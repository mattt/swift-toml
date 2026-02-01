import CTomlPlusPlus
import Foundation

/// A decoder that converts TOML format data into Swift values.
///
/// This decoder conforms to the [TOML v1.0.0 specification](https://toml.io/en/v1.0.0).
/// It supports all TOML data types including strings, integers, floats, booleans,
/// dates and times, arrays, and tables.
///
/// ## Usage
///
/// ```swift
/// struct Config: Decodable {
///     var title: String
///     var port: Int
/// }
///
/// let toml = """
/// title = "My App"
/// port = 8080
/// """
///
/// let decoder = TOMLDecoder()
/// let config = try decoder.decode(Config.self, from: toml)
/// ```
///
/// ## Date Decoding
///
/// The decoder supports multiple date formats through ``DateDecodingStrategy``:
///
/// ```swift
/// let decoder = TOMLDecoder()
/// decoder.dateDecodingStrategy = .iso8601
/// ```
///
/// ## Key Decoding
///
/// Use ``KeyDecodingStrategy`` to automatically convert between naming conventions:
///
/// ```swift
/// let decoder = TOMLDecoder()
/// decoder.keyDecodingStrategy = .convertFromSnakeCase
/// ```
public final class TOMLDecoder {

    // MARK: - Date Decoding Strategy

    /// The strategy used when decoding `Date` values.
    ///
    /// TOML natively supports date-time values, which are decoded according
    /// to this strategy.
    public enum DateDecodingStrategy: Sendable {
        /// Decode dates from ISO 8601 formatted strings or TOML offset date-times.
        ///
        /// This is the default strategy and works with TOML's native date-time types.
        case iso8601

        /// Decode dates from a floating-point number of seconds since January 1, 1970.
        case secondsSince1970

        /// Decode dates from a floating-point number of milliseconds since January 1, 1970.
        case millisecondsSince1970
    }

    // MARK: - Key Decoding Strategy

    /// The strategy used when decoding keys from TOML.
    ///
    /// Use this to automatically convert between different naming conventions
    /// in your TOML files and Swift types.
    public enum KeyDecodingStrategy: Sendable {
        /// Use the keys specified in the TOML file without modification.
        case useDefaultKeys

        /// Convert keys from snake_case to camelCase.
        ///
        /// For example, `user_name` in TOML becomes `userName` in Swift.
        case convertFromSnakeCase
    }

    // MARK: - Decoding Limits

    /// Limits for decoding to prevent resource exhaustion.
    ///
    /// Use this to protect against malicious or malformed input when parsing
    /// untrusted TOML data.
    public struct DecodingLimits: Sendable {
        /// Maximum input size in bytes.
        public var maxInputSize: Int

        /// Maximum nesting depth for tables and arrays.
        public var maxDepth: Int

        /// Maximum number of keys in a single table.
        public var maxTableKeys: Int

        /// Maximum number of elements in an array.
        public var maxArrayLength: Int

        /// Maximum length of a string value in characters.
        public var maxStringLength: Int

        /// Default decoding limits suitable for most use cases.
        ///
        /// - `maxInputSize`: 10 MB
        /// - `maxDepth`: 128
        /// - `maxTableKeys`: 10,000
        /// - `maxArrayLength`: 100,000
        /// - `maxStringLength`: 1 MB
        public static let `default` = DecodingLimits(
            maxInputSize: 10 * 1024 * 1024,
            maxDepth: 128,
            maxTableKeys: 10_000,
            maxArrayLength: 100_000,
            maxStringLength: 1024 * 1024
        )

