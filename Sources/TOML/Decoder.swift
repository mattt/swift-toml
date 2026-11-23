import CTomlPlusPlus
import Foundation

/// A decoder that converts TOML format data into Swift values.
///
/// This decoder conforms to the [TOML v1.1.0 specification](https://toml.io/en/v1.1.0).
/// It also reads [TOML v1.0.0](https://toml.io/en/v1.0.0) documents.
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
/// `Date` can't represent a leap second,
/// so an offset date-time with second 60, such as `2016-12-31T23:59:60Z`,
/// decodes as the following second, `2017-01-01T00:00:00Z`.
/// ``LocalTime`` and ``LocalDateTime`` keep second 60.
/// The parser accepts second 60 at minute 59
/// without checking that a leap second occurred.
///
/// ## Key Decoding
///
/// Use ``KeyDecodingStrategy`` to automatically convert between naming conventions:
///
/// ```swift
/// let decoder = TOMLDecoder()
/// decoder.keyDecodingStrategy = .convertFromSnakeCase
/// ```
///
/// ## URL Decoding
///
/// The decoder reads a `URL` from either form that ``TOMLEncoder`` writes:
/// a string, such as `url = "https://example.com/"`,
/// or the table that `URL`'s own `Encodable` conformance produces.
/// A string that `URL(string:)` can't parse throws
/// `DecodingError.dataCorrupted`.
public final class TOMLDecoder {

    // MARK: - Date Decoding Strategy

    /// The strategy used when decoding `Date` values.
    ///
    /// TOML natively supports date-time values, which are decoded according
    /// to this strategy.
    public enum DateDecodingStrategy: Sendable {
        /// Decode dates from TOML date-time values.
        ///
        /// An offset date-time decodes as the instant that it names.
        /// A local date-time decodes as that time in the current time zone,
        /// and a local date decodes as midnight at the start of that day
        /// in the current time zone.
        /// This strategy doesn't parse strings.
        ///
        /// This is the default strategy.
        case iso8601

        /// Decode dates from a number of seconds since January 1, 1970,
        /// written as an integer or a float.
        ///
        /// This strategy also decodes TOML date-time values, as ``iso8601`` does.
        case secondsSince1970

        /// Decode dates from a number of milliseconds since January 1, 1970,
        /// written as an integer or a float.
        ///
        /// This strategy also decodes TOML date-time values, as ``iso8601`` does.
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
        /// Leading and trailing underscores stay,
        /// so `_user_name_` becomes `_userName_`.
        ///
        /// As with `JSONDecoder`, this strategy doesn't change the keys
        /// of a dictionary with `String` keys, such as `[String: String]`.
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
        /// The root table has depth 0.
        ///
        /// - Note: For input within ``maxInputSize``,
        ///   the parser rejects documents nested more than about 128 levels deep
        ///   before this limit applies, so they throw
        ///   ``TOMLDecodingError/invalidSyntax(line:column:message:)``
        ///   whatever the value of this property.
        ///   For example, 129 nested empty arrays throw `invalidSyntax`,
        ///   even with the default limits.
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
        /// The parser's nesting ceiling of about 128 levels still applies;
        /// see ``maxDepth``.
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
    ///     The data can start with one UTF-8 byte order mark.
    /// - Returns: The decoded value.
    /// - Throws: ``TOMLDecodingError`` if parsing or decoding fails,
    ///   or if `data` is not valid UTF-8.
    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if data.count > limits.maxInputSize {
            throw TOMLDecodingError.invalidData("Input exceeds maximum size of \(limits.maxInputSize) bytes")
        }

        // Convert the bytes without Foundation, which can remove a leading
        // byte order mark and differs between platforms.
        // Decoding replaces each invalid sequence with U+FFFD,
        // so the result has the same bytes only if the input is valid UTF-8.
        let string = String(decoding: data, as: UTF8.self)
        guard string.utf8.elementsEqual(data) else {
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
        return try _TOMLDecoder.decode(
            type,
            from: value,
            codingPath: [],
            userInfo: userInfo.reduce(into: [:]) { $0[$1.key] = $1.value },
            options: DecodingOptions(
                dateDecodingStrategy: dateDecodingStrategy,
                keyDecodingStrategy: keyDecodingStrategy
            )
        )
    }

    // MARK: - Private

