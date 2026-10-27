import Foundation

/// An encoder that converts Swift values into TOML format.
///
/// This encoder produces output conforming to the
/// [TOML v1.0.0 specification](https://toml.io/en/v1.0.0).
/// It supports all TOML data types including strings, integers, floats, booleans,
/// dates and times, arrays, and tables.
///
/// ## Usage
///
/// ```swift
/// struct Config: Encodable {
///     var title: String
///     var port: Int
/// }
///
/// let config = Config(title: "My App", port: 8080)
/// let encoder = TOMLEncoder()
/// let data = try encoder.encode(config)
/// ```
///
/// ## Date Encoding
///
/// The encoder supports multiple date formats through ``DateEncodingStrategy``:
///
/// ```swift
/// let encoder = TOMLEncoder()
/// encoder.dateEncodingStrategy = .localDateTime
/// ```
///
/// ## Key Encoding
///
/// Use ``KeyEncodingStrategy`` to automatically convert between naming conventions:
///
/// ```swift
/// let encoder = TOMLEncoder()
/// encoder.keyEncodingStrategy = .convertToSnakeCase
/// ```
///
/// ## URL Encoding
///
/// Use ``URLEncodingStrategy`` to encode `URL` values as strings:
///
/// ```swift
/// let encoder = TOMLEncoder()
/// encoder.urlEncodingStrategy = .absoluteString
/// ```
///
/// ## Output Formatting
///
/// Control the output format with ``OutputFormatting``:
///
/// ```swift
/// let encoder = TOMLEncoder()
/// encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
/// ```
public final class TOMLEncoder {

    // MARK: - Date Encoding Strategy

    /// The strategy used when encoding `Date` values.
    ///
    /// TOML supports several date-time formats, and this strategy controls
    /// which format is used when encoding Swift `Date` values.
    public enum DateEncodingStrategy: Sendable {
        /// Encode dates as ISO 8601 formatted offset date-times (RFC 3339).
        ///
        /// Example: `2024-01-15T09:30:00.000Z`
        case iso8601

        /// Encode dates as local date-times without timezone information.
        ///
        /// Example: `2024-01-15T09:30:00`
        case localDateTime

        /// Encode dates as local dates without time components.
        ///
        /// Example: `2024-01-15`
        case localDate

        /// Encode dates as local times without date components.
        ///
        /// Example: `09:30:00`
        case localTime

        /// Encode dates as floating-point seconds since January 1, 1970.
        case secondsSince1970

        /// Encode dates as floating-point milliseconds since January 1, 1970.
        case millisecondsSince1970
    }

    // MARK: - Key Encoding Strategy

    /// The strategy used when encoding keys to TOML.
    ///
    /// Use this to automatically convert between different naming conventions
    /// in your Swift types and TOML output.
    public enum KeyEncodingStrategy: Sendable {
        /// Use the keys specified by the Swift type without modification.
        case useDefaultKeys

        /// Convert keys from camelCase to snake_case.
        ///
        /// For example, `userName` in Swift becomes `user_name` in TOML.
        case convertToSnakeCase
    }

    // MARK: - URL Encoding Strategy

    /// The strategy used when encoding `URL` values.
    ///
    /// ``TOMLDecoder`` reads URLs written with either strategy.
    public enum URLEncodingStrategy: Sendable {
        /// Encode URLs with their own `Encodable` implementation.
        ///
        /// Foundation writes a table with a `relative` string
        /// and, for a URL that has one, a `base` URL.
        /// This is the default strategy.
        case deferredToURL

        /// Encode URLs as strings, using their absolute string.
        ///
        /// A relative URL is resolved against its base URL,
        /// so decoding the string produces an absolute URL
        /// that has no base URL.
        ///
        /// Example: `url = "https://example.com/"`
        case absoluteString
    }

    // MARK: - Output Formatting

    /// Options for formatting the encoded TOML output.
    public struct OutputFormatting: OptionSet, Sendable {
        public let rawValue: UInt

        /// Creates an output formatting option with the given raw value.
        public init(rawValue: UInt) {
            self.rawValue = rawValue
        }

        /// Sort keys alphabetically in tables.
        ///
        /// This produces deterministic output that's easier to diff
        /// and useful for version control.
        public static let sortedKeys = OutputFormatting(rawValue: 1 << 0)

        /// Format the output with additional whitespace for readability.
        public static let prettyPrinted = OutputFormatting(rawValue: 1 << 1)
    }