        /// Decoding limits that impose no restrictions.
        ///
        /// - Warning: This configuration is unsafe for untrusted input
        ///   and should only be used with data from trusted sources.
        ///   Without limits, malicious input can cause excessive memory usage,
        ///   stack overflow from deep nesting, or denial-of-service attacks.
        ///
        /// Use this only when you have full control over the input data
        /// and need to decode arbitrarily large or complex TOML structures.
        ///
        /// For production use with external input, use ``default`` or
        /// ``init(maxInputSize:maxDepth:maxTableKeys:maxArrayLength:maxStringLength:)``
        /// with appropriate limits instead.
        public static let unlimited = DecodingLimits(
            maxInputSize: .max,
            maxDepth: .max,
            maxTableKeys: .max,
            maxArrayLength: .max,
            maxStringLength: .max
        )

        /// Creates new decoding limits with the specified values.
        public init(
            maxInputSize: Int,
            maxDepth: Int,
            maxTableKeys: Int,
            maxArrayLength: Int,
            maxStringLength: Int
        ) {
            self.maxInputSize = maxInputSize
            self.maxDepth = maxDepth
            self.maxTableKeys = maxTableKeys
            self.maxArrayLength = maxArrayLength
            self.maxStringLength = maxStringLength
        }
    }

    // MARK: - Properties

    /// The strategy used when decoding `Date` values.
    public var dateDecodingStrategy: DateDecodingStrategy = .iso8601

    /// The strategy used when decoding keys.
    public var keyDecodingStrategy: KeyDecodingStrategy = .useDefaultKeys

    /// The limits applied during decoding.
    public var limits: DecodingLimits = .default

    /// A dictionary of contextual information to pass to the decoder.
    public var userInfo: [CodingUserInfoKey: any Sendable] = [:]

    // MARK: - Initialization

    /// Creates a new TOML decoder.
    public init() {}

    // MARK: - Decoding