    private func parseToValue(_ string: String) throws -> TOMLValue {
        var result = string.withCString { cString in
            ctoml_parse(cString, string.utf8.count)
        }
        defer { ctoml_free_result(&result) }

        guard result.success else {
            if let errorMsg = result.error_message {
                let message = String(cString: errorMsg)
                let line = Int(result.error_line)
                let column = Int(result.error_column)
                if line > 0 || column > 0 {
                    throw TOMLDecodingError.invalidSyntax(line: line, column: column, message: message)
                }
                throw TOMLDecodingError.invalidData(message)
            }
            throw TOMLDecodingError.invalidData("Unknown parse error")
        }

        return try convertNode(result.root)
    }

    private func decodeCTomlString(_ strData: CTomlString) -> String {
        if let data = strData.data {
            let buffer = UnsafeRawBufferPointer(start: data, count: strData.length)
            return String(decoding: buffer, as: UTF8.self)
        }
        return ""
    }

    /// Converts a parsed node and its descendants to a `TOMLValue`.
    ///
    /// The conversion keeps an explicit stack of the arrays and tables
    /// that it is building, instead of recursing,
    /// so that deeply nested documents do not overflow a small thread stack.
    /// It visits nodes in depth-first order, children in index order,
    /// and checks each node's depth and size limits when it visits the node.
    private func convertNode(_ root: CTomlNode) throws -> TOMLValue {
        var stack: [ContainerFrame] = []

        switch try visit(root, depth: 0) {
        case .value(let value):
            return value
        case .container(let frame):
            stack.append(frame)
        }

        // The stack is never empty here: the loop returns
        // when it finishes the root container.
        while true {
            let top = stack.count - 1
            guard let child = stack[top].nextChild(decodeKey: decodeCTomlString) else {
                let value = stack.removeLast().value
                if stack.isEmpty {
                    return value
                }
                stack[top - 1].append(value)
                continue
            }

            switch try visit(child, depth: stack[top].depth + 1) {
            case .value(let value):
                stack[top].append(value)
            case .container(let frame):
                stack.append(frame)
            }
        }
    }

    /// The result of visiting a node:
    /// either a finished value or an array or table to fill.
    private enum Visit {
        case value(TOMLValue)
        case container(ContainerFrame)
    }

    /// An array or table that ``convertNode(_:)`` is building.
    private struct ContainerFrame {
        let depth: Int
        private let elements: UnsafeMutablePointer<CTomlNode>?
        private let keys: UnsafeMutablePointer<CTomlString>?
        private let count: Int
        private var index = 0
        private var pendingKey = ""
        private var array: [TOMLValue]?
        private var table: [String: TOMLValue]?

        init(array node: CTomlArrayData, depth: Int) {
            self.depth = depth
            self.elements = node.elements
            self.keys = nil
            self.count = node.elements == nil ? 0 : node.count
            self.array = []
        }

        init(table node: CTomlTableData, depth: Int) {
            self.depth = depth
            let hasEntries = node.keys != nil && node.values != nil
            self.elements = node.values
            self.keys = node.keys
            self.count = hasEntries ? node.count : 0
            self.table = [:]
        }

        /// Returns the next child node to convert, or `nil` if none remain.
        /// For a table, it also records the child's key.
        mutating func nextChild(decodeKey: (CTomlString) -> String) -> CTomlNode? {
            guard index < count, let elements else { return nil }
            if let keys {
                pendingKey = decodeKey(keys[index])
            }
            defer { index += 1 }
            return elements[index]
        }

        /// Adds the converted value of the child that ``nextChild(decodeKey:)`` returned last.
        mutating func append(_ value: TOMLValue) {
            if table != nil {
                table?[pendingKey] = value
            } else {
                array?.append(value)
            }
        }

        var value: TOMLValue {
            if let table {
                return .table(table)
            }
            return .array(array ?? [])
        }
    }

    /// Checks a node's limits, then converts a scalar node to a value
    /// or starts an array or table.
    private func visit(_ node: CTomlNode, depth: Int) throws -> Visit {
        guard depth < limits.maxDepth else {
            throw TOMLDecodingError.invalidData("Maximum nesting depth of \(limits.maxDepth) exceeded")
        }

        switch node.type {
        case CTOML_ARRAY:
            let count = node.data.array_value.count
            guard count <= limits.maxArrayLength else {
                throw TOMLDecodingError.invalidData("Array exceeds maximum length of \(limits.maxArrayLength) elements")
            }
            return .container(ContainerFrame(array: node.data.array_value, depth: depth))

        case CTOML_TABLE:
            let count = node.data.table_value.count
            guard count <= limits.maxTableKeys else {
                throw TOMLDecodingError.invalidData("Table exceeds maximum of \(limits.maxTableKeys) keys")
            }
            return .container(ContainerFrame(table: node.data.table_value, depth: depth))

        default:
            return try .value(convertScalar(node))
        }
    }

