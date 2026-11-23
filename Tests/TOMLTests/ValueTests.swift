import Foundation
import Testing

import TOML

@Suite("TOMLValue Codable Tests")
struct ValueTests {
    static let document = """
        string = "text"
        integer = 42
        float = 1.5
        boolean = true
        offset_date_time = 1979-05-27T07:32:00Z
        local_date_time = 1979-05-27T07:32:00.5
        local_date = 1979-05-27
        local_time = 07:32:00
        array = [1, "two", [3]]
        inline = { first_name = "Ada" }

        [table]
        nested_key = 1

        [[items]]
        item_name = "a"
        """

    static let expected: TOMLValue = .table([
        "string": .string("text"),
        "integer": .integer(42),
        "float": .float(1.5),
        "boolean": .boolean(true),
        "offset_date_time": .offsetDateTime(Date(timeIntervalSince1970: 296_638_320)),
        "local_date_time": .localDateTime(
            LocalDateTime(year: 1979, month: 5, day: 27, hour: 7, minute: 32, second: 0, nanosecond: 500_000_000)
        ),
        "local_date": .localDate(LocalDate(year: 1979, month: 5, day: 27)),
        "local_time": .localTime(LocalTime(hour: 7, minute: 32, second: 0)),
        "array": .array([.integer(1), .string("two"), .array([.integer(3)])]),
        "inline": .table(["first_name": .string("Ada")]),
        "table": .table(["nested_key": .integer(1)]),
        "items": .array([.table(["item_name": .string("a")])]),
    ])

    // MARK: - TOMLDecoder

    @Test func decodeDocument() throws {
        let value = try TOMLDecoder().decode(TOMLValue.self, from: Self.document)
        #expect(value == Self.expected)
    }

    /// The decoder doesn't apply its date or key strategy to a `TOMLValue`.
    @Test func decodeDocumentIgnoresStrategies() throws {
        let decoder = TOMLDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let value = try decoder.decode(TOMLValue.self, from: Self.document)
        #expect(value == Self.expected)
    }

    @Test func decodeProperties() throws {
        struct Config: Decodable {
            let integer: TOMLValue
            let localTime: TOMLValue
            let table: TOMLValue
            let array: [TOMLValue]
        }

        let decoder = TOMLDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let config = try decoder.decode(Config.self, from: Self.document)

        #expect(config.integer == .integer(42))
        #expect(config.localTime == .localTime(LocalTime(hour: 7, minute: 32, second: 0)))
        #expect(config.table == .table(["nested_key": .integer(1)]))
        #expect(config.array == [.integer(1), .string("two"), .array([.integer(3)])])
    }

    @Test func decodeOpenEndedTable() throws {
        struct Package: Decodable {
            let name: String
            let metadata: [String: TOMLValue]
        }

        let toml = """
            name = "toml"

            [metadata]
            release_date = 2024-01-15
            maintainers = ["Ada"]
            docs = { base_url = "https://example.com" }
            """

        let decoder = TOMLDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let package = try decoder.decode(Package.self, from: toml)

        #expect(package.name == "toml")
        #expect(
            package.metadata == [
                "release_date": .localDate(LocalDate(year: 2024, month: 1, day: 15)),
                "maintainers": .array([.string("Ada")]),
                "docs": .table(["base_url": .string("https://example.com")]),
            ]
        )
    }

    // MARK: - TOMLEncoder

    /// The encoder writes a `TOMLValue` as it is,
    /// without its date or key strategy.
    @Test func encodeDocumentRoundTrip() throws {
        let encoder = TOMLEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(Self.expected)

        #expect(try TOMLDecoder().decode(TOMLValue.self, from: data) == Self.expected)
    }

    /// The encoder writes an offset date-time with millisecond precision.
    @Test func encodeOffsetDateTimeWithMillisecondPrecision() throws {
        let value = try TOMLDecoder().decode(TOMLValue.self, from: "time = 1979-05-27T07:32:00.123456Z")
        let toml = try TOMLEncoder().encodeToString(value)
        #expect(toml == "time = 1979-05-27T07:32:00.123Z\n")
    }

    @Test func encodeProperty() throws {
        struct Package: Encodable {
            let name: String
            let metadata: TOMLValue
        }

        let package = Package(
            name: "toml",
            metadata: .table([
                "releaseDate": .localDate(LocalDate(year: 2024, month: 1, day: 15)),
                "tags": .array([.string("a"), .string("b")]),
            ])
        )
        let encoder = TOMLEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = .sortedKeys

        #expect(
            try encoder.encodeToString(package) == """
                name = "toml"

                [metadata]
                releaseDate = 2024-01-15
                tags = ["a", "b"]

                """
        )
    }

    @Test(arguments: [
        TOMLValue.string("text"), .integer(1), .array([.integer(1)]),
        .localDate(LocalDate(year: 2024, month: 1, day: 15)),
    ])
    func encodeTopLevelNonTableThrows(value: TOMLValue) {
        #expect {
            try TOMLEncoder().encode(value)
        } throws: { error in
            guard case .invalidValue = error as? TOMLEncodingError else { return false }
            return true
        }
    }

    // MARK: - Other Coders

    @Test func jsonRoundTrip() throws {
        let value: TOMLValue = .table([
            "string": .string("text"),
            "integer": .integer(42),
            "float": .float(1.5),
            "boolean": .boolean(false),
            "array": .array([.integer(1), .string("two"), .array([])]),
            "table": .table(["key": .table([:])]),
        ])

        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(TOMLValue.self, from: data) == value)
    }

    @Test func jsonEncodesDateTimesWithTheirOwnConformances() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .secondsSince1970

        let localDate = TOMLValue.localDate(LocalDate(year: 2024, month: 1, day: 15))
        let localDateJSON = String(decoding: try encoder.encode(localDate), as: UTF8.self)
        #expect(localDateJSON == #"{"day":15,"month":1,"year":2024}"#)
        #expect(
            try JSONDecoder().decode(TOMLValue.self, from: Data(localDateJSON.utf8))
                == .table(["day": .integer(15), "month": .integer(1), "year": .integer(2024)])
        )

        let offsetDateTime = TOMLValue.offsetDateTime(Date(timeIntervalSince1970: 1))
        #expect(String(decoding: try encoder.encode(offsetDateTime), as: UTF8.self) == "1")
    }

    @Test func jsonNullThrows() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TOMLValue.self, from: Data("null".utf8))
        }
    }
}
