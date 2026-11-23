import Foundation

/// A dynamically-typed TOML value.
///
/// `TOMLValue` represents the various value types defined in the
/// [TOML specification](https://toml.io/en/v1.1.0), including strings,
/// integers, floats, booleans, dates and times, arrays, and tables.
///
/// Use `TOMLValue` to work with a document whose structure you don't know in advance.
/// ``TOMLDecoder`` decodes a document or a part of one as it's written,
/// without the date or key decoding strategies:
///
/// ```swift
/// let document = try TOMLDecoder().decode(TOMLValue.self, from: toml)
/// if case .table(let table) = document, case .integer(let port)? = table["port"] {
///     print(port)
/// }
/// ```
///
/// A `TOMLValue` or `[String: TOMLValue]` property in a `Decodable` type
/// gets its part of the document in the same way,
/// such as a table whose keys you don't know:
///
/// ```swift
/// struct Package: Codable {
///     var name: String
///     var metadata: [String: TOMLValue]
/// }
/// ```
///
/// ``TOMLEncoder`` writes a `TOMLValue` as it is,
/// without the date or key encoding strategies.
/// A top-level `TOMLValue` must be a table.
///
/// Other coders, such as `JSONEncoder` and `JSONDecoder`,
/// encode each case as a single value, an array, or a keyed container,
/// and encode each date-time case with its value's own `Codable` conformance.
/// They decode a boolean, integer, float, string, array, or table,
/// in that order, so an integer decodes as ``integer(_:)``.
/// Through other coders, the date-time cases can't be told apart from other values:
/// for example, `JSONDecoder` decodes an encoded ``localDate(_:)``
/// as a ``table(_:)`` with `year`, `month`, and `day` keys.
public enum TOMLValue: Sendable, Equatable {
    /// A string value.
    case string(String)

    /// A 64-bit signed integer value.
    case integer(Int64)

    /// A double-precision floating-point value.
    case float(Double)

    /// A boolean value.
    case boolean(Bool)

    /// An offset date-time with timezone information.
    ///
    /// This corresponds to TOML's offset date-time type (RFC 3339).
    case offsetDateTime(Date)

    /// A local date-time without timezone information.
    case localDateTime(LocalDateTime)

    /// A local date without time or timezone information.
    case localDate(LocalDate)

    /// A local time without date or timezone information.
    case localTime(LocalTime)

    /// An array of TOML values.
    case array([TOMLValue])

    /// A table (dictionary) of string keys to TOML values.
    case table([String: TOMLValue])
}

// MARK: - Codable

extension TOMLValue: Codable {
    /// Creates a value from the given decoder.
    ///
    /// From a ``TOMLDecoder``, this decodes the value as it's written in the document.
    /// From another decoder, it decodes a boolean, integer, float, string, array, or table,
    /// in that order.
    public init(from decoder: any Decoder) throws {
        if let decoder = decoder as? _TOMLDecoder {
            self = decoder.value
            return
        }

        if let container = try? decoder.singleValueContainer() {
            if let value = try? container.decode(Bool.self) {
                self = .boolean(value)
                return
            }
            if let value = try? container.decode(Int64.self) {
                self = .integer(value)
                return
            }
            if let value = try? container.decode(Double.self) {
                self = .float(value)
                return
            }
            if let value = try? container.decode(String.self) {
                self = .string(value)
                return
            }
        }

        if var container = try? decoder.unkeyedContainer() {
            var array: [TOMLValue] = []
            while !container.isAtEnd {
                array.append(try container.decode(TOMLValue.self))
            }
            self = .array(array)
            return
        }

        if let container = try? decoder.container(keyedBy: TOMLCodingKey.self) {
            var table: [String: TOMLValue] = [:]
            for key in container.allKeys {
                table[key.stringValue] = try container.decode(TOMLValue.self, forKey: key)
            }
            self = .table(table)
            return
        }

        throw DecodingError.typeMismatch(
            TOMLValue.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected a boolean, integer, float, string, array, or table"
            )
        )
    }

    /// Encodes the value into the given encoder.
    ///
    /// ``TOMLEncoder`` writes the value as it is.
    /// Another encoder gets each case as a single value, an array, or a keyed container.
    public func encode(to encoder: any Encoder) throws {
        if let encoder = encoder as? _TOMLEncoder {
            encoder.setValue(self)
            return
        }

        switch self {
        case .string(let value): try encodeSingleValue(value, to: encoder)
        case .integer(let value): try encodeSingleValue(value, to: encoder)
        case .float(let value): try encodeSingleValue(value, to: encoder)
        case .boolean(let value): try encodeSingleValue(value, to: encoder)
        case .offsetDateTime(let value): try encodeSingleValue(value, to: encoder)
        case .localDateTime(let value): try encodeSingleValue(value, to: encoder)
        case .localDate(let value): try encodeSingleValue(value, to: encoder)
        case .localTime(let value): try encodeSingleValue(value, to: encoder)
        case .array(let array):
            var container = encoder.unkeyedContainer()
            for element in array {
                try container.encode(element)
            }
        case .table(let table):
            var container = encoder.container(keyedBy: TOMLCodingKey.self)
            for (key, value) in table {
                try container.encode(value, forKey: TOMLCodingKey(stringValue: key))
            }
        }
    }
}

private func encodeSingleValue<T: Encodable>(_ value: T, to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(value)
}