    /// Decodes a value of the given type from TOML data.
    ///
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - data: UTF-8 encoded TOML data.
    /// - Returns: The decoded value.
    /// - Throws: ``TOMLDecodingError`` if parsing or decoding fails.
    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard let string = String(data: data, encoding: .utf8) else {
            throw TOMLDecodingError.invalidData("Unable to convert data to UTF-8 string")
        }
        return try decode(type, from: string)
    }

    /// Decodes a value of the given type from a TOML string.
    ///
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - string: A string containing TOML content.
    /// - Returns: The decoded value.
    /// - Throws: ``TOMLDecodingError`` if parsing or decoding fails.
    public func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        if string.utf8.count > limits.maxInputSize {
            throw TOMLDecodingError.invalidData("Input exceeds maximum size of \(limits.maxInputSize) bytes")
        }

        let value = try parseToValue(string)
        let decoder = _TOMLDecoder(
            value: value,
            codingPath: [],
            userInfo: userInfo.reduce(into: [:]) { $0[$1.key] = $1.value },
            options: DecodingOptions(
                dateDecodingStrategy: dateDecodingStrategy,
                keyDecodingStrategy: keyDecodingStrategy
            )
        )
        return try T(from: decoder)
    }

    // MARK: - Private

    private func parseToValue(_ string: String) throws -> TOMLValue {
        var result = string.withCString { cString in
            ctoml_parse(cString, string.utf8.count)
        }
        defer { ctoml_free_result(&result) }

        guard result.success else {
            if let errorMsg = result.error_message {
                throw TOMLDecodingError.invalidSyntax(
                    line: Int(result.error_line),
                    column: Int(result.error_column),
                    message: String(cString: errorMsg)
                )
            }
            throw TOMLDecodingError.invalidData("Unknown parse error")
        }

        return try convertNode(result.root, depth: 0)
    }

    private func decodeCTomlString(_ strData: CTomlString) -> String {
        if let data = strData.data {
            let buffer = UnsafeRawBufferPointer(start: data, count: strData.length)
            return String(decoding: buffer, as: UTF8.self)
        }
        return ""
    }

    private func convertNode(_ node: CTomlNode, depth: Int) throws -> TOMLValue {
        guard depth < limits.maxDepth else {
            throw TOMLDecodingError.invalidData("Maximum nesting depth of \(limits.maxDepth) exceeded")
        }

        switch node.type {
        case CTOML_STRING:
            let str = decodeCTomlString(node.data.string_value)
            guard str.count <= limits.maxStringLength else {
                throw TOMLDecodingError.invalidData(
                    "String exceeds maximum length of \(limits.maxStringLength) characters"
                )
            }
            return .string(str)

        case CTOML_INTEGER:
            return .integer(node.data.integer_value)

        case CTOML_FLOAT:
            return .float(node.data.float_value)

        case CTOML_BOOLEAN:
            return .boolean(node.data.boolean_value)

        case CTOML_DATE:
            let d = node.data.date_value
            return .localDate(
                LocalDate(
                    year: Int(d.year),
                    month: Int(d.month),
                    day: Int(d.day)
                )
            )

        case CTOML_TIME:
            let t = node.data.time_value
            return .localTime(
                LocalTime(
                    hour: Int(t.hour),
                    minute: Int(t.minute),
                    second: Int(t.second),
                    nanosecond: Int(t.nanosecond)
                )
            )

        case CTOML_DATETIME:
            let dt = node.data.datetime_value
            if dt.has_offset {
                var components = DateComponents()
                components.year = Int(dt.date.year)
                components.month = Int(dt.date.month)
                components.day = Int(dt.date.day)
                components.hour = Int(dt.time.hour)
                components.minute = Int(dt.time.minute)
                components.second = Int(dt.time.second)
                components.nanosecond = Int(dt.time.nanosecond)
                components.timeZone = TimeZone(secondsFromGMT: Int(dt.offset_minutes) * 60)

                if let date = Calendar(identifier: .gregorian).date(from: components) {
                    return .offsetDateTime(date)
                }
            }
            return .localDateTime(
                LocalDateTime(
                    year: Int(dt.date.year),
                    month: Int(dt.date.month),
                    day: Int(dt.date.day),
                    hour: Int(dt.time.hour),
                    minute: Int(dt.time.minute),
                    second: Int(dt.time.second),
                    nanosecond: Int(dt.time.nanosecond)
                )
            )

        case CTOML_ARRAY:
            let count = node.data.array_value.count
            guard count <= limits.maxArrayLength else {
                throw TOMLDecodingError.invalidData("Array exceeds maximum length of \(limits.maxArrayLength) elements")
            }
            var values: [TOMLValue] = []
            if let elements = node.data.array_value.elements {
                for i in 0 ..< count {
                    try values.append(convertNode(elements[i], depth: depth + 1))
                }
            }
            return .array(values)

        case CTOML_TABLE:
            let count = node.data.table_value.count
            guard count <= limits.maxTableKeys else {
                throw TOMLDecodingError.invalidData("Table exceeds maximum of \(limits.maxTableKeys) keys")
            }
            var dict: [String: TOMLValue] = [:]
            if let keys = node.data.table_value.keys, let tableValues = node.data.table_value.values {
                for i in 0 ..< count {
                    let key = decodeCTomlString(keys[i])
                    dict[key] = try convertNode(tableValues[i], depth: depth + 1)
                }
            }
            return .table(dict)

        case CTOML_NONE:
            return .string("")

        default:
            return .string("")
        }
    }
}

// MARK: - Decoding Errors

/// Errors that can occur during TOML decoding.
public enum TOMLDecodingError: Error, CustomStringConvertible, Sendable {
    /// Invalid TOML syntax at the specified location.
    case invalidSyntax(line: Int, column: Int, message: String)

    /// Type mismatch during decoding.
    case typeMismatch(expected: String, found: String, codingPath: [any CodingKey])

    /// Required key not found in the table.
    case keyNotFound(key: any CodingKey, availableKeys: [String])

    /// Expected value not found at the specified path.
    case valueNotFound(type: String, codingPath: [any CodingKey])