    /// Converts a node that is not an array or a table.
    private func convertScalar(_ node: CTomlNode) throws -> TOMLValue {
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

                // `TimeZone(secondsFromGMT:)` rejects offsets above 18 hours,
                // but TOML allows offsets up to 23:59,
                // so read the components as UTC and then apply the offset.
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                guard let utcDate = calendar.date(from: components) else {
                    throw TOMLDecodingError.invalidData("Offset date-time is not a valid date")
                }
                let offset = TimeInterval(Int(dt.offset_minutes) * 60)
                return .offsetDateTime(utcDate.addingTimeInterval(-offset))
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

        case CTOML_NONE:
            return .string("")

        // We can't use `@unknown default` here because
        // the C enum imports as a plain enum and exhaustiveness isn't tracked.
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

    /// Whether a keyed container for this value keeps the table's keys
    /// instead of applying the key decoding strategy.
    let keepsTableKeys: Bool

    init(
        value: TOMLValue,
        codingPath: [any CodingKey],
        userInfo: [CodingUserInfoKey: Any],
        options: DecodingOptions,
        keepsTableKeys: Bool = false
    ) {
        self.value = value
        self.codingPath = codingPath
        self.userInfo = userInfo
        self.options = options
        self.keepsTableKeys = keepsTableKeys
    }

    /// Decodes a value of the given type from a TOML value.
    ///
    /// Like `JSONDecoder`, this doesn't apply the key decoding strategy
    /// to the keys of a dictionary with `String` keys,
    /// but it applies the strategy to the tables inside the dictionary.
    static func decode<T: Decodable>(
        _ type: T.Type,
        from value: TOMLValue,
        codingPath: [any CodingKey],
        userInfo: [CodingUserInfoKey: Any],
        options: DecodingOptions
    ) throws -> T {
        let decoder = _TOMLDecoder(
            value: value,
            codingPath: codingPath,
            userInfo: userInfo,
            options: options,
            keepsTableKeys: type is any StringKeyedDictionary.Type
        )
        return try T(from: decoder)
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
            table: dict,
            codingPath: codingPath,
            userInfo: userInfo,
            options: options,
            convertsKeys: !keepsTableKeys
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

/// A dictionary with `String` keys,
/// whose keys the decoder keeps instead of applying the key decoding strategy.
private protocol StringKeyedDictionary {}

extension Dictionary: StringKeyedDictionary where Key == String {}

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

/// Creates a URL from a TOML string.
///
/// The containers call this only for string values.
/// Other values go to `URL(from:)`,
/// which reads the table that `URL`'s own `Encodable` conformance writes.
private func decodeURL(from string: String, codingPath: [any CodingKey]) throws -> URL {
    guard let url = URL(string: string) else {
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Invalid URL string: \"\(string)\""
            )
        )
    }
    return url
}

/// Decodes a `Date` from a TOML value with the given strategy.
///
/// Every strategy decodes TOML offset date-times, local date-times, and local dates.
/// The numeric strategies also decode integers and floats.
private func decodeDate(
    from value: TOMLValue,
    strategy: TOMLDecoder.DateDecodingStrategy,
    codingPath: [any CodingKey]
) throws -> Date {
    let typeMismatch = DecodingError.typeMismatch(
        Date.self,
        DecodingError.Context(
            codingPath: codingPath,
            debugDescription: "Expected \(Date.self), found \(valueTypeName(value))"
        )
    )

    let number: Double
    switch value {
    case .offsetDateTime(let date):
        return date
    case .localDateTime(let dt):
        let components = DateComponents(
            year: dt.year,
            month: dt.month,
            day: dt.day,
            hour: dt.hour,
            minute: dt.minute,
            second: dt.second,
            nanosecond: dt.nanosecond
        )
        return try localDate(from: components, codingPath: codingPath)
    case .localDate(let d):
        let components = DateComponents(year: d.year, month: d.month, day: d.day)
        return try localDate(from: components, codingPath: codingPath)
    case .integer(let i):
        number = Double(i)
    case .float(let f):
        number = f
    default:
        throw typeMismatch
    }

    switch strategy {
    case .secondsSince1970:
        return Date(timeIntervalSince1970: number)
    case .millisecondsSince1970:
        return Date(timeIntervalSince1970: number / 1000)
    case .iso8601:
        throw typeMismatch
    }
}

/// Creates a date from components in the current time zone.
private func localDate(from components: DateComponents, codingPath: [any CodingKey]) throws -> Date {
    guard let date = Calendar(identifier: .gregorian).date(from: components) else {
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Invalid date components"
            )
        )
    }
    return date
}

