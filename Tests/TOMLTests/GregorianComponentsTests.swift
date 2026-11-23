import Foundation
import Testing

@testable import TOML

@Suite("Gregorian Components Tests")
struct GregorianComponentsTests {
    /// 2024-01-15T09:30:00.25Z
    let date = Date(timeIntervalSince1970: 1_705_311_000.25)

    let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]

    static let calendars: [Calendar.Identifier] = [.buddhist, .japanese, .islamicCivil, .gregorian]

    @Test(arguments: calendars, ["UTC", "Asia/Tokyo", "America/Los_Angeles"])
    func ignoresCallersCalendarSystem(identifier: Calendar.Identifier, timeZone: String) throws {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = try #require(TimeZone(identifier: timeZone))

        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone

        let result = gregorianComponents(components, of: date, inTimeZoneOf: calendar)
        #expect(result == gregorian.dateComponents(components, from: date))
    }

    @Test func buddhistCalendarGivesGregorianYear() throws {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = try #require(TimeZone(identifier: "UTC"))

        // The Buddhist calendar's year for this date is 2567.
        #expect(buddhist.component(.year, from: date) == 2567)

        let result = gregorianComponents(components, of: date, inTimeZoneOf: buddhist)
        #expect(result.year == 2024)
        #expect(result.month == 1)
        #expect(result.day == 15)
        #expect(result.hour == 9)
        #expect(result.minute == 30)
        #expect(result.second == 0)
    }

    @Test func usesTimeZoneOfCalendar() throws {
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))

        let result = gregorianComponents(components, of: date, inTimeZoneOf: japanese)
        #expect(result.year == 2024)
        #expect(result.hour == 18)
    }
}