    /// Data is corrupted or invalid.
    case dataCorrupted(message: String, codingPath: [any CodingKey])

    /// The input data is invalid.
    case invalidData(String)

    public var description: String {
        switch self {
        case .invalidSyntax(let line, let column, let message):
            return "Invalid TOML syntax at line \(line), column \(column): \(message)"
        case .typeMismatch(let expected, let found, let codingPath):
            let path = codingPath.map(\.stringValue).joined(separator: ".")
            return "Type mismatch at '\(path)': expected \(expected), found \(found)"
        case .keyNotFound(let key, let availableKeys):
            return "Key '\(key.stringValue)' not found. Available keys: \(availableKeys.joined(separator: ", "))"
        case .valueNotFound(let type, let codingPath):
            let path = codingPath.map(\.stringValue).joined(separator: ".")
            return "Value of type \(type) not found at '\(path)'"
        case .dataCorrupted(let message, let codingPath):
            let path = codingPath.map(\.stringValue).joined(separator: ".")
            return "Data corrupted at '\(path)': \(message)"
        case .invalidData(let message):
            return "Invalid data: \(message)"
        }
    }
}

// MARK: - Internal Types

struct DecodingOptions {
    let dateDecodingStrategy: TOMLDecoder.DateDecodingStrategy
    let keyDecodingStrategy: TOMLDecoder.KeyDecodingStrategy
}

// MARK: - Internal Decoder

final class _TOMLDecoder: Decoder {
    let value: TOMLValue
    var codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any]
    let options: DecodingOptions

    init(value: TOMLValue, codingPath: [any CodingKey], userInfo: [CodingUserInfoKey: Any], options: DecodingOptions) {
        self.value = value
        self.codingPath = codingPath
        self.userInfo = userInfo
        self.options = options
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard case .table(let dict) = value else {
            throw DecodingError.typeMismatch(
                [String: Any].self,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Expected table, found \(valueTypeName(value))"
                )
            )
        }

        let container = TOMLKeyedDecodingContainer<Key>(
            dict: dict,
            codingPath: codingPath,
            userInfo: userInfo,
            options: options
        )
        return KeyedDecodingContainer(container)
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        guard case .array(let arr) = value else {
            throw DecodingError.typeMismatch(
                [Any].self,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Expected array, found \(valueTypeName(value))"
                )
            )
        }

        return TOMLUnkeyedDecodingContainer(
            array: arr,
            codingPath: codingPath,
            userInfo: userInfo,
            options: options
        )
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        TOMLSingleValueDecodingContainer(
            value: value,
            codingPath: codingPath,
            userInfo: userInfo,
            options: options
        )
    }
}

// MARK: - Helpers

private func valueTypeName(_ value: TOMLValue) -> String {
    switch value {
    case .string: return "string"
    case .integer: return "integer"
    case .float: return "float"
    case .boolean: return "boolean"
    case .offsetDateTime: return "offset date-time"
    case .localDateTime: return "local date-time"
    case .localDate: return "local date"
    case .localTime: return "local time"
    case .array: return "array"
    case .table: return "table"
    }
}

// MARK: - Keyed Decoding Container