    // MARK: - Properties

    /// The strategy used when encoding `Date` values.
    public var dateEncodingStrategy: DateEncodingStrategy = .iso8601

    /// The strategy used when encoding keys.
    public var keyEncodingStrategy: KeyEncodingStrategy = .useDefaultKeys

    /// The strategy used when encoding `URL` values.
    public var urlEncodingStrategy: URLEncodingStrategy = .deferredToURL

    /// The output formatting options.
    public var outputFormatting: OutputFormatting = []

    /// A dictionary of contextual information to pass to the encoder.
    public var userInfo: [CodingUserInfoKey: any Sendable] = [:]

    // MARK: - Initialization

    /// Creates a new TOML encoder.
    public init() {}

    // MARK: - Encoding

    /// Encodes the given value as TOML data.
    ///
    /// - Parameter value: An `Encodable` value to convert to TOML format.
    /// - Returns: UTF-8 encoded data containing the TOML representation.
    /// - Throws: ``TOMLEncodingError`` if encoding fails.
    public func encode<T: Encodable>(_ value: T) throws -> Data {
        let string = try encodeToString(value)
        guard let data = string.data(using: .utf8) else {
            throw TOMLEncodingError.invalidValue("Unable to convert to UTF-8 data", codingPath: [])
        }
        return data
    }

    /// Encodes the given value as a TOML string.
    ///
    /// - Parameter value: An `Encodable` value to convert to TOML format.
    /// - Returns: A string containing the TOML representation.
    /// - Throws: ``TOMLEncodingError`` if encoding fails.
    public func encodeToString<T: Encodable>(_ value: T) throws -> String {
        let encoder = _TOMLEncoder(
            codingPath: [],
            userInfo: userInfo.reduce(into: [:]) { $0[$1.key] = $1.value },
            options: EncodingOptions(
                dateEncodingStrategy: dateEncodingStrategy,
                keyEncodingStrategy: keyEncodingStrategy,
                urlEncodingStrategy: urlEncodingStrategy,
                outputFormatting: outputFormatting
            )
        )

        try value.encode(to: encoder)

        guard let value = encoder.value else {
            throw TOMLEncodingError.invalidValue("No value encoded", codingPath: [])
        }

        return serialize(value, sortKeys: outputFormatting.contains(.sortedKeys))
    }

    // MARK: - Private Serialization

    private func serialize(_ value: TOMLValue, sortKeys: Bool) -> String {
        var result = ""
        serializeTable(value, to: &result, path: [], sortKeys: sortKeys)
        return result
    }

    private func serializeTable(_ value: TOMLValue, to output: inout String, path: [String], sortKeys: Bool) {
        guard case .table(let dict) = value else { return }

        let keys = sortKeys ? dict.keys.sorted() : Array(dict.keys)

        var simpleKeys: [String] = []
        var tableKeys: [String] = []
        var arrayOfTablesKeys: [String] = []

        for key in keys {
            guard let val = dict[key] else { continue }
            switch val {
            case .table:
                tableKeys.append(key)
            case .array(let arr) where !arr.isEmpty && arr.allSatisfy({ $0.isTable }):
                arrayOfTablesKeys.append(key)
            default:
                simpleKeys.append(key)
            }
        }

        for key in simpleKeys {
            guard let val = dict[key] else { continue }
            output += "\(escapeKey(key)) = \(serializeValue(val, sortKeys: sortKeys))\n"
        }

        for key in tableKeys {
            guard let val = dict[key] else { continue }
            let newPath = path + [key]
            output += "\n[\(newPath.map(escapeKey).joined(separator: "."))]\n"
            serializeTable(val, to: &output, path: newPath, sortKeys: sortKeys)
        }

        for key in arrayOfTablesKeys {
            guard case .array(let arr) = dict[key] else { continue }
            let newPath = path + [key]
            for item in arr {
                output += "\n[[\(newPath.map(escapeKey).joined(separator: "."))]]"
                output += "\n"
                serializeTable(item, to: &output, path: newPath, sortKeys: sortKeys)
            }
        }
    }

