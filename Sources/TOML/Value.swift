import Foundation

/// A dynamically-typed TOML value.
///
/// `TOMLValue` represents the various value types defined in the
/// [TOML specification](https://toml.io/en/v1.1.0), including strings,
/// integers, floats, booleans, dates and times, arrays, and tables.
///
/// This type is used internally during encoding and decoding,
/// and can also be used directly when working with TOML data
/// in a type-erased manner.
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