private struct TOMLKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let dict: [String: TOMLValue]
    var codingPath: [any CodingKey]
    let userInfo: [CodingUserInfoKey: Any]
    let options: DecodingOptions

    var allKeys: [Key] {
        dict.keys.compactMap { Key(stringValue: $0) }
    }

    func contains(_ key: Key) -> Bool {
        dict[convertKey(key)] != nil
    }

    private func convertKey(_ key: Key) -> String {
        switch options.keyDecodingStrategy {
        case .useDefaultKeys:
            return key.stringValue
        case .convertFromSnakeCase:
            return key.stringValue.convertFromSnakeCase()
        }
    }

    private func getValue(forKey key: Key) throws -> TOMLValue {
        let keyString = convertKey(key)
        guard let value = dict[keyString] else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Key '\(keyString)' not found"
                )
            )
        }
        return value
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        !contains(key)
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        let value = try getValue(forKey: key)
        guard case .boolean(let b) = value else {
            throw typeMismatchError(type, value: value, key: key)
        }
        return b
    }

    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        let value = try getValue(forKey: key)
        guard case .string(let s) = value else {
            throw typeMismatchError(type, value: value, key: key)
        }
        return s
    }

    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
        let value = try getValue(forKey: key)
        switch value {
        case .float(let f): return f
        case .integer(let i): return Double(i)
        default: throw typeMismatchError(type, value: value, key: key)
        }
    }

    func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
        Float(try decode(Double.self, forKey: key))
    }

    func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
        Int(try decode(Int64.self, forKey: key))
    }

    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
        Int8(try decode(Int64.self, forKey: key))
    }

    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
        Int16(try decode(Int64.self, forKey: key))
    }

    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
        Int32(try decode(Int64.self, forKey: key))
    }

    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
        let value = try getValue(forKey: key)
        guard case .integer(let i) = value else {
            throw typeMismatchError(type, value: value, key: key)
        }
        return i
    }

    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
        UInt(try decode(Int64.self, forKey: key))
    }

    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
        UInt8(try decode(Int64.self, forKey: key))
    }

    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
        UInt16(try decode(Int64.self, forKey: key))
    }

    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
        UInt32(try decode(Int64.self, forKey: key))
    }

    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
        UInt64(try decode(Int64.self, forKey: key))
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        let value = try getValue(forKey: key)

        if type == Date.self {
            return try decodeDate(from: value, forKey: key) as! T
        }
        if type == LocalDateTime.self {
            guard case .localDateTime(let dt) = value else {
                throw typeMismatchError(type, value: value, key: key)
            }
            return dt as! T
        }
        if type == LocalDate.self {
            guard case .localDate(let d) = value else {
                throw typeMismatchError(type, value: value, key: key)
            }
            return d as! T
        }
        if type == LocalTime.self {
            guard case .localTime(let t) = value else {
                throw typeMismatchError(type, value: value, key: key)
            }
            return t as! T
        }

        let decoder = _TOMLDecoder(
            value: value,
            codingPath: codingPath + [key],
            userInfo: userInfo,
            options: options
        )
        return try T(from: decoder)
    }

    private func decodeDate(from value: TOMLValue, forKey key: Key) throws -> Date {
        switch value {
        case .offsetDateTime(let date):
            return date
        case .localDateTime(let dt):
            var components = DateComponents()
            components.year = dt.year
            components.month = dt.month
            components.day = dt.day
            components.hour = dt.hour
            components.minute = dt.minute
            components.second = dt.second
            components.nanosecond = dt.nanosecond
            guard let date = Calendar(identifier: .gregorian).date(from: components) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: codingPath + [key],
                        debugDescription: "Invalid date components"
                    )
                )
            }
            return date
        case .localDate(let d):
            var components = DateComponents()
            components.year = d.year
            components.month = d.month
            components.day = d.day
            guard let date = Calendar(identifier: .gregorian).date(from: components) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: codingPath + [key],
                        debugDescription: "Invalid date components"
                    )
                )
            }
            return date
        case .float(let f):
            switch options.dateDecodingStrategy {
            case .secondsSince1970:
                return Date(timeIntervalSince1970: f)
            case .millisecondsSince1970:
                return Date(timeIntervalSince1970: f / 1000)
            default:
                throw typeMismatchError(Date.self, value: value, key: key)
            }
        default:
            throw typeMismatchError(Date.self, value: value, key: key)
        }
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type,
        forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> {
        let value = try getValue(forKey: key)
        guard case .table(let dict) = value else {
            throw typeMismatchError([String: Any].self, value: value, key: key)
        }

        let container = TOMLKeyedDecodingContainer<NestedKey>(
            dict: dict,
            codingPath: codingPath + [key],
            userInfo: userInfo,
            options: options
        )
        return KeyedDecodingContainer(container)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        let value = try getValue(forKey: key)
        guard case .array(let arr) = value else {
            throw typeMismatchError([Any].self, value: value, key: key)
        }

        return TOMLUnkeyedDecodingContainer(
            array: arr,
            codingPath: codingPath + [key],
            userInfo: userInfo,
            options: options
        )
    }

    func superDecoder() throws -> any Decoder {
        _TOMLDecoder(
            value: .table(dict),
            codingPath: codingPath,
            userInfo: userInfo,
            options: options
        )
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        let value = try getValue(forKey: key)
        return _TOMLDecoder(
            value: value,
            codingPath: codingPath + [key],
            userInfo: userInfo,
            options: options
        )
    }

    private func typeMismatchError<T>(_ type: T.Type, value: TOMLValue, key: Key) -> DecodingError {
        DecodingError.typeMismatch(
            type,
            DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription: "Expected \(type), found \(valueTypeName(value))"
            )
        )
    }
}