    private func serializeValue(_ value: TOMLValue, sortKeys: Bool) -> String {
        switch value {
        case .string(let s):
            return "\"\(escapeString(s))\""
        case .integer(let i):
            return String(i)
        case .float(let f):
            if f.isNaN {
                return "nan"
            } else if f.isInfinite {
                return f > 0 ? "inf" : "-inf"
            }
            return String(f)
        case .boolean(let b):
            return b ? "true" : "false"
        case .offsetDateTime(let date):
            return formatOffsetDateTime(date)
        case .localDateTime(let dt):
            return formatLocalDateTime(dt)
        case .localDate(let d):
            return formatLocalDate(d)
        case .localTime(let t):
            return formatLocalTime(t)
        case .array(let arr):
            let items = arr.map { serializeValue($0, sortKeys: sortKeys) }
            return "[\(items.joined(separator: ", "))]"
        case .table(let dict):
            let keys = sortKeys ? dict.keys.sorted() : Array(dict.keys)
            let items = keys.compactMap { key -> String? in
                guard let val = dict[key] else { return nil }
                return "\(escapeKey(key)) = \(serializeValue(val, sortKeys: sortKeys))"
            }
            return "{ \(items.joined(separator: ", ")) }"
        }
    }

    private func escapeKey(_ key: String) -> String {
        let bareKeyPattern = #"^[A-Za-z0-9_-]+$"#
        if key.range(of: bareKeyPattern, options: .regularExpression) != nil {
            return key
        }
        return "\"\(escapeString(key))\""
    }

    private func escapeString(_ s: String) -> String {
        var result = ""
        // Iterate over Unicode scalars to preserve individual CR and LF characters
        // (Swift treats CR+LF as a single Character grapheme cluster)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "\u{08}": result += "\\b"  // backspace
            case "\u{0C}": result += "\\f"  // formfeed
            case "\u{7F}": result += "\\u007F"  // DEL
            default:
                if scalar.isASCII && scalar.value < 32 {
                    result += String(format: "\\u%04X", scalar.value)
                } else {
                    result.append(Character(scalar))
                }
            }
        }
        return result
    }

    private func formatOffsetDateTime(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func formatLocalDateTime(_ dt: LocalDateTime) -> String {
        var result = String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d",
            dt.year,
            dt.month,
            dt.day,
            dt.hour,
            dt.minute,
            dt.second
        )
        if dt.nanosecond > 0 {
            result += formatFractionalSeconds(dt.nanosecond)
        }
        return result
    }

    private func formatLocalDate(_ d: LocalDate) -> String {
        String(format: "%04d-%02d-%02d", d.year, d.month, d.day)
    }

    private func formatLocalTime(_ t: LocalTime) -> String {
        var result = String(format: "%02d:%02d:%02d", t.hour, t.minute, t.second)
        if t.nanosecond > 0 {
            result += formatFractionalSeconds(t.nanosecond)
        }
        return result
    }

    private func formatFractionalSeconds(_ nanosecond: Int) -> String {
        // Convert nanoseconds to fractional string, trimming trailing zeros
        let fractional = String(format: "%09d", nanosecond)
        let trimmed = fractional.replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
        return ".\(trimmed)"
    }
}

// MARK: - Encoding Errors

/// Errors that can occur during TOML encoding.
public enum TOMLEncodingError: Error, CustomStringConvertible, Sendable {
    /// The value could not be encoded.
    case invalidValue(String, codingPath: [any CodingKey])

    /// The type is not supported for TOML encoding.
    case unsupportedType(String, codingPath: [any CodingKey])

    /// The key is not valid for TOML.
    case invalidKey(String)

    public var description: String {
        switch self {
        case .invalidValue(let message, let codingPath):
            let path = codingPath.map(\.stringValue).joined(separator: ".")
            return "Invalid value at '\(path)': \(message)"
        case .unsupportedType(let type, let codingPath):
            let path = codingPath.map(\.stringValue).joined(separator: ".")
            return "Unsupported type '\(type)' at '\(path)'"
        case .invalidKey(let key):
            return "Invalid TOML key: '\(key)'"
        }
    }
}

// MARK: - Internal Types

struct EncodingOptions {
    let dateEncodingStrategy: TOMLEncoder.DateEncodingStrategy
    let keyEncodingStrategy: TOMLEncoder.KeyEncodingStrategy
    let urlEncodingStrategy: TOMLEncoder.URLEncodingStrategy
    let outputFormatting: TOMLEncoder.OutputFormatting
}

// MARK: - Internal Encoder

