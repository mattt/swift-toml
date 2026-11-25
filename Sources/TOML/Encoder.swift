import Foundation

/// An encoder that converts Swift values into TOML format.
///
/// This encoder produces output that conforms to both the
/// [TOML v1.0.0](https://toml.io/en/v1.0.0)
/// and [TOML v1.1.0](https://toml.io/en/v1.1.0) specifications.
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
        ///
        /// This strategy writes the same keys as `JSONEncoder`'s strategy of the same name.
        /// A run of uppercase letters is one word,
        /// so `myURLValue` becomes `my_url_value` and `userID` becomes `user_id`.
        /// The first character never starts a new word,
        /// so a key that starts with an acronym splits after the acronym's first letter:
        /// `URLSession` becomes `u_rl_session`, and `PATH` becomes `p_ath`.
        /// `JSONEncoder` writes the same keys.
        /// To write such a property with another key,
        /// give it an explicit `CodingKeys` raw value,
        /// such as `case URLSession = "urlSession"`, which this strategy writes as `url_session`.
        /// Leading and trailing underscores stay.
        ///
        /// As with `JSONEncoder` and `JSONDecoder`,
        /// a property such as `userID` doesn't round-trip
        /// with ``TOMLDecoder/KeyDecodingStrategy/convertFromSnakeCase``,
        /// because `user_id` decodes as `userId`.
        /// To round-trip such a property under both strategies,
        /// give it an explicit `CodingKeys` raw value that each strategy converts to the other,
        /// such as `case userID = "userId"`.
        ///
        /// As with `JSONEncoder`, this strategy doesn't change the keys
        /// of a dictionary with `String` keys, such as `[String: Int]`,
        /// that you pass to a container's `encode` method
        /// or encode as the top-level value.
        /// It still converts the coding keys of the values in the dictionary,
        /// such as the properties of a structure.
        /// ``TOMLDecoder`` keeps those dictionary keys too,
        /// so they round-trip with
        /// ``TOMLDecoder/KeyDecodingStrategy/convertFromSnakeCase``.
        /// If a custom `encode(to:)` method calls the dictionary's own `encode(to:)` method,
        /// including with a super encoder,
        /// this strategy converts the dictionary's keys, as `JSONEncoder` does.
        /// Version 2.2.2 and earlier converted the keys of a dictionary in every case.
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

        /// Write each array of more than one element on several lines.
        ///
        /// Each element is on its own line, indented four spaces,
        /// and followed by a comma:
        ///
        /// ```toml
        /// ports = [
        ///     8080,
        ///     8081,
        /// ]
        /// ```
        ///
        /// A nested array of more than one element is indented
        /// one more level for each level of nesting,
        /// including an array in a one-element array or in an inline table:
        ///
        /// ```toml
        /// single = [[
        ///     1,
        ///     2,
        /// ]]
        /// ```
        ///
        /// An empty array and the brackets of a one-element array stay on one line,
        /// and so do an inline table's braces and the start of each of its entries.
        /// This option doesn't change the form of an array of tables
        /// that the encoder writes as `[[name]]` sections,
        /// but it applies to the arrays in those tables.
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
    /// - Throws: ``TOMLEncodingError/invalidValue(_:codingPath:)``
    ///   for a value that TOML can't represent,
    ///   such as an integer greater than `Int64.max`
    ///   or a top-level value that isn't a table,
    ///   and any error that a value's `encode(to:)` method throws.
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
    /// - Throws: ``TOMLEncodingError/invalidValue(_:codingPath:)``
    ///   for a value that TOML can't represent,
    ///   such as an integer greater than `Int64.max`
    ///   or a top-level value that isn't a table,
    ///   and any error that a value's `encode(to:)` method throws.
    public func encodeToString<T: Encodable>(_ value: T) throws -> String {
        let encoder = _TOMLEncoder(
            codingPath: [],
            userInfo: userInfo.reduce(into: [:]) { $0[$1.key] = $1.value },
            options: EncodingOptions(
                dateEncodingStrategy: dateEncodingStrategy,
                keyEncodingStrategy: keyEncodingStrategy,
                urlEncodingStrategy: urlEncodingStrategy,
                outputFormatting: outputFormatting
            ),
            keepsTableKeys: value is any StringKeyedDictionary
        )

        try value.encode(to: encoder)

        guard let value = try encoder.encodedValue() else {
            throw TOMLEncodingError.invalidValue("No value encoded", codingPath: [])
        }

        return try serialize(value)
    }

    // MARK: - Private Serialization

    private func serialize(_ value: TOMLValue) throws -> String {
        // A TOML document is a table, so it can't hold another value at the top level.
        guard value.isTable else {
            throw TOMLEncodingError.invalidValue(
                "Top-level value must encode as a table, not \(value.typeName)",
                codingPath: []
            )
        }

        var result = ""
        let serializer = Serializer(
            sortKeys: outputFormatting.contains(.sortedKeys),
            prettyPrinted: outputFormatting.contains(.prettyPrinted)
        )
        serializer.serializeTable(value, to: &result, path: [])
        return result
    }
}

