/// A local date-time without timezone information.
///
/// This type represents a date and time as they would appear on a calendar
/// and clock, without any reference to a particular timezone. Use this type
/// when encoding or decoding TOML local date-time values.
///
/// Example TOML:
/// ```toml
/// created_at = 2024-01-15T09:30:00
/// ```
public struct LocalDateTime: Sendable, Equatable, Hashable, Codable {
    /// The year component.
    public var year: Int

    /// The month component (1-12).
    public var month: Int

    /// The day component (1-31).
    public var day: Int

    /// The hour component (0-23).
    public var hour: Int

    /// The minute component (0-59).
    public var minute: Int

    /// The second component (0-60, where 60 is a leap second).
    public var second: Int

    /// The nanosecond component (0-999999999).
    public var nanosecond: Int

    /// Creates a new local date-time.
    ///
    /// - Parameters:
    ///   - year: The year component.
    ///   - month: The month component (1-12).
    ///   - day: The day component (1-31).
    ///   - hour: The hour component (0-23).
    ///   - minute: The minute component (0-59).
    ///   - second: The second component (0-60, where 60 is a leap second).
    ///   - nanosecond: The nanosecond component (0-999999999). Defaults to 0.
    public init(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int, nanosecond: Int = 0) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
        self.nanosecond = nanosecond
    }
}

/// A local date without time or timezone information.
///
/// This type represents a calendar date without any time component.
/// Use this type when encoding or decoding TOML local date values.
///
/// Example TOML:
/// ```toml
/// birthday = 1990-05-15
/// ```
public struct LocalDate: Sendable, Equatable, Hashable, Codable {
    /// The year component.
    public var year: Int

    /// The month component (1-12).
    public var month: Int

    /// The day component (1-31).
    public var day: Int

    /// Creates a new local date.
    ///
    /// - Parameters:
    ///   - year: The year component.
    ///   - month: The month component (1-12).
    ///   - day: The day component (1-31).
    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }
}

/// A local time without date or timezone information.
///
/// This type represents a time of day without any date component.
/// Use this type when encoding or decoding TOML local time values.
///
/// Example TOML:
/// ```toml
/// alarm = 07:30:00
/// ```
public struct LocalTime: Sendable, Equatable, Hashable, Codable {
    /// The hour component (0-23).
    public var hour: Int

    /// The minute component (0-59).
    public var minute: Int

    /// The second component (0-60, where 60 is a leap second).
    public var second: Int

    /// The nanosecond component (0-999999999).
    public var nanosecond: Int

    /// Creates a new local time.
    ///
    /// - Parameters:
    ///   - hour: The hour component (0-23).
    ///   - minute: The minute component (0-59).
    ///   - second: The second component (0-60, where 60 is a leap second).
    ///   - nanosecond: The nanosecond component (0-999999999). Defaults to 0.
    public init(hour: Int, minute: Int, second: Int, nanosecond: Int = 0) {
        self.hour = hour
        self.minute = minute
        self.second = second
        self.nanosecond = nanosecond
    }
}
