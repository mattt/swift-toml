import Foundation
import Testing

import TOML

@Suite("TOML Decoder Tests")
struct TOMLDecoderTests {

    // MARK: - Basic Types

    @Test func decodeSimpleTypes() throws {
        let toml = """
            title = "Test Config"
            port = 8080
            enabled = true
            ratio = 3.14
            """

        struct Config: Codable, Equatable {
            let title: String
            let port: Int
            let enabled: Bool
            let ratio: Double
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.title == "Test Config")
        #expect(config.port == 8080)
        #expect(config.enabled == true)
        #expect(config.ratio == 3.14)
    }

    @Test func decodeURL() throws {
        let toml = """
            url = "https://example.com/"
            """

        struct Config: Codable, Equatable {
            let url: URL
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)
        #expect(config.url == URL(string: "https://example.com/"))
    }

    @Test func decodeURLFromSingleValueContainer() throws {
        struct Container: Codable {
            let url: URL
            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                self.url = try container.decode(URL.self)
            }
        }

        struct Config: Codable {
            let container: Container
        }

        let toml = """
            container = "https://example.com/"
            """

        let config = try TOMLDecoder().decode(Config.self, from: toml)
        #expect(config.container.url.absoluteString == "https://example.com/")
    }

    @Test func decodeURLFromUnkeyedContainer() throws {
        let toml = """
            urls = ["https://example.com/", "https://swift.org/"]
            """

        struct Config: Codable {
            let urls: [URL]
        }

        let config = try TOMLDecoder().decode(Config.self, from: toml)
        #expect(config.urls == [URL(string: "https://example.com/")!, URL(string: "https://swift.org/")!])
    }

    @Test func decodeURLFromTable() throws {
        // TOMLEncoder writes this table for a URL by default,
        // using URL's own Encodable conformance.
        let toml = """
            [url]
            relative = "https://example.com/"
            """

        struct Config: Codable {
            let url: URL
        }

        let config = try TOMLDecoder().decode(Config.self, from: toml)
        #expect(config.url == URL(string: "https://example.com/"))
    }

    @Test func decodeInvalidURLString() throws {
        let toml = """
            url = "http://[::1"
            """

        struct Config: Codable {
            let url: URL
        }

        do {
            _ = try TOMLDecoder().decode(Config.self, from: toml)
            Issue.record("Expected a decoding error")
        } catch DecodingError.dataCorrupted(let context) {
            #expect(context.codingPath.map(\.stringValue) == ["url"])
            #expect(context.debugDescription == "Invalid URL string: \"http://[::1\"")
        }
    }

    @Test func decodeInvalidURLStringInArray() throws {
        let toml = """
            urls = ["https://example.com/", "http://[::1"]
            """

        struct Config: Codable {
            let urls: [URL]
        }

        do {
            _ = try TOMLDecoder().decode(Config.self, from: toml)
            Issue.record("Expected a decoding error")
        } catch DecodingError.dataCorrupted(let context) {
            #expect(context.codingPath.last?.intValue == 1)
        }
    }

    @Test func decodeURLTypeMismatchInArray() throws {
        let toml = """
            urls = [1, "https://example.com/"]
            """

        struct Config: Codable {
            let urls: [URL]
        }

        do {
            _ = try TOMLDecoder().decode(Config.self, from: toml)
            Issue.record("Expected a decoding error")
        } catch DecodingError.typeMismatch(_, let context) {
            #expect(context.codingPath.last?.intValue == 0)
        }
    }

    @Test func typeMismatchInArrayReportsElementIndex() throws {
        let toml = """
            numbers = [1, "two", 3]
            """

        struct Config: Codable {
            let numbers: [Int]
        }

        do {
            _ = try TOMLDecoder().decode(Config.self, from: toml)
            Issue.record("Expected a decoding error")
        } catch DecodingError.typeMismatch(_, let context) {
            #expect(context.codingPath.last?.intValue == 1)
        }
    }

    @Test func decodeAllIntegerTypes() throws {
        let toml = """
            int = 42
            int8 = 8
            int16 = 16
            int32 = 32
            int64 = 64
            uint = 100
            uint8 = 200
            uint16 = 300
            uint32 = 400
            uint64 = 500
            """

        struct IntTypes: Codable {
            let int: Int
            let int8: Int8
            let int16: Int16
            let int32: Int32
            let int64: Int64
            let uint: UInt
            let uint8: UInt8
            let uint16: UInt16
            let uint32: UInt32
            let uint64: UInt64
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(IntTypes.self, from: toml)

        #expect(config.int == 42)
        #expect(config.int8 == 8)
        #expect(config.int16 == 16)
        #expect(config.int32 == 32)
        #expect(config.int64 == 64)
        #expect(config.uint == 100)
        #expect(config.uint8 == 200)
        #expect(config.uint16 == 300)
        #expect(config.uint32 == 400)
        #expect(config.uint64 == 500)
    }

    @Test func decodeFloatTypes() throws {
        let toml = """
            float = 3.14
            double = 2.71828
            """

        struct FloatTypes: Codable {
            let float: Float
            let double: Double
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(FloatTypes.self, from: toml)

        #expect(abs(config.float - 3.14) < 0.001)
        #expect(config.double == 2.71828)
    }

    @Test func decodeSpecialFloatValues() throws {
        let toml = """
            infinity = inf
            negInfinity = -inf
            nan = nan
            """

        struct SpecialFloats: Codable {
            let infinity: Double
            let negInfinity: Double
            let nan: Double
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(SpecialFloats.self, from: toml)

        #expect(config.infinity == .infinity)
        #expect(config.negInfinity == -.infinity)
        #expect(config.nan.isNaN)
    }

    @Test func decodeIntegerAsDouble() throws {
        let toml = """
            value = 42
            """

        struct Config: Codable {
            let value: Double
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.value == 42.0)
    }

    // MARK: - Nested Tables

    @Test func decodeNestedTables() throws {
        let toml = """
            [database]
            server = "192.168.1.1"
            port = 5432

            [database.connection]
            timeout = 30
            """

        struct Config: Codable {
            struct Database: Codable {
                struct Connection: Codable {
                    let timeout: Int
                }
                let server: String
                let port: Int
                let connection: Connection
            }
            let database: Database
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.database.server == "192.168.1.1")
        #expect(config.database.port == 5432)
        #expect(config.database.connection.timeout == 30)
    }

    @Test func decodeDeeplyNestedTables() throws {
        let toml = """
            [level1.level2.level3]
            value = "deep"
            """

        struct Config: Codable {
            struct Level1: Codable {
                struct Level2: Codable {
                    struct Level3: Codable {
                        let value: String
                    }
                    let level3: Level3
                }
                let level2: Level2
            }
            let level1: Level1
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.level1.level2.level3.value == "deep")
    }

    // MARK: - Arrays

    @Test func decodeArrays() throws {
        let toml = """
            ports = [8001, 8002, 8003]
            names = ["alpha", "beta", "gamma"]
            """

        struct Config: Codable {
            let ports: [Int]
            let names: [String]
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.ports == [8001, 8002, 8003])
        #expect(config.names == ["alpha", "beta", "gamma"])
    }

    @Test func decodeEmptyArray() throws {
        let toml = """
            empty = []
            """

        struct Config: Codable {
            let empty: [Int]
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.empty.isEmpty)
    }

    @Test func decodeNestedArrays() throws {
        let toml = """
            matrix = [[1, 2], [3, 4]]
            """

        struct Config: Codable {
            let matrix: [[Int]]
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.matrix == [[1, 2], [3, 4]])
    }

    @Test func decodeMixedTypeArrayElements() throws {
        let toml = """
            values = [1, 2, 3]
            """

        struct Config: Codable {
            let values: [Double]
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.values == [1.0, 2.0, 3.0])
    }

    // MARK: - Array of Tables

    @Test func decodeArrayOfTables() throws {
        let toml = """
            [[products]]
            name = "Widget"
            price = 9.99

            [[products]]
            name = "Gadget"
            price = 19.99
            """

        struct Config: Codable {
            struct Product: Codable {
                let name: String
                let price: Double
            }
            let products: [Product]
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.products.count == 2)
        #expect(config.products[0].name == "Widget")
        #expect(config.products[1].price == 19.99)
    }

    @Test func decodeNestedArrayOfTables() throws {
        let toml = """
            [[servers]]
            name = "alpha"

            [[servers.endpoints]]
            path = "/api"
            method = "GET"

            [[servers.endpoints]]
            path = "/health"
            method = "GET"

            [[servers]]
            name = "beta"
            """

        struct Config: Codable {
            struct Server: Codable {
                struct Endpoint: Codable {
                    let path: String
                    let method: String
                }
                let name: String
                let endpoints: [Endpoint]?
            }
            let servers: [Server]
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.servers.count == 2)
        #expect(config.servers[0].endpoints?.count == 2)
        #expect(config.servers[0].endpoints?[0].path == "/api")
    }

    // MARK: - Date Types

    @Test func decodeOffsetDateTime() throws {
        let toml = """
            timestamp = 1979-05-27T07:32:00Z
            """

        struct Config: Codable {
            let timestamp: Date
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        let components = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(identifier: "UTC")!,
            from: config.timestamp
        )
        #expect(components.year == 1979)
        #expect(components.month == 5)
        #expect(components.day == 27)
    }

    @Test func decodeOffsetDateTimeWithOffset() throws {
        let toml = """
            timestamp = 1979-05-27T07:32:00+05:30
            """

        struct Config: Codable {
            let timestamp: Date
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.timestamp.timeIntervalSince1970 > 0)
    }

    @Test func decodeLocalDateTime() throws {
        let toml = """
            datetime = 2024-06-15T10:30:00
            """

        struct Config: Codable {
            let datetime: LocalDateTime
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.datetime.year == 2024)
        #expect(config.datetime.month == 6)
        #expect(config.datetime.day == 15)
        #expect(config.datetime.hour == 10)
        #expect(config.datetime.minute == 30)
        #expect(config.datetime.second == 0)
    }

    @Test func decodeLocalDate() throws {
        let toml = """
            date = 2024-06-15
            """

        struct Config: Codable {
            let date: LocalDate
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.date.year == 2024)
        #expect(config.date.month == 6)
        #expect(config.date.day == 15)
    }

    @Test func decodeLocalTime() throws {
        let toml = """
            time = 10:30:45
            """

        struct Config: Codable {
            let time: LocalTime
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.time.hour == 10)
        #expect(config.time.minute == 30)
        #expect(config.time.second == 45)
    }

    @Test func decodeLocalDateTimeAsDate() throws {
        let toml = """
            datetime = 2024-06-15T10:30:00
            """

        struct Config: Codable {
            let datetime: Date
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: config.datetime)
        #expect(components.year == 2024)
        #expect(components.month == 6)
        #expect(components.day == 15)
    }

    @Test func decodeLocalDateAsDate() throws {
        let toml = """
            date = 2024-06-15
            """

        struct Config: Codable {
            let date: Date
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: config.date)
        #expect(components.year == 2024)
        #expect(components.month == 6)
        #expect(components.day == 15)
    }

    // MARK: - Date Decoding Strategies

    @Test func decodeDateSecondsSince1970() throws {
        let toml = """
            timestamp = 1000.0
            """

        struct Config: Codable {
            let timestamp: Date
        }

        let decoder = TOMLDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.timestamp.timeIntervalSince1970 == 1000)
    }

    @Test func decodeDateMillisecondsSince1970() throws {
        let toml = """
            timestamp = 1000000.0
            """

        struct Config: Codable {
            let timestamp: Date
        }

        let decoder = TOMLDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.timestamp.timeIntervalSince1970 == 1000)
    }

    // MARK: - Key Decoding Strategy

    @Test func decodeConvertFromSnakeCase() throws {
        let toml = """
            userName = "john"
            userEmail = "john@example.com"
            createdAt = 123
            """

        struct Config: Codable {
            let userName: String
            let userEmail: String
            let createdAt: Int
        }

        let decoder = TOMLDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.userName == "john")
        #expect(config.userEmail == "john@example.com")
        #expect(config.createdAt == 123)
    }

    @Test func decodeUseDefaultKeys() throws {
        let toml = """
            userName = "john"
            """

        struct Config: Codable {
            let userName: String
        }

        let decoder = TOMLDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.userName == "john")
    }

    // MARK: - Optional Values

    @Test func decodeOptionalPresent() throws {
        let toml = """
            name = "test"
            nickname = "testy"
            """

        struct Config: Codable {
            let name: String
            let nickname: String?
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.name == "test")
        #expect(config.nickname == "testy")
    }

    @Test func decodeOptionalMissing() throws {
        let toml = """
            name = "test"
            """

        struct Config: Codable {
            let name: String
            let nickname: String?
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.name == "test")
        #expect(config.nickname == nil)
    }

    // MARK: - Dictionary Decoding

    @Test func decodeDictionary() throws {
        let toml = """
            key1 = "value1"
            key2 = "value2"
            """

        let decoder = TOMLDecoder()
        let config = try decoder.decode([String: String].self, from: toml)

        #expect(config["key1"] == "value1")
        #expect(config["key2"] == "value2")
    }

    @Test func decodeNestedDictionary() throws {
        let toml = """
            [outer]
            inner = 42
            """

        let decoder = TOMLDecoder()
        let config = try decoder.decode([String: [String: Int]].self, from: toml)

        #expect(config["outer"]?["inner"] == 42)
    }

    // MARK: - Decode from Data

    @Test func decodeFromData() throws {
        let toml = "name = \"test\""
        let data = toml.data(using: .utf8)!

        struct Config: Codable {
            let name: String
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: data)

        #expect(config.name == "test")
    }

    // MARK: - User Info

    @Test func decoderUserInfo() throws {
        let key = CodingUserInfoKey(rawValue: "testKey")!

        let toml = "name = \"test\""

        struct Config: Codable {
            let name: String
        }

        let decoder = TOMLDecoder()
        decoder.userInfo = [key: "testValue"]
        _ = try decoder.decode(Config.self, from: toml)
    }

    // MARK: - Decoding Limits

    @Test func decodingLimitsMaxInputSize() throws {
        let decoder = TOMLDecoder()
        decoder.limits.maxInputSize = 10
        let toml = "name = \"this is a very long string that exceeds the limit\""

        #expect(throws: TOMLDecodingError.self) {
            try decoder.decode([String: String].self, from: toml)
        }
    }

    @Test func decodingLimitsDefaults() {
        let limits = TOMLDecoder.DecodingLimits.default

        #expect(limits.maxInputSize == 10 * 1024 * 1024)
        #expect(limits.maxDepth == 128)
        #expect(limits.maxTableKeys == 10_000)
        #expect(limits.maxArrayLength == 100_000)
        #expect(limits.maxStringLength == 1024 * 1024)
    }

    @Test func decodingLimitsMaxDepth() throws {
        let decoder = TOMLDecoder()
        decoder.limits.maxDepth = 2
        // Depth: root (0) -> a (1) -> b (2) -> c (3) - exceeds limit of 2
        let toml = """
            [a.b.c]
            value = 1
            """

        #expect(throws: TOMLDecodingError.self) {
            try decoder.decode([String: [String: [String: [String: Int]]]].self, from: toml)
        }
    }

    @Test func decodingLimitsMaxDepthAllowed() throws {
        let decoder = TOMLDecoder()
        decoder.limits.maxDepth = 5
        // Depth: root (0) -> a (1) -> b (2) -> c (3) -> value (4) - within limit of 5
        let toml = """
            [a.b.c]
            value = 1
            """

        let result = try decoder.decode([String: [String: [String: [String: Int]]]].self, from: toml)
        #expect(result["a"]?["b"]?["c"]?["value"] == 1)
    }

    @Test func decodingLimitsMaxTableKeys() throws {
        let decoder = TOMLDecoder()
        decoder.limits.maxTableKeys = 3
        let toml = """
            a = 1
            b = 2
            c = 3
            d = 4
            """

        #expect(throws: TOMLDecodingError.self) {
            try decoder.decode([String: Int].self, from: toml)
        }
    }

    @Test func decodingLimitsMaxTableKeysAllowed() throws {
        let decoder = TOMLDecoder()
        decoder.limits.maxTableKeys = 3
        let toml = """
            a = 1
            b = 2
            c = 3
            """

        let result = try decoder.decode([String: Int].self, from: toml)
        #expect(result.count == 3)
    }

    @Test func decodingLimitsMaxArrayLength() throws {
        let decoder = TOMLDecoder()
        decoder.limits.maxArrayLength = 3
        let toml = """
            items = [1, 2, 3, 4]
            """

        struct Config: Codable {
            let items: [Int]
        }

        #expect(throws: TOMLDecodingError.self) {
            try decoder.decode(Config.self, from: toml)
        }
    }

    @Test func decodingLimitsMaxArrayLengthAllowed() throws {
        let decoder = TOMLDecoder()
        decoder.limits.maxArrayLength = 3
        let toml = """
            items = [1, 2, 3]
            """

        struct Config: Codable {
            let items: [Int]
        }

        let result = try decoder.decode(Config.self, from: toml)
        #expect(result.items == [1, 2, 3])
    }

    @Test func decodingLimitsMaxStringLength() throws {
        let decoder = TOMLDecoder()
        decoder.limits.maxStringLength = 10
        let toml = """
            name = "this string is too long"
            """

        #expect(throws: TOMLDecodingError.self) {
            try decoder.decode([String: String].self, from: toml)
        }
    }

    @Test func decodingLimitsMaxStringLengthAllowed() throws {
        let decoder = TOMLDecoder()
        decoder.limits.maxStringLength = 10
        let toml = """
            name = "short"
            """

        let result = try decoder.decode([String: String].self, from: toml)
        #expect(result["name"] == "short")
    }

    // MARK: - Error Cases

    @Test func decodeInvalidSyntax() throws {
        let toml = """
            name = "unclosed string
            """

        let decoder = TOMLDecoder()

        #expect(throws: TOMLDecodingError.self) {
            try decoder.decode([String: String].self, from: toml)
        }
    }

    @Test func decodeTypeMismatch() throws {
        let toml = """
            name = 123
            """

        struct Config: Codable {
            let name: String
        }

        let decoder = TOMLDecoder()

        #expect(throws: DecodingError.self) {
            try decoder.decode(Config.self, from: toml)
        }
    }

    @Test func decodeKeyNotFound() throws {
        let toml = """
            other = "value"
            """

        struct Config: Codable {
            let name: String
        }

        let decoder = TOMLDecoder()

        #expect(throws: DecodingError.self) {
            try decoder.decode(Config.self, from: toml)
        }
    }

    @Test func decodeInvalidUTF8Data() throws {
        let invalidData = Data([0xFF, 0xFE])

        struct Config: Codable {
            let name: String
        }

        let decoder = TOMLDecoder()

        #expect(throws: TOMLDecodingError.self) {
            try decoder.decode(Config.self, from: invalidData)
        }
    }

    @Test func decodeExpectTableButFoundOther() throws {
        let toml = """
            config = "not a table"
            """

        struct Config: Codable {
            struct Inner: Codable {
                let value: String
            }
            let config: Inner
        }

        let decoder = TOMLDecoder()

        #expect(throws: DecodingError.self) {
            try decoder.decode(Config.self, from: toml)
        }
    }

    @Test func decodeExpectArrayButFoundOther() throws {
        let toml = """
            items = "not an array"
            """

        struct Config: Codable {
            let items: [String]
        }

        let decoder = TOMLDecoder()

        #expect(throws: DecodingError.self) {
            try decoder.decode(Config.self, from: toml)
        }
    }

    // MARK: - Error Descriptions

    @Test func errorDescriptionInvalidSyntax() {
        let error = TOMLDecodingError.invalidSyntax(line: 5, column: 10, message: "test error")
        #expect(error.description.contains("line 5"))
        #expect(error.description.contains("column 10"))
    }

    @Test func errorDescriptionTypeMismatch() {
        let error = TOMLDecodingError.typeMismatch(expected: "String", found: "Integer", codingPath: [])
        #expect(error.description.contains("String"))
        #expect(error.description.contains("Integer"))
    }

    @Test func errorDescriptionKeyNotFound() {
        struct TestKey: CodingKey {
            var stringValue: String
            var intValue: Int?
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }
        let error = TOMLDecodingError.keyNotFound(key: TestKey(stringValue: "missing")!, availableKeys: ["a", "b"])
        #expect(error.description.contains("missing"))
    }

    @Test func errorDescriptionValueNotFound() {
        let error = TOMLDecodingError.valueNotFound(type: "String", codingPath: [])
        #expect(error.description.contains("String"))
    }

    @Test func errorDescriptionDataCorrupted() {
        let error = TOMLDecodingError.dataCorrupted(message: "corrupted", codingPath: [])
        #expect(error.description.contains("corrupted"))
    }

    @Test func errorDescriptionInvalidData() {
        let error = TOMLDecodingError.invalidData("bad data")
        #expect(error.description.contains("bad data"))
    }

    // MARK: - Inline Tables

    @Test func decodeInlineTable() throws {
        let toml = """
            point = { x = 1, y = 2 }
            """

        struct Config: Codable {
            struct Point: Codable {
                let x: Int
                let y: Int
            }
            let point: Point
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.point.x == 1)
        #expect(config.point.y == 2)
    }

    // MARK: - String Types

    @Test func decodeBasicString() throws {
        let toml = """
            name = "hello world"
            """

        let decoder = TOMLDecoder()
        let config = try decoder.decode([String: String].self, from: toml)

        #expect(config["name"] == "hello world")
    }

    @Test func decodeLiteralString() throws {
        let toml = """
            path = 'C:\\Users\\name'
            """

        let decoder = TOMLDecoder()
        let config = try decoder.decode([String: String].self, from: toml)

        #expect(config["path"] == "C:\\Users\\name")
    }

    @Test func decodeMultilineBasicString() throws {
        let toml = """
            text = \"\"\"
            line1
            line2\"\"\"
            """

        let decoder = TOMLDecoder()
        let config = try decoder.decode([String: String].self, from: toml)

        #expect(config["text"]?.contains("line1") == true)
        #expect(config["text"]?.contains("line2") == true)
    }

    // MARK: - Dotted Keys

    @Test func decodeDottedKeys() throws {
        let toml = """
            fruit.apple.color = "red"
            fruit.apple.taste = "sweet"
            """

        struct Config: Codable {
            struct Fruit: Codable {
                struct Apple: Codable {
                    let color: String
                    let taste: String
                }
                let apple: Apple
            }
            let fruit: Fruit
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.fruit.apple.color == "red")
        #expect(config.fruit.apple.taste == "sweet")
    }

    // MARK: - Boolean Values

    @Test func decodeBooleanValues() throws {
        let toml = """
            yes = true
            no = false
            """

        struct Config: Codable {
            let yes: Bool
            let no: Bool
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.yes == true)
        #expect(config.no == false)
    }

    // MARK: - Array Decoding Edge Cases

    @Test func decodeArrayOfDates() throws {
        let toml = """
            dates = [2024-01-01, 2024-06-15, 2024-12-31]
            """

        struct Config: Codable {
            let dates: [LocalDate]
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.dates.count == 3)
        #expect(config.dates[0].year == 2024)
        #expect(config.dates[1].month == 6)
        #expect(config.dates[2].day == 31)
    }

    @Test func decodeArrayOfLocalTimes() throws {
        let toml = """
            times = [08:00:00, 12:30:00, 18:45:30]
            """

        struct Config: Codable {
            let times: [LocalTime]
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.times.count == 3)
        #expect(config.times[0].hour == 8)
        #expect(config.times[1].minute == 30)
        #expect(config.times[2].second == 30)
    }

    @Test func decodeArrayOfBooleans() throws {
        let toml = """
            flags = [true, false, true, false]
            """

        struct Config: Codable {
            let flags: [Bool]
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.flags == [true, false, true, false])
    }

    @Test func decodeArrayOfFloats() throws {
        let toml = """
            values = [1.1, 2.2, 3.3]
            """

        struct Config: Codable {
            let values: [Float]
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.values.count == 3)
    }

    // MARK: - Unkeyed Container

    @Test func decodeTopLevelArray() throws {
        let toml = """
            [[items]]
            name = "first"

            [[items]]
            name = "second"
            """

        struct Item: Codable {
            let name: String
        }

        struct Config: Codable {
            let items: [Item]
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.items.count == 2)
    }

    // MARK: - Nested Container Decoding

    @Test func decodeNestedKeyedContainers() throws {
        let toml = """
            [a.b.c]
            value = 42
            """

        struct Config: Codable {
            struct A: Codable {
                struct B: Codable {
                    struct C: Codable {
                        let value: Int
                    }
                    let c: C
                }
                let b: B
            }
            let a: A
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.a.b.c.value == 42)
    }

    @Test func decodeNestedUnkeyedContainers() throws {
        let toml = """
            matrix = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]
            """

        struct Config: Codable {
            let matrix: [[Int]]
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.matrix[0] == [1, 2, 3])
        #expect(config.matrix[1] == [4, 5, 6])
        #expect(config.matrix[2] == [7, 8, 9])
    }

    // MARK: - Keyed Container Date Decoding

    @Test func keyedContainerDecodeDateFromOffsetDateTime() throws {
        let toml = """
            timestamp = 1979-05-27T07:32:00Z
            """

        struct Config: Codable {
            let timestamp: Date
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.timestamp.timeIntervalSince1970 > 0)
    }

    @Test func keyedContainerDecodeDateFromLocalDateTime() throws {
        let toml = """
            timestamp = 2024-06-15T10:30:00
            """

        struct Config: Codable {
            let timestamp: Date
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        let components = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour],
            from: config.timestamp
        )
        #expect(components.year == 2024)
        #expect(components.month == 6)
        #expect(components.day == 15)
        #expect(components.hour == 10)
    }

    @Test func keyedContainerDecodeDateFromLocalDate() throws {
        let toml = """
            date = 2024-06-15
            """

        struct Config: Codable {
            let date: Date
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: config.date)
        #expect(components.year == 2024)
        #expect(components.month == 6)
        #expect(components.day == 15)
    }

    @Test func keyedContainerDecodeDateFromFloatSecondsSince1970() throws {
        let toml = """
            timestamp = 1000.0
            """

        struct Config: Codable {
            let timestamp: Date
        }

        let decoder = TOMLDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.timestamp.timeIntervalSince1970 == 1000)
    }

    @Test func keyedContainerDecodeDateFromFloatMillisecondsSince1970() throws {
        let toml = """
            timestamp = 5000.0
            """

        struct Config: Codable {
            let timestamp: Date
        }

        let decoder = TOMLDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.timestamp.timeIntervalSince1970 == 5)
    }

    @Test func keyedContainerDecodeDateTypeMismatch() throws {
        let toml = """
            timestamp = "not a date"
            """

        struct Config: Codable {
            let timestamp: Date
        }

        let decoder = TOMLDecoder()

        #expect(throws: DecodingError.self) {
            try decoder.decode(Config.self, from: toml)
        }
    }

    // MARK: - Unkeyed Container Date Decoding

    @Test func unkeyedContainerDecodeDateFromOffsetDateTime() throws {
        let toml = """
            dates = [1979-05-27T07:32:00Z, 2024-01-01T00:00:00Z]
            """

        struct Config: Codable {
            let dates: [Date]
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.dates.count == 2)
        #expect(config.dates[0].timeIntervalSince1970 > 0)
    }

    @Test func unkeyedContainerDecodeDateFromLocalDateTime() throws {
        let toml = """
            dates = [2024-06-15T10:30:00, 2024-12-25T08:00:00]
            """

        struct Config: Codable {
            let dates: [Date]
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.dates.count == 2)
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: config.dates[0])
        #expect(components.year == 2024)
        #expect(components.month == 6)
    }

    @Test func unkeyedContainerDecodeDateFromLocalDate() throws {
        let toml = """
            dates = [2024-06-15, 2024-12-25]
            """

        struct Config: Codable {
            let dates: [Date]
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.dates.count == 2)
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: config.dates[1])
        #expect(components.year == 2024)
        #expect(components.month == 12)
        #expect(components.day == 25)
    }

    // MARK: - Single Value Container Date Decoding

    @Test func singleValueContainerDecodeDateFromOffsetDateTime() throws {
        let toml = """
            [[events]]
            when = 1979-05-27T07:32:00Z
            """

        struct Event: Codable {
            let when: Date
        }

        struct Config: Codable {
            let events: [Event]
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.events[0].when.timeIntervalSince1970 > 0)
    }

    @Test func singleValueContainerDecodeDateFromLocalDateTime() throws {
        let toml = """
            [[events]]
            when = 2024-06-15T10:30:00
            """

        struct Event: Codable {
            let when: Date
        }

        struct Config: Codable {
            let events: [Event]
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        let components = Calendar(identifier: .gregorian).dateComponents([.year, .hour], from: config.events[0].when)
        #expect(components.year == 2024)
        #expect(components.hour == 10)
    }

    @Test func singleValueContainerDecodeDateFromLocalDate() throws {
        let toml = """
            [[events]]
            when = 2024-06-15
            """

        struct Event: Codable {
            let when: Date
        }

        struct Config: Codable {
            let events: [Event]
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        let components = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day],
            from: config.events[0].when
        )
        #expect(components.year == 2024)
        #expect(components.month == 6)
        #expect(components.day == 15)
    }
}