final class _TOMLEncoder: Encoder {
    var codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any]
    let options: EncodingOptions

    var value: TOMLValue?
    private var storage: TOMLEncodingStorage

    init(codingPath: [any CodingKey], userInfo: [CodingUserInfoKey: Any], options: EncodingOptions) {
        self.codingPath = codingPath
        self.userInfo = userInfo
        self.options = options
        self.storage = TOMLEncodingStorage()
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        let container = TOMLKeyedEncodingContainer<Key>(
            encoder: self,
            codingPath: codingPath
        )
        return KeyedEncodingContainer(container)
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        TOMLUnkeyedEncodingContainer(
            encoder: self,
            codingPath: codingPath
        )
    }

    func singleValueContainer() -> any SingleValueEncodingContainer {
        TOMLSingleValueEncodingContainer(
            encoder: self,
            codingPath: codingPath
        )
    }

    func setValue(_ value: TOMLValue) {
        self.value = value
    }
}

// MARK: - Boxing Helpers

private extension _TOMLEncoder {
    func box(_ value: Bool) -> TOMLValue { .boolean(value) }
    func box(_ value: Int) -> TOMLValue { .integer(Int64(value)) }
    func box(_ value: Int8) -> TOMLValue { .integer(Int64(value)) }
    func box(_ value: Int16) -> TOMLValue { .integer(Int64(value)) }
    func box(_ value: Int32) -> TOMLValue { .integer(Int64(value)) }
    func box(_ value: Int64) -> TOMLValue { .integer(value) }
    func box(_ value: UInt) -> TOMLValue { .integer(Int64(value)) }
    func box(_ value: UInt8) -> TOMLValue { .integer(Int64(value)) }
    func box(_ value: UInt16) -> TOMLValue { .integer(Int64(value)) }
    func box(_ value: UInt32) -> TOMLValue { .integer(Int64(value)) }
    func box(_ value: UInt64) -> TOMLValue { .integer(Int64(value)) }
    func box(_ value: Float) -> TOMLValue { .float(Double(value)) }
    func box(_ value: Double) -> TOMLValue { .float(value) }
    func box(_ value: String) -> TOMLValue { .string(value) }

    func box(_ date: Date) -> TOMLValue {
        switch options.dateEncodingStrategy {
        case .iso8601:
            return .offsetDateTime(date)
        case .localDateTime:
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second, .nanosecond],
                from: date
            )
            return .localDateTime(
                LocalDateTime(
                    year: components.year ?? 0,
                    month: components.month ?? 0,
                    day: components.day ?? 0,
                    hour: components.hour ?? 0,
                    minute: components.minute ?? 0,
                    second: components.second ?? 0,
                    nanosecond: components.nanosecond ?? 0
                )
            )
        case .localDate:
            let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
            return .localDate(
                LocalDate(
                    year: components.year ?? 0,
                    month: components.month ?? 0,
                    day: components.day ?? 0
                )
            )
        case .localTime:
            let components = Calendar.current.dateComponents(
                [.hour, .minute, .second, .nanosecond],
                from: date
            )
            return .localTime(
                LocalTime(
                    hour: components.hour ?? 0,
                    minute: components.minute ?? 0,
                    second: components.second ?? 0,
                    nanosecond: components.nanosecond ?? 0
                )
            )
        case .secondsSince1970:
            return .float(date.timeIntervalSince1970)
        case .millisecondsSince1970:
            return .float(date.timeIntervalSince1970 * 1000)
        }
    }

    func box<T: Encodable>(_ value: T) throws -> TOMLValue {
        if let date = value as? Date {
            return box(date)
        }
        if let localDateTime = value as? LocalDateTime {
            return .localDateTime(localDateTime)
        }
        if let localDate = value as? LocalDate {
            return .localDate(localDate)
        }
        if let localTime = value as? LocalTime {
            return .localTime(localTime)
        }
        if let url = value as? URL, options.urlEncodingStrategy == .absoluteString {
            return .string(url.absoluteString)
        }

        let encoder = _TOMLEncoder(codingPath: codingPath, userInfo: userInfo, options: options)
        try value.encode(to: encoder)

        if let v = encoder.value {
            return v
        }

        throw TOMLEncodingError.invalidValue("Unable to encode \(type(of: value))", codingPath: codingPath)
    }

    func convertKey(_ key: any CodingKey) -> String {
        switch options.keyEncodingStrategy {
        case .useDefaultKeys:
            return key.stringValue
        case .convertToSnakeCase:
            return key.stringValue.convertToSnakeCase()
        }
    }
}

// MARK: - Encoding Storage