// MARK: - Serialization

/// Writes a TOML document for a table, with the encoder's output formatting.
private struct Serializer {
    /// The indentation for each level of a multi-line array.
    static let indentation = "    "

    let sortKeys: Bool
    let prettyPrinted: Bool

    func serializeTable(_ value: TOMLValue, to output: inout String, path: [String]) {
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
            output += "\(escapeKey(key)) = \(serializeValue(val, indentLevel: prettyPrinted ? 0 : nil))\n"
        }

        for key in tableKeys {
            guard let val = dict[key] else { continue }
            let newPath = path + [key]
            output += "\n[\(newPath.map(escapeKey).joined(separator: "."))]\n"
            serializeTable(val, to: &output, path: newPath)
        }

        for key in arrayOfTablesKeys {
            guard case .array(let arr) = dict[key] else { continue }
            let newPath = path + [key]
            for item in arr {
                output += "\n[[\(newPath.map(escapeKey).joined(separator: "."))]]"
                output += "\n"
                serializeTable(item, to: &output, path: newPath)
            }
        }
    }

    /// Returns the TOML text for a value.
    ///
    /// - Parameter indentLevel: The indentation level of the line where the value starts,
    ///   if each array of more than one element in the value spans several lines,
    ///   or `nil` if the value is on one line.
    private func serializeValue(_ value: TOMLValue, indentLevel: Int?) -> String {
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
            if let indentLevel, arr.count > 1 {
                // Write one element on each line, indented one level more than the array.
                let elementIndentation = String(repeating: Self.indentation, count: indentLevel + 1)
                let items = arr.map {
                    "\(elementIndentation)\(serializeValue($0, indentLevel: indentLevel + 1)),\n"
                }
                return "[\n\(items.joined())\(String(repeating: Self.indentation, count: indentLevel))]"
            }
            // An empty or one-element array is on one line,
            // but the element starts on that line and can span several lines.
            let items = arr.map { serializeValue($0, indentLevel: indentLevel) }
            return "[\(items.joined(separator: ", "))]"
        case .table(let dict):
            // TOML 1.0 doesn't allow newlines between an inline table's entries,
            // but it allows them inside an array value,
            // so each value starts on the table's line and can span several lines.
            let keys = sortKeys ? dict.keys.sorted() : Array(dict.keys)
            let items = keys.compactMap { key -> String? in
                guard let val = dict[key] else { return nil }
                return "\(escapeKey(key)) = \(serializeValue(val, indentLevel: indentLevel))"
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
        // The formatter rounds fractions, but TOML requires truncation.
        // Compare in seconds so an exact millisecond survives floating-point conversion.
        let seconds = date.timeIntervalSinceReferenceDate
        let nearest = (seconds * 1000).rounded()
        let milliseconds = nearest / 1000 > seconds ? nearest - 1 : nearest
        let truncated = Date(timeIntervalSinceReferenceDate: milliseconds / 1000)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: truncated)
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
    @available(
        *,
        deprecated,
        message: "TOMLEncoder never throws this error; it throws invalidValue for a value that TOML can't represent"
    )
    case unsupportedType(String, codingPath: [any CodingKey])

    /// The key is not valid for TOML.
    @available(
        *,
        deprecated,
        message: "TOMLEncoder never throws this error; it quotes keys as needed and throws only invalidValue"
    )
    case invalidKey(String)

    public var description: String {
        switch self {
        case .invalidValue(let message, let codingPath):
            let path = codingPath.map(\.stringValue).joined(separator: ".")
            return "Invalid value at '\(path)': \(message)"
        default:
            // Read the deprecated cases' descriptions through a protocol,
            // so that this switch doesn't use them and cause deprecation warnings.
            return (self as any DeprecatedCaseDescribing).deprecatedCaseDescription
        }
    }
}