// MARK: - Unkeyed Decoding Container

private struct TOMLUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    let array: [TOMLValue]
    var codingPath: [any CodingKey]
    let userInfo: [CodingUserInfoKey: Any]
    let options: DecodingOptions

    var count: Int? { array.count }
    var isAtEnd: Bool { currentIndex >= array.count }
    var currentIndex: Int = 0

    private mutating func nextValue() throws -> TOMLValue {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(
                Any.self,
                DecodingError.Context(
                    codingPath: codingPath + [TOMLCodingKey(index: currentIndex)],
                    debugDescription: "Unkeyed container is at end"
                )
            )
        }
        let value = array[currentIndex]
        currentIndex += 1
        return value
    }

    mutating func decodeNil() throws -> Bool {
        false
    }

    mutating func decode(_ type: Bool.Type) throws -> Bool {
        let value = try nextValue()
        guard case .boolean(let b) = value else {
            throw typeMismatchError(type, value: value)
        }
        return b
    }

    mutating func decode(_ type: String.Type) throws -> String {
        let value = try nextValue()
        guard case .string(let s) = value else {
            throw typeMismatchError(type, value: value)
        }
        return s
    }

    mutating func decode(_ type: Double.Type) throws -> Double {
        let value = try nextValue()
        switch value {
        case .float(let f): return f
        case .integer(let i): return Double(i)
        default: throw typeMismatchError(type, value: value)
        }
    }

    mutating func decode(_ type: Float.Type) throws -> Float {
        Float(try decode(Double.self))
    }

    mutating func decode(_ type: Int.Type) throws -> Int {
        Int(try decode(Int64.self))
    }

    mutating func decode(_ type: Int8.Type) throws -> Int8 {
        Int8(try decode(Int64.self))
    }

    mutating func decode(_ type: Int16.Type) throws -> Int16 {
        Int16(try decode(Int64.self))
    }

    mutating func decode(_ type: Int32.Type) throws -> Int32 {
        Int32(try decode(Int64.self))
    }

    mutating func decode(_ type: Int64.Type) throws -> Int64 {
        let value = try nextValue()
        guard case .integer(let i) = value else {
            throw typeMismatchError(type, value: value)
        }
        return i
    }

    mutating func decode(_ type: UInt.Type) throws -> UInt {
        UInt(try decode(Int64.self))
    }

    mutating func decode(_ type: UInt8.Type) throws -> UInt8 {
        UInt8(try decode(Int64.self))
    }

    mutating func decode(_ type: UInt16.Type) throws -> UInt16 {
        UInt16(try decode(Int64.self))
    }

    mutating func decode(_ type: UInt32.Type) throws -> UInt32 {
        UInt32(try decode(Int64.self))
    }

    mutating func decode(_ type: UInt64.Type) throws -> UInt64 {
        UInt64(try decode(Int64.self))
    }

    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let value = try nextValue()

        if type == Date.self {
            return try decodeDate(from: value) as! T
        }
        if type == LocalDateTime.self {
            guard case .localDateTime(let dt) = value else {
                throw typeMismatchError(type, value: value)
            }
            return dt as! T
        }
        if type == LocalDate.self {
            guard case .localDate(let d) = value else {
                throw typeMismatchError(type, value: value)
            }
            return d as! T
        }
        if type == LocalTime.self {
            guard case .localTime(let t) = value else {
                throw typeMismatchError(type, value: value)
            }
            return t as! T
        }

        let decoder = _TOMLDecoder(
            value: value,
            codingPath: codingPath + [TOMLCodingKey(index: currentIndex - 1)],
            userInfo: userInfo,
            options: options
        )
        return try T(from: decoder)
    }

    private func decodeDate(from value: TOMLValue) throws -> Date {
        switch value {
        case .offsetDateTime(let date):
            return date
        case .localDateTime(let dt):
            var components = DateComponents()
            components.year = dt.year
            components.month = dt.month
            components.day = dt.day
            components.hour = dt.hour
            components.minute = dt.minute
            components.second = dt.second
            components.nanosecond = dt.nanosecond
            guard let date = Calendar(identifier: .gregorian).date(from: components) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: codingPath + [TOMLCodingKey(index: currentIndex - 1)],
                        debugDescription: "Invalid date components"
                    )
                )
            }
            return date
        case .localDate(let d):
            var components = DateComponents()
            components.year = d.year
            components.month = d.month
            components.day = d.day
            guard let date = Calendar(identifier: .gregorian).date(from: components) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: codingPath + [TOMLCodingKey(index: currentIndex - 1)],
                        debugDescription: "Invalid date components"
                    )
                )
            }
            return date
        default:
            throw typeMismatchError(Date.self, value: value)
        }
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type
    ) throws -> KeyedDecodingContainer<NestedKey> {
        let value = try nextValue()
        guard case .table(let dict) = value else {
            throw typeMismatchError([String: Any].self, value: value)
        }

        let container = TOMLKeyedDecodingContainer<NestedKey>(
            dict: dict,
            codingPath: codingPath + [TOMLCodingKey(index: currentIndex - 1)],
            userInfo: userInfo,
            options: options
        )
        return KeyedDecodingContainer(container)
    }

    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        let value = try nextValue()
        guard case .array(let arr) = value else {
            throw typeMismatchError([Any].self, value: value)
        }

        return TOMLUnkeyedDecodingContainer(
            array: arr,
            codingPath: codingPath + [TOMLCodingKey(index: currentIndex - 1)],
            userInfo: userInfo,
            options: options
        )
    }

    mutating func superDecoder() throws -> any Decoder {
        let value = try nextValue()
        return _TOMLDecoder(
            value: value,
            codingPath: codingPath + [TOMLCodingKey(index: currentIndex - 1)],
            userInfo: userInfo,
            options: options
        )
    }

    private func typeMismatchError<T>(_ type: T.Type, value: TOMLValue) -> DecodingError {
        DecodingError.typeMismatch(
            type,
            DecodingError.Context(
                codingPath: codingPath + [TOMLCodingKey(index: currentIndex)],
                debugDescription: "Expected \(type), found \(valueTypeName(value))"
            )
        )
    }
}