private final class TOMLEncodingStorage {
    var containers: [Any] = []
}

// MARK: - Keyed Encoding Container

private struct TOMLKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    var codingPath: [any CodingKey]
    let encoder: _TOMLEncoder

    private var storage: [String: TOMLValue] = [:]

    init(encoder: _TOMLEncoder, codingPath: [any CodingKey]) {
        self.encoder = encoder
        self.codingPath = codingPath
        // Initialize with empty table so empty containers are valid
        encoder.setValue(.table([:]))
    }

    private mutating func set(_ value: TOMLValue, forKey key: Key) {
        let keyString = encoder.convertKey(key)
        storage[keyString] = value
        encoder.setValue(.table(storage))
    }

    mutating func encodeNil(forKey key: Key) throws {
    }

    mutating func encode(_ value: Bool, forKey key: Key) throws {
        set(.boolean(value), forKey: key)
    }

    mutating func encode(_ value: String, forKey key: Key) throws {
        set(.string(value), forKey: key)
    }

    mutating func encode(_ value: Double, forKey key: Key) throws {
        set(.float(value), forKey: key)
    }

    mutating func encode(_ value: Float, forKey key: Key) throws {
        set(.float(Double(value)), forKey: key)
    }

    mutating func encode(_ value: Int, forKey key: Key) throws {
        set(.integer(Int64(value)), forKey: key)
    }

    mutating func encode(_ value: Int8, forKey key: Key) throws {
        set(.integer(Int64(value)), forKey: key)
    }

    mutating func encode(_ value: Int16, forKey key: Key) throws {
        set(.integer(Int64(value)), forKey: key)
    }

    mutating func encode(_ value: Int32, forKey key: Key) throws {
        set(.integer(Int64(value)), forKey: key)
    }

    mutating func encode(_ value: Int64, forKey key: Key) throws {
        set(.integer(value), forKey: key)
    }

    mutating func encode(_ value: UInt, forKey key: Key) throws {
        set(.integer(Int64(value)), forKey: key)
    }

    mutating func encode(_ value: UInt8, forKey key: Key) throws {
        set(.integer(Int64(value)), forKey: key)
    }

    mutating func encode(_ value: UInt16, forKey key: Key) throws {
        set(.integer(Int64(value)), forKey: key)
    }

    mutating func encode(_ value: UInt32, forKey key: Key) throws {
        set(.integer(Int64(value)), forKey: key)
    }

    mutating func encode(_ value: UInt64, forKey key: Key) throws {
        set(.integer(Int64(value)), forKey: key)
    }

    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        let boxed = try encoder.box(value)
        set(boxed, forKey: key)
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type,
        forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> {
        let nestedEncoder = _TOMLEncoder(
            codingPath: codingPath + [key],
            userInfo: encoder.userInfo,
            options: encoder.options
        )
        return nestedEncoder.container(keyedBy: keyType)
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
        let nestedEncoder = _TOMLEncoder(
            codingPath: codingPath + [key],
            userInfo: encoder.userInfo,
            options: encoder.options
        )
        return nestedEncoder.unkeyedContainer()
    }

    mutating func superEncoder() -> any Encoder {
        _TOMLEncoder(codingPath: codingPath, userInfo: encoder.userInfo, options: encoder.options)
    }

    mutating func superEncoder(forKey key: Key) -> any Encoder {
        _TOMLEncoder(codingPath: codingPath + [key], userInfo: encoder.userInfo, options: encoder.options)
    }
}

// MARK: - Unkeyed Encoding Container