extension TOMLEncodingError: DeprecatedCaseDescribing {
    @available(*, deprecated)
    var deprecatedCaseDescription: String {
        switch self {
        case .unsupportedType(let type, let codingPath):
            let path = codingPath.map(\.stringValue).joined(separator: ".")
            return "Unsupported type '\(type)' at '\(path)'"
        case .invalidKey(let key):
            return "Invalid TOML key: '\(key)'"
        case .invalidValue:
            return description
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

    /// The place that holds the value this encoder's containers write to.
    ///
    /// A super encoder's parent container holds the same slot,
    /// so the parent sees the value without keeping the super encoder alive.
    fileprivate let slot = EncodedSlot()

    /// The value that this encoder's containers write to,
    /// or `nil` if nothing is encoded yet.
    fileprivate var storage: EncodedValue? {
        get { slot.value }
        set { slot.value = newValue }
    }

    /// The errors that this encoder, its containers, and its super encoders record.
    private let context: EncodingContext

    /// The table and key where a keyed super encoder writes its value
    /// when it's released.
    private let superEncoderTarget: (table: EncodedTable, key: String)?

    /// Whether a keyed container for this encoder writes its keys
    /// without applying the key encoding strategy.
    ///
    /// Like `JSONEncoder`, the encoder keeps the keys of a dictionary with `String` keys,
    /// but it applies the strategy to the tables inside the dictionary.
    private let keepsTableKeys: Bool

    /// Creates an encoder with its own error context,
    /// for the top-level value or a value that a container boxes.
    convenience init(
        codingPath: [any CodingKey],
        userInfo: [CodingUserInfoKey: Any],
        options: EncodingOptions,
        keepsTableKeys: Bool = false
    ) {
        self.init(
            codingPath: codingPath,
            userInfo: userInfo,
            options: options,
            context: EncodingContext(),
            superEncoderTarget: nil,
            keepsTableKeys: keepsTableKeys
        )
    }

    private init(
        codingPath: [any CodingKey],
        userInfo: [CodingUserInfoKey: Any],
        options: EncodingOptions,
        context: EncodingContext,
        superEncoderTarget: (table: EncodedTable, key: String)?,
        keepsTableKeys: Bool
    ) {
        self.codingPath = codingPath
        self.userInfo = userInfo
        self.options = options
        self.context = context
        self.superEncoderTarget = superEncoderTarget
        self.keepsTableKeys = keepsTableKeys
    }

    deinit {
        // Like `JSONEncoder`, a keyed super encoder writes its value when it's released,
        // so the value replaces one that the parent wrote at the key after it created the super encoder.
        if let superEncoderTarget {
            superEncoderTarget.table.entries[superEncoderTarget.key] = .slot(slot)
        }
    }

    /// Returns a super encoder at the given coding path
    /// that shares this encoder's options and error context.
    ///
    /// - Parameter target: The table and key where the super encoder
    ///   writes its value again when it's released, if any.
    fileprivate func makeSuperEncoder(
        codingPath: [any CodingKey],
        target: (table: EncodedTable, key: String)?
    ) -> _TOMLEncoder {
        _TOMLEncoder(
            codingPath: codingPath,
            userInfo: userInfo,
            options: options,
            context: context,
            superEncoderTarget: target,
            keepsTableKeys: false
        )
    }

    /// The value that the encoder holds,
    /// or `nil` if nothing is encoded.
    ///
    /// - Throws: The first error that a container recorded
    ///   because it couldn't throw when the fault happened.
    func encodedValue() throws -> TOMLValue? {
        if let error = context.error {
            throw error
        }
        return storage?.resolved()
    }

    /// Records an error for a fault in a method that can't throw.
    ///
    /// ``encodedValue()`` throws the error
    /// when the value that this encoder encodes is finished.
    ///
    /// Only the first error is kept.
    fileprivate func recordError(_ message: String, codingPath: [any CodingKey]) {
        if context.error == nil {
            context.error = .invalidValue(message, codingPath: codingPath)
        }
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        let table = tableStorage(at: &storage) ?? conflictingTable(at: codingPath)
        let container = TOMLKeyedEncodingContainer<Key>(
            encoder: self,
            codingPath: codingPath,
            table: table,
            convertsKeys: !keepsTableKeys
        )
        return KeyedEncodingContainer(container)
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        TOMLUnkeyedEncodingContainer(
            encoder: self,
            codingPath: codingPath,
            array: arrayStorage(at: &storage) ?? conflictingArray(at: codingPath)
        )
    }

    func singleValueContainer() -> any SingleValueEncodingContainer {
        TOMLSingleValueEncodingContainer(
            encoder: self,
            codingPath: codingPath
        )
    }

    func setValue(_ value: TOMLValue) {
        storage = .value(value)
    }

    /// Records an error for a keyed container
    /// that can't write at the given path,
    /// and returns a table that isn't part of the output.
    fileprivate func conflictingTable(at codingPath: [any CodingKey]) -> EncodedTable {
        recordError(
            "Unable to encode a keyed container where a value of another type is already encoded",
            codingPath: codingPath
        )
        return EncodedTable()
    }

    /// Records an error for an unkeyed container
    /// that can't write at the given path,
    /// and returns an array that isn't part of the output.
    fileprivate func conflictingArray(at codingPath: [any CodingKey]) -> EncodedArray {
        recordError(
            "Unable to encode an unkeyed container where a value of another type is already encoded",
            codingPath: codingPath
        )
        return EncodedArray()
    }
}

// MARK: - Boxing Helpers

private extension _TOMLEncoder {
    func box(_ date: Date) -> TOMLValue {
        switch options.dateEncodingStrategy {
        case .iso8601:
            return .offsetDateTime(date)
        case .localDateTime:
            let components = gregorianComponents(
                [.year, .month, .day, .hour, .minute, .second, .nanosecond],
                of: date,
                inTimeZoneOf: .current
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
            let components = gregorianComponents([.year, .month, .day], of: date, inTimeZoneOf: .current)
            return .localDate(
                LocalDate(
                    year: components.year ?? 0,
                    month: components.month ?? 0,
                    day: components.day ?? 0
                )
            )
        case .localTime:
            let components = gregorianComponents(
                [.hour, .minute, .second, .nanosecond],
                of: date,
                inTimeZoneOf: .current
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

    /// Converts a value to a TOML value,
    /// using a new encoder at the given coding path for most types.
    func box<T: Encodable>(_ value: T, codingPath: [any CodingKey]) throws -> TOMLValue {
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

        // The value gets its own error context,
        // so an error that the caller catches doesn't reach later values.
        let encoder = _TOMLEncoder(
            codingPath: codingPath,
            userInfo: userInfo,
            options: options,
            keepsTableKeys: value is any StringKeyedDictionary
        )
        try value.encode(to: encoder)

        if let v = try encoder.encodedValue() {
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

// MARK: - Local Date Components

/// Returns the components of a date in the Gregorian calendar,
/// in the time zone of the given calendar.
///
/// TOML dates use the Gregorian calendar, as ``TOMLDecoder`` does,
/// so this ignores the calendar system of `calendar`,
/// such as the Buddhist or Japanese calendar, and uses only its time zone.
func gregorianComponents(
    _ components: Set<Calendar.Component>,
    of date: Date,
    inTimeZoneOf calendar: Calendar
) -> DateComponents {
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = calendar.timeZone
    return gregorian.dateComponents(components, from: date)
}

// MARK: - Integer Encoding

/// Converts an unsigned integer to a TOML integer.
///
/// TOML integers are 64-bit signed integers,
/// so this throws for a value greater than `Int64.max`.
private func encodeInteger<T: UnsignedInteger>(_ value: T, codingPath: [any CodingKey]) throws -> TOMLValue {
    guard let integer = Int64(exactly: value) else {
        throw TOMLEncodingError.invalidValue(
            "\(value) is greater than the maximum TOML integer, \(Int64.max)",
            codingPath: codingPath
        )
    }
    return .integer(integer)
}

// MARK: - Encoding Storage

/// The errors that an encoder, its containers, and its super encoders record.
///
/// The top-level value and each value that a container boxes
/// get their own context,
/// so an error reaches the code that encodes that value,
/// and a caller that catches it can write another value.
private final class EncodingContext {
    /// The first error that a container recorded
    /// in a method that can't throw.
    var error: TOMLEncodingError?
}

/// A value that encoding can still change,
/// because a container or super encoder writes to it.
///
/// Tables and arrays are references,
/// so a nested container writes into its parent at its key or index.
/// The encoder turns its storage into a ``TOMLValue`` when encoding finishes.
private enum EncodedValue {
    /// A finished value.
    case value(TOMLValue)

    /// A table that keyed containers write to.
    case table(EncodedTable)

    /// An array that unkeyed containers write to.
    case array(EncodedArray)

    /// The place for the value that a super encoder writes.
    case slot(EncodedSlot)

    func resolved() -> TOMLValue {
        switch self {
        case .value(let value):
            return value
        case .table(let table):
            return .table(table.entries.mapValues { $0.resolved() })
        case .array(let array):
            return .array(array.elements.map { $0.resolved() })
        case .slot(let slot):
            // Like `JSONEncoder`, a super encoder that encodes nothing writes an empty table.
            return slot.value?.resolved() ?? .table([:])
        }
    }
}

/// The place that holds the value an encoder writes.
private final class EncodedSlot {
    var value: EncodedValue?
}

private final class EncodedTable {
    var entries: [String: EncodedValue]

    init(entries: [String: EncodedValue] = [:]) {
        self.entries = entries
    }
}

private final class EncodedArray {
    var elements: [EncodedValue]

    init(elements: [EncodedValue] = []) {
        self.elements = elements
    }
}

/// Returns the table that a keyed container writes to at `value`,
/// creating it if nothing is encoded there,
/// or `nil` if a value of another type is encoded there.
///
/// Like `JSONEncoder`, a second keyed container at one place
/// writes to the same table,
/// and a keyed container adds to a table that a value encoded there.
private func tableStorage(at value: inout EncodedValue?) -> EncodedTable? {
    switch value {
    case nil:
        let table = EncodedTable()
        value = .table(table)
        return table
    case .table(let table):
        return table
    case .value(.table(let entries)):
        let table = EncodedTable(entries: entries.mapValues { .value($0) })
        value = .table(table)
        return table
    case .slot(let slot):
        return tableStorage(at: &slot.value)
    case .value, .array:
        return nil
    }
}

/// Returns the array that an unkeyed container writes to at `value`,
/// creating it if nothing is encoded there,
/// or `nil` if a value of another type is encoded there.
///
/// Like `JSONEncoder`, a second unkeyed container at one place
/// appends to the same array,
/// and an unkeyed container appends to an array that a value encoded there.
private func arrayStorage(at value: inout EncodedValue?) -> EncodedArray? {
    switch value {
    case nil:
        let array = EncodedArray()
        value = .array(array)
        return array
    case .array(let array):
        return array
    case .value(.array(let elements)):
        let array = EncodedArray(elements: elements.map { .value($0) })
        value = .array(array)
        return array
    case .slot(let slot):
        return arrayStorage(at: &slot.value)
    case .value, .table:
        return nil
    }
}

// MARK: - Keyed Encoding Container

private struct TOMLKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    var codingPath: [any CodingKey]
    let encoder: _TOMLEncoder

    private let table: EncodedTable

    /// Whether the container applies the key encoding strategy to its keys.
    private let convertsKeys: Bool

    init(encoder: _TOMLEncoder, codingPath: [any CodingKey], table: EncodedTable, convertsKeys: Bool = true) {
        self.encoder = encoder
        self.codingPath = codingPath
        self.table = table
        self.convertsKeys = convertsKeys
    }

    /// Returns the key that the container writes in its table for a coding key.
    private func convertKey(_ key: any CodingKey) -> String {
        convertsKeys ? encoder.convertKey(key) : key.stringValue
    }

    /// Writes a value at the given key.
    ///
    /// Like `JSONEncoder`, the last value written at a key replaces the others.
    private func set(_ value: TOMLValue, forKey key: Key) {
        table.entries[convertKey(key)] = .value(value)
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
        set(try encodeInteger(value, codingPath: codingPath + [key]), forKey: key)
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
        set(try encodeInteger(value, codingPath: codingPath + [key]), forKey: key)
    }

    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        let boxed = try encoder.box(value, codingPath: codingPath)
        set(boxed, forKey: key)
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type,
        forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> {
        let nestedPath = codingPath + [key]
        let nestedTable =
            tableStorage(at: &table.entries[convertKey(key)])
            ?? encoder.conflictingTable(at: nestedPath)
        let container = TOMLKeyedEncodingContainer<NestedKey>(
            encoder: encoder,
            codingPath: nestedPath,
            table: nestedTable
        )
        return KeyedEncodingContainer(container)
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
        let nestedPath = codingPath + [key]
        let nestedArray =
            arrayStorage(at: &table.entries[convertKey(key)])
            ?? encoder.conflictingArray(at: nestedPath)
        return TOMLUnkeyedEncodingContainer(
            encoder: encoder,
            codingPath: nestedPath,
            array: nestedArray
        )
    }

    mutating func superEncoder() -> any Encoder {
        superEncoder(forCodingKey: TOMLCodingKey(stringValue: "super"))
    }

    mutating func superEncoder(forKey key: Key) -> any Encoder {
        superEncoder(forCodingKey: key)
    }

    /// Returns an encoder that writes its value at the given key.
    ///
    /// Like `JSONEncoder`, the super encoder's value replaces any value at the key,
    /// including a value that this container writes there
    /// before the super encoder is released.
    /// A value that this container writes at the key after that release
    /// replaces the super encoder's value.
    private func superEncoder(forCodingKey key: any CodingKey) -> any Encoder {
        let convertedKey = convertKey(key)
        let superEncoder = encoder.makeSuperEncoder(
            codingPath: codingPath + [key],
            target: (table, convertedKey)
        )
        // Reserve the key now, so the value is kept
        // even if the super encoder is still alive when encoding finishes.
        table.entries[convertedKey] = .slot(superEncoder.slot)
        return superEncoder
    }
}

// MARK: - Unkeyed Encoding Container

private struct TOMLUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    var codingPath: [any CodingKey]
    let encoder: _TOMLEncoder

    private let array: EncodedArray

    var count: Int { array.elements.count }

    init(encoder: _TOMLEncoder, codingPath: [any CodingKey], array: EncodedArray) {
        self.encoder = encoder
        self.codingPath = codingPath
        self.array = array
    }

    private func append(_ value: TOMLValue) {
        array.elements.append(.value(value))
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
        append(try encodeInteger(value, codingPath: codingPath + [TOMLCodingKey(index: count)]))
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
        append(try encodeInteger(value, codingPath: codingPath + [TOMLCodingKey(index: count)]))
    }

    mutating func encode<T: Encodable>(_ value: T) throws {
        let boxed = try encoder.box(value, codingPath: codingPath)
        append(boxed)
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type
    ) -> KeyedEncodingContainer<NestedKey> {
        let nestedPath = codingPath + [TOMLCodingKey(index: count)]
        let nestedTable = EncodedTable()
        array.elements.append(.table(nestedTable))
        let container = TOMLKeyedEncodingContainer<NestedKey>(
            encoder: encoder,
            codingPath: nestedPath,
            table: nestedTable
        )
        return KeyedEncodingContainer(container)
    }

    mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
        let nestedPath = codingPath + [TOMLCodingKey(index: count)]
        let nestedArray = EncodedArray()
        array.elements.append(.array(nestedArray))
        return TOMLUnkeyedEncodingContainer(
            encoder: encoder,
            codingPath: nestedPath,
            array: nestedArray
        )
    }

    /// Returns an encoder that writes its value at the next index,
    /// even after other values are appended to this container.
    mutating func superEncoder() -> any Encoder {
        let superEncoder = encoder.makeSuperEncoder(
            codingPath: codingPath + [TOMLCodingKey(index: count)],
            target: nil
        )
        array.elements.append(.slot(superEncoder.slot))
        return superEncoder
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
        encoder.setValue(try encodeInteger(value, codingPath: codingPath))
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
        encoder.setValue(try encodeInteger(value, codingPath: codingPath))
    }

    mutating func encode<T: Encodable>(_ value: T) throws {
        let boxed = try encoder.box(value, codingPath: codingPath)
        encoder.setValue(boxed)
    }
}

// MARK: - Private Extensions

private extension String {
    /// Converts a camelCase key to snake_case, as `JSONEncoder` does.
    ///
    /// This follows Foundation's algorithm.
    /// A word starts at an uppercase letter that follows a letter that isn't uppercase,
    /// and at the last letter of a run of uppercase letters that a lowercase letter follows.
    /// The first character never starts a word.
    /// The conversion joins the words with underscores and lowercases them.
    /// It keeps leading and trailing underscores.
    ///
    /// For example, `userID` becomes `user_id`, `myURLValue` becomes `my_url_value`,
    /// `URLSession` becomes `u_rl_session`, and `PATH` becomes `p_ath`.
    ///
    /// Like Foundation, the conversion tests Unicode scalars for letters,
    /// but it moves by characters to skip the first character
    /// and to find the characters next to a letter,
    /// so it doesn't separate an accent from its letter.
    /// These methods round an index inside a character down to the start of the character.
    func convertToSnakeCase() -> String {
        guard !isEmpty else { return self }

        var words: [Range<String.Index>] = []
        var wordStart = startIndex
        var searchStart = index(after: wordStart)

        while let upper = self[searchStart...].unicodeScalars.firstIndex(where: \.isUppercaseLetter) {
            words.append(wordStart ..< upper)

            guard let lower = self[upper...].unicodeScalars.firstIndex(where: \.isLowercaseLetter) else {
                // No lowercase letters follow, so the rest of the key is one word.
                wordStart = upper
                break
            }

            let beforeLower = index(before: lower)
            if lower == index(after: upper) || beforeLower < upper {
                // A lowercase letter follows the uppercase letter, so they're in one word.
                // The character before the lowercase letter can also start before the uppercase letter,
                // such as in `"a\u{0600}A\u{0600}a"`, where `JSONEncoder` stops with a fatal error;
                // the conversion doesn't start a word there.
                wordStart = upper
            } else {
                // A run of uppercase letters is a word,
                // except for its last character, which starts the next word.
                words.append(upper ..< beforeLower)
                wordStart = beforeLower
            }
            searchStart = unicodeScalars.index(after: lower)
        }
        words.append(wordStart ..< endIndex)

        return words.map { self[$0].lowercased() }.joined(separator: "_")
    }
}

private extension Unicode.Scalar {
    /// Whether the scalar is in the Unicode general category Lu or Lt,
    /// as in Foundation's `uppercaseLetters` character set.
    var isUppercaseLetter: Bool {
        switch properties.generalCategory {
        case .uppercaseLetter, .titlecaseLetter: return true
        default: return false
        }
    }

    /// Whether the scalar is in the Unicode general category Ll,
    /// as in Foundation's `lowercaseLetters` character set.
    var isLowercaseLetter: Bool {
        properties.generalCategory == .lowercaseLetter
    }
}

private extension TOMLValue {
    var isTable: Bool {
        if case .table = self { return true }
        return false
    }

    var typeName: String {
        switch self {
        case .string: return "a string"
        case .integer: return "an integer"
        case .float: return "a float"
        case .boolean: return "a boolean"
        case .offsetDateTime: return "an offset date-time"
        case .localDateTime: return "a local date-time"
        case .localDate: return "a local date"
        case .localTime: return "a local time"
        case .array: return "an array"
        case .table: return "a table"
        }
    }
}