// MARK: - Single Value Decoding Container

private struct TOMLSingleValueDecodingContainer: SingleValueDecodingContainer {
    let value: TOMLValue
    var codingPath: [any CodingKey]
    let userInfo: [CodingUserInfoKey: Any]
    let options: DecodingOptions

    func decodeNil() -> Bool {
        false
    }

    func decode(_ type: Bool.Type) throws -> Bool {
        guard case .boolean(let b) = value else {
            throw typeMismatchError(type)
        }
        return b
    }

    func decode(_ type: String.Type) throws -> String {
        guard case .string(let s) = value else {
            throw typeMismatchError(type)
        }
        return s
    }

    func decode(_ type: Double.Type) throws -> Double {
        switch value {
        case .float(let f): return f
        case .integer(let i): return Double(i)
        default: throw typeMismatchError(type)
        }
    }

    func decode(_ type: Float.Type) throws -> Float {
        Float(try decode(Double.self))
    }

    func decode(_ type: Int.Type) throws -> Int {
        Int(try decode(Int64.self))
    }

    func decode(_ type: Int8.Type) throws -> Int8 {
        Int8(try decode(Int64.self))
    }

    func decode(_ type: Int16.Type) throws -> Int16 {
        Int16(try decode(Int64.self))
    }

    func decode(_ type: Int32.Type) throws -> Int32 {
        Int32(try decode(Int64.self))
    }