private struct TOMLUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    var codingPath: [any CodingKey]
    let encoder: _TOMLEncoder

    private var storage: [TOMLValue] = []

    var count: Int { storage.count }

    init(encoder: _TOMLEncoder, codingPath: [any CodingKey]) {
        self.encoder = encoder
        self.codingPath = codingPath
        // Initialize with empty array so empty containers are valid
        encoder.setValue(.array([]))
    }

    private mutating func append(_ value: TOMLValue) {
        storage.append(value)
        encoder.setValue(.array(storage))
    }

    mutating func encodeNil() throws {
    }

    mutating func encode(_ value: Bool) throws {
        append(.boolean(value))
    }

    mutating func encode(_ value: String) throws {
        append(.string(value))
    }

    mutating func encode(_ value: Double) throws {
        append(.float(value))
    }

    mutating func encode(_ value: Float) throws {
        append(.float(Double(value)))
    }

    mutating func encode(_ value: Int) throws {
        append(.integer(Int64(value)))
    }

    mutating func encode(_ value: Int8) throws {
        append(.integer(Int64(value)))
    }

    mutating func encode(_ value: Int16) throws {
        append(.integer(Int64(value)))
    }

    mutating func encode(_ value: Int32) throws {
        append(.integer(Int64(value)))
    }

    mutating func encode(_ value: Int64) throws {
        append(.integer(value))
    }

    mutating func encode(_ value: UInt) throws {
        append(.integer(Int64(value)))
    }

    mutating func encode(_ value: UInt8) throws {
        append(.integer(Int64(value)))
    }

    mutating func encode(_ value: UInt16) throws {
        append(.integer(Int64(value)))
    }

    mutating func encode(_ value: UInt32) throws {
        append(.integer(Int64(value)))
    }

    mutating func encode(_ value: UInt64) throws {
        append(.integer(Int64(value)))
    }

    mutating func encode<T: Encodable>(_ value: T) throws {
        let boxed = try encoder.box(value)
        append(boxed)
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type
    ) -> KeyedEncodingContainer<NestedKey> {
        let nestedEncoder = _TOMLEncoder(
            codingPath: codingPath + [TOMLCodingKey(index: count)],
            userInfo: encoder.userInfo,
            options: encoder.options
        )
        return nestedEncoder.container(keyedBy: keyType)
    }

    mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
        let nestedEncoder = _TOMLEncoder(
            codingPath: codingPath + [TOMLCodingKey(index: count)],
            userInfo: encoder.userInfo,
            options: encoder.options
        )
        return nestedEncoder.unkeyedContainer()
    }

    mutating func superEncoder() -> any Encoder {
        _TOMLEncoder(
            codingPath: codingPath + [TOMLCodingKey(index: count)],
            userInfo: encoder.userInfo,
            options: encoder.options
        )
    }
}

// MARK: - Single Value Encoding Container

private struct TOMLSingleValueEncodingContainer: SingleValueEncodingContainer {
    var codingPath: [any CodingKey]
    let encoder: _TOMLEncoder

    init(encoder: _TOMLEncoder, codingPath: [any CodingKey]) {
        self.encoder = encoder
        self.codingPath = codingPath
    }

    mutating func encodeNil() throws {
    }

    mutating func encode(_ value: Bool) throws {
        encoder.setValue(.boolean(value))
    }

    mutating func encode(_ value: String) throws {
        encoder.setValue(.string(value))
    }

    mutating func encode(_ value: Double) throws {
        encoder.setValue(.float(value))
    }

    mutating func encode(_ value: Float) throws {
        encoder.setValue(.float(Double(value)))
    }

    mutating func encode(_ value: Int) throws {
        encoder.setValue(.integer(Int64(value)))
    }

    mutating func encode(_ value: Int8) throws {
        encoder.setValue(.integer(Int64(value)))
    }

    mutating func encode(_ value: Int16) throws {
        encoder.setValue(.integer(Int64(value)))
    }

    mutating func encode(_ value: Int32) throws {
        encoder.setValue(.integer(Int64(value)))
    }

    mutating func encode(_ value: Int64) throws {
        encoder.setValue(.integer(value))
    }

    mutating func encode(_ value: UInt) throws {
        encoder.setValue(.integer(Int64(value)))
    }

    mutating func encode(_ value: UInt8) throws {
        encoder.setValue(.integer(Int64(value)))
    }

    mutating func encode(_ value: UInt16) throws {
        encoder.setValue(.integer(Int64(value)))
    }

    mutating func encode(_ value: UInt32) throws {
        encoder.setValue(.integer(Int64(value)))
    }

    mutating func encode(_ value: UInt64) throws {
        encoder.setValue(.integer(Int64(value)))
    }

    mutating func encode<T: Encodable>(_ value: T) throws {
        let boxed = try encoder.box(value)
        encoder.setValue(boxed)
    }
}

// MARK: - Private Extensions

private extension String {
    func convertToSnakeCase() -> String {
        var result = ""
        for (index, char) in self.enumerated() {
            if char.isUppercase {
                if index > 0 {
                    result += "_"
                }
                result += char.lowercased()
            } else {
                result.append(char)
            }
        }
        return result
    }
}

private extension TOMLValue {
    var isTable: Bool {
        if case .table = self { return true }
        return false
    }
}