/// Converts a TOML integer to the requested integer type.
///
/// Like `JSONDecoder`, this throws instead of trapping
/// when the value doesn't fit in the type.
private func convertInteger<T: FixedWidthInteger>(
    _ value: Int64,
    to type: T.Type,
    codingPath: [any CodingKey]
) throws -> T {
    guard let result = T(exactly: value) else {
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Number \(value) is not representable as \(type)"
            )
        )
    }
    return result
}

// MARK: - Keyed Decoding Container

private struct TOMLKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    /// The table as it appears in the document.
    let table: [String: TOMLValue]

    /// The table with its keys converted by the key decoding strategy.
    let dict: [String: TOMLValue]

    var codingPath: [any CodingKey]
    let userInfo: [CodingUserInfoKey: Any]
    let options: DecodingOptions

    /// Creates a container for a table.
    ///
    /// Like `JSONDecoder`, the container converts the table's keys
    /// when it's created, and then looks up each coding key unchanged.
    /// If two keys convert to the same key,
    /// the container keeps the value of the key that is already in that form,
    /// or else the value of the key that sorts first.
    init(
        table: [String: TOMLValue],
        codingPath: [any CodingKey],
        userInfo: [CodingUserInfoKey: Any],
        options: DecodingOptions,
        convertsKeys: Bool = true
    ) {
        self.table = table
        self.codingPath = codingPath
        self.userInfo = userInfo
        self.options = options

        switch options.keyDecodingStrategy {
        case .convertFromSnakeCase where convertsKeys:
            var dict: [String: TOMLValue] = [:]
            dict.reserveCapacity(table.count)
            for key in table.keys.sorted() {
                let converted = key.convertFromSnakeCase()
                if dict[converted] == nil || converted == key {
                    dict[converted] = table[key]
                }
            }
            self.dict = dict
        default:
            self.dict = table
        }
    }

    var allKeys: [Key] {
        dict.keys.compactMap { Key(stringValue: $0) }
    }

    func contains(_ key: Key) -> Bool {
        dict[key.stringValue] != nil
    }

    private func getValue(forKey key: Key) throws -> TOMLValue {
        guard let value = dict[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Key '\(key.stringValue)' not found"
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
        try decodeInteger(type, forKey: key)
    }

    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
        try decodeInteger(type, forKey: key)
    }

    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
        try decodeInteger(type, forKey: key)
    }

    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
        try decodeInteger(type, forKey: key)
    }

    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
        let value = try getValue(forKey: key)
        guard case .integer(let i) = value else {
            throw typeMismatchError(type, value: value, key: key)
        }
        return i
    }

    private func decodeInteger<T: FixedWidthInteger>(_ type: T.Type, forKey key: Key) throws -> T {
        try convertInteger(decode(Int64.self, forKey: key), to: type, codingPath: codingPath + [key])
    }

    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
        try decodeInteger(type, forKey: key)
    }

    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
        try decodeInteger(type, forKey: key)
    }

    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
        try decodeInteger(type, forKey: key)
    }

    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
        try decodeInteger(type, forKey: key)
    }

    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
        try decodeInteger(type, forKey: key)
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        let value = try getValue(forKey: key)

        if type == Date.self {
            return try decodeDate(
                from: value,
                strategy: options.dateDecodingStrategy,
                codingPath: codingPath + [key]
            ) as! T
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
        if type == URL.self, case .string(let string) = value {
            return try decodeURL(from: string, codingPath: codingPath + [key]) as! T
        }

        return try _TOMLDecoder.decode(
            type,
            from: value,
            codingPath: codingPath + [key],
            userInfo: userInfo,
            options: options
        )
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
            table: dict,
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
            value: .table(table),
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
        try decodeInteger(type)
    }

    mutating func decode(_ type: Int8.Type) throws -> Int8 {
        try decodeInteger(type)
    }

    mutating func decode(_ type: Int16.Type) throws -> Int16 {
        try decodeInteger(type)
    }

    mutating func decode(_ type: Int32.Type) throws -> Int32 {
        try decodeInteger(type)
    }

    mutating func decode(_ type: Int64.Type) throws -> Int64 {
        let value = try nextValue()
        guard case .integer(let i) = value else {
            throw typeMismatchError(type, value: value)
        }
        return i
    }

    private mutating func decodeInteger<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        let value = try decode(Int64.self)
        return try convertInteger(value, to: type, codingPath: codingPath + [TOMLCodingKey(index: currentIndex - 1)])
    }

    mutating func decode(_ type: UInt.Type) throws -> UInt {
        try decodeInteger(type)
    }

    mutating func decode(_ type: UInt8.Type) throws -> UInt8 {
        try decodeInteger(type)
    }

    mutating func decode(_ type: UInt16.Type) throws -> UInt16 {
        try decodeInteger(type)
    }

    mutating func decode(_ type: UInt32.Type) throws -> UInt32 {
        try decodeInteger(type)
    }

    mutating func decode(_ type: UInt64.Type) throws -> UInt64 {
        try decodeInteger(type)
    }

    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let value = try nextValue()

        if type == Date.self {
            return try decodeDate(
                from: value,
                strategy: options.dateDecodingStrategy,
                codingPath: codingPath + [TOMLCodingKey(index: currentIndex - 1)]
            ) as! T
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
        if type == URL.self, case .string(let string) = value {
            return try decodeURL(
                from: string,
                codingPath: codingPath + [TOMLCodingKey(index: currentIndex - 1)]
            ) as! T
        }

        return try _TOMLDecoder.decode(
            type,
            from: value,
            codingPath: codingPath + [TOMLCodingKey(index: currentIndex - 1)],
            userInfo: userInfo,
            options: options
        )
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type
    ) throws -> KeyedDecodingContainer<NestedKey> {
        let value = try nextValue()
        guard case .table(let dict) = value else {
            throw typeMismatchError([String: Any].self, value: value)
        }

        let container = TOMLKeyedDecodingContainer<NestedKey>(
            table: dict,
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
                codingPath: codingPath + [TOMLCodingKey(index: currentIndex - 1)],
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
        try decodeInteger(type)
    }

    func decode(_ type: Int8.Type) throws -> Int8 {
        try decodeInteger(type)
    }

    func decode(_ type: Int16.Type) throws -> Int16 {
        try decodeInteger(type)
    }

    func decode(_ type: Int32.Type) throws -> Int32 {
        try decodeInteger(type)
    }

    func decode(_ type: Int64.Type) throws -> Int64 {
        guard case .integer(let i) = value else {
            throw typeMismatchError(type)
        }
        return i
    }

    private func decodeInteger<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        try convertInteger(decode(Int64.self), to: type, codingPath: codingPath)
    }

    func decode(_ type: UInt.Type) throws -> UInt {
        try decodeInteger(type)
    }

    func decode(_ type: UInt8.Type) throws -> UInt8 {
        try decodeInteger(type)
    }

    func decode(_ type: UInt16.Type) throws -> UInt16 {
        try decodeInteger(type)
    }

    func decode(_ type: UInt32.Type) throws -> UInt32 {
        try decodeInteger(type)
    }

    func decode(_ type: UInt64.Type) throws -> UInt64 {
        try decodeInteger(type)
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        if type == Date.self {
            return try decodeDate(from: value, strategy: options.dateDecodingStrategy, codingPath: codingPath) as! T
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
        if type == URL.self, case .string(let string) = value {
            return try decodeURL(from: string, codingPath: codingPath) as! T
        }

        return try _TOMLDecoder.decode(
            type,
            from: value,
            codingPath: codingPath,
            userInfo: userInfo,
            options: options
        )
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
    /// Converts a snake_case key to camelCase, as `JSONDecoder` does.
    ///
    /// The conversion lowercases the first word, capitalizes the other words,
    /// and removes the underscores between them.
    /// It keeps leading and trailing underscores,
    /// and leaves a key without an underscore between words unchanged.
    /// For example, `first_name` becomes `firstName`,
    /// `_first_name_` becomes `_firstName_`, and `MY_VAR` becomes `myVar`.
    func convertFromSnakeCase() -> String {
        guard let first = firstIndex(where: { $0 != "_" }) else {
            return self
        }
        var last = index(before: endIndex)
        while last > first && self[last] == "_" {
            formIndex(before: &last)
        }

        let words = self[first ... last].split(separator: "_")
        guard words.count > 1 else {
            return self
        }
        let camelCase = ([words[0].lowercased()] + words.dropFirst().map(\.capitalized)).joined()
        return String(self[..<first]) + camelCase + String(self[index(after: last)...])
    }
}