    func decode(_ type: Int64.Type) throws -> Int64 {
        guard case .integer(let i) = value else {
            throw typeMismatchError(type)
        }
        return i
    }

    func decode(_ type: UInt.Type) throws -> UInt {
        UInt(try decode(Int64.self))
    }

    func decode(_ type: UInt8.Type) throws -> UInt8 {
        UInt8(try decode(Int64.self))
    }

    func decode(_ type: UInt16.Type) throws -> UInt16 {
        UInt16(try decode(Int64.self))
    }

    func decode(_ type: UInt32.Type) throws -> UInt32 {
        UInt32(try decode(Int64.self))
    }

    func decode(_ type: UInt64.Type) throws -> UInt64 {
        UInt64(try decode(Int64.self))
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        if type == Date.self {
            return try decodeDate() as! T
        }
        if type == LocalDateTime.self {
            guard case .localDateTime(let dt) = value else {
                throw typeMismatchError(type)
            }
            return dt as! T
        }
        if type == LocalDate.self {
            guard case .localDate(let d) = value else {
                throw typeMismatchError(type)
            }
            return d as! T
        }
        if type == LocalTime.self {
            guard case .localTime(let t) = value else {
                throw typeMismatchError(type)
            }
            return t as! T
        }

        let decoder = _TOMLDecoder(
            value: value,
            codingPath: codingPath,
            userInfo: userInfo,
            options: options
        )
        return try T(from: decoder)
    }

    private func decodeDate() throws -> Date {
        switch value {
        case .offsetDateTime(let date):
            return date
        case .localDateTime(let dt):
            var components = DateComponents()
            components.year = dt.year
            components.month = dt.month
            components.day = dt.day
            components.hour = dt.hour
            components.minute = dt.minute
            components.second = dt.second
            components.nanosecond = dt.nanosecond
            guard let date = Calendar(identifier: .gregorian).date(from: components) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: codingPath,
                        debugDescription: "Invalid date components"
                    )
                )
            }
            return date
        case .localDate(let d):
            var components = DateComponents()
            components.year = d.year
            components.month = d.month
            components.day = d.day
            guard let date = Calendar(identifier: .gregorian).date(from: components) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: codingPath,
                        debugDescription: "Invalid date components"
                    )
                )
            }
            return date
        default:
            throw typeMismatchError(Date.self)
        }
    }

    private func typeMismatchError<T>(_ type: T.Type) -> DecodingError {
        DecodingError.typeMismatch(
            type,
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Expected \(type), found \(valueTypeName(value))"
            )
        )
    }
}

// MARK: - String Extensions

private extension String {
    func convertFromSnakeCase() -> String {
        var result = ""
        var capitalizeNext = false
        for char in self {
            if char == "_" {
                capitalizeNext = true
            } else if capitalizeNext {
                result += char.uppercased()
                capitalizeNext = false
            } else {
                result.append(char)
            }
        }
        return result
    }
}
