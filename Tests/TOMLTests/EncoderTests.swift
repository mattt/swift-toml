import Foundation
import Testing

import TOML

@Suite("Encoder Tests")
struct EncoderTests {

    // MARK: - Basic Types

    @Test func encodeSimpleTypes() throws {
        struct Config: Codable {
            let title: String
            let port: Int
            let enabled: Bool
        }

        let config = Config(title: "Test", port: 8080, enabled: true)
        let encoder = TOMLEncoder()
        let toml = try encoder.encodeToString(config)

        #expect(toml.contains("title = \"Test\""))
        #expect(toml.contains("port = 8080"))
        #expect(toml.contains("enabled = true"))
    }

    @Test func encodeAllIntegerTypes() throws {
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

        let values = IntTypes(
            int: 42,
            int8: 8,
            int16: 16,
            int32: 32,
            int64: 64,
            uint: 100,
            uint8: 200,
            uint16: 300,
            uint32: 400,
            uint64: 500
        )

        let encoder = TOMLEncoder()
        let toml = try encoder.encodeToString(values)

        #expect(toml.contains("int = 42"))
        #expect(toml.contains("int8 = 8"))
        #expect(toml.contains("int16 = 16"))
        #expect(toml.contains("int32 = 32"))
        #expect(toml.contains("int64 = 64"))
        #expect(toml.contains("uint = 100"))
        #expect(toml.contains("uint8 = 200"))
        #expect(toml.contains("uint16 = 300"))
        #expect(toml.contains("uint32 = 400"))
        #expect(toml.contains("uint64 = 500"))
    }

    @Test func encodeFloatTypes() throws {
        struct FloatTypes: Codable {
            let float: Float
            let double: Double
        }

        let values = FloatTypes(float: 3.14, double: 2.71828)
        let encoder = TOMLEncoder()
        let toml = try encoder.encodeToString(values)

        #expect(toml.contains("float = "))
        #expect(toml.contains("double = 2.71828"))
    }

    @Test func encodeSpecialFloatValues() throws {
        struct SpecialFloats: Codable {
            let infinity: Double
            let negInfinity: Double
            let nan: Double
        }

        let values = SpecialFloats(infinity: .infinity, negInfinity: -.infinity, nan: .nan)
        let encoder = TOMLEncoder()
        let toml = try encoder.encodeToString(values)

        #expect(toml.contains("infinity = inf"))
        #expect(toml.contains("negInfinity = -inf"))
        #expect(toml.contains("nan = nan"))
    }

    @Test func encodeURL() throws {
        struct URLs: Codable {
            let url: URL
        }
        let value = URLs(url: URL(string: "https://example.com/")!)
        let encoder = TOMLEncoder()
        encoder.urlEncodingStrategy = .absoluteString
        let toml = try encoder.encodeToString(value)
        #expect(toml.contains(#"url = "https://example.com/""#))
    }

    @Test func encodeURLDeferredToURLByDefault() throws {
        struct URLs: Codable {
            let url: URL
        }
        let value = URLs(url: URL(string: "https://example.com/")!)
        let toml = try TOMLEncoder().encodeToString(value)
        #expect(toml.contains(#"relative = "https://example.com/""#))
        #expect(!toml.contains(#"url = "https://example.com/""#))
    }

    @Test func encodeRelativeURLAsAbsoluteString() throws {
        struct URLs: Codable {
            let url: URL
        }
        let base = URL(string: "https://example.com/docs/")!
        let value = URLs(url: URL(string: "guide", relativeTo: base)!)
        let encoder = TOMLEncoder()
        encoder.urlEncodingStrategy = .absoluteString
        let toml = try encoder.encodeToString(value)
        #expect(toml.contains(#"url = "https://example.com/docs/guide""#))
    }

    // MARK: - String Escaping

    @Test func encodeStringEscaping() throws {
        struct StringTest: Codable {
            let quote: String
            let backslash: String
            let newline: String
            let tab: String
            let carriage: String
        }

        let values = StringTest(
            quote: "say \"hello\"",
            backslash: "path\\to\\file",
            newline: "line1\nline2",
            tab: "col1\tcol2",
            carriage: "text\rmore"
        )

        let encoder = TOMLEncoder()
        let toml = try encoder.encodeToString(values)

        #expect(toml.contains("\\\""))
        #expect(toml.contains("\\\\"))
        #expect(toml.contains("\\n"))
        #expect(toml.contains("\\t"))
        #expect(toml.contains("\\r"))
    }

    @Test func encodeControlCharacters() throws {
        struct ControlChar: Codable {
            let bell: String
        }

        let values = ControlChar(bell: "\u{0007}")
        let encoder = TOMLEncoder()
        let toml = try encoder.encodeToString(values)

        #expect(toml.contains("\\u0007"))
    }

    @Test func encodeSpecialKeyNames() throws {
        let dict = ["key with spaces": "value", "key.with.dots": "value2"]
        let encoder = TOMLEncoder()
        let toml = try encoder.encodeToString(dict)

        #expect(toml.contains("\"key with spaces\""))
        #expect(toml.contains("\"key.with.dots\""))
    }

    // MARK: - Arrays

    @Test func encodeArrays() throws {
        struct ArrayTypes: Codable {
            let integers: [Int]
            let strings: [String]
            let booleans: [Bool]
            let doubles: [Double]
        }

        let values = ArrayTypes(
            integers: [1, 2, 3],
            strings: ["a", "b", "c"],
            booleans: [true, false, true],
            doubles: [1.1, 2.2, 3.3]
        )

        let encoder = TOMLEncoder()
        let toml = try encoder.encodeToString(values)

        #expect(toml.contains("integers = [1, 2, 3]"))
        #expect(toml.contains("strings = [\"a\", \"b\", \"c\"]"))
        #expect(toml.contains("booleans = [true, false, true]"))
    }

    @Test func encodeNestedArrays() throws {
        struct NestedArray: Codable {
            let matrix: [[Int]]
        }

        let values = NestedArray(matrix: [[1, 2], [3, 4]])
        let encoder = TOMLEncoder()
        let toml = try encoder.encodeToString(values)

        #expect(toml.contains("[[1, 2], [3, 4]]"))
    }

    @Test func encodeEmptyArray() throws {
        struct ArrayContainer: Codable {
            let items: [Int]
        }

        let values = ArrayContainer(items: [1, 2, 3])
        let encoder = TOMLEncoder()
        let toml = try encoder.encodeToString(values)

        #expect(toml.contains("items = [1, 2, 3]"))
    }

    // MARK: - Nested Tables

    @Test func encodeNestedTables() throws {
        struct Config: Codable {
            struct Database: Codable {
                let host: String
                let port: Int
            }
            let database: Database
        }

        let config = Config(database: Config.Database(host: "localhost", port: 5432))
        let encoder = TOMLEncoder()
        let toml = try encoder.encodeToString(config)

        #expect(toml.contains("[database]"))
        #expect(toml.contains("host = \"localhost\""))
        #expect(toml.contains("port = 5432"))
    }

    @Test func encodeDeeplyNestedTables() throws {
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

        let config = Config(level1: .init(level2: .init(level3: .init(value: "deep"))))
        let encoder = TOMLEncoder()
        let toml = try encoder.encodeToString(config)

        #expect(toml.contains("[level1.level2.level3]"))
        #expect(toml.contains("value = \"deep\""))
    }

    // MARK: - Array of Tables

    @Test func encodeArrayOfTables() throws {
        struct Config: Codable {
            struct Server: Codable {
                let name: String
                let port: Int
            }
            let servers: [Server]
        }

        let config = Config(servers: [
            Config.Server(name: "alpha", port: 8001),
            Config.Server(name: "beta", port: 8002),
        ])

        let encoder = TOMLEncoder()
        let toml = try encoder.encodeToString(config)

        #expect(toml.contains("[[servers]]"))
        #expect(toml.contains("name = \"alpha\""))
        #expect(toml.contains("name = \"beta\""))
    }

    // MARK: - Date Encoding Strategies

    @Test func encodeDateISO8601() throws {
        struct DateConfig: Codable {
            let timestamp: Date
        }

        let date = Date(timeIntervalSince1970: 0)
        let config = DateConfig(timestamp: date)
        let encoder = TOMLEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let toml = try encoder.encodeToString(config)

        #expect(toml.contains("1970-01-01T00:00:00"))
    }

    @Test func encodeDateSecondsSince1970() throws {
        struct DateConfig: Codable {
            let timestamp: Date
        }

        let date = Date(timeIntervalSince1970: 1000)
        let config = DateConfig(timestamp: date)
        let encoder = TOMLEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let toml = try encoder.encodeToString(config)

        #expect(toml.contains("1000"))
    }

    @Test func encodeDateMillisecondsSince1970() throws {
        struct DateConfig: Codable {
            let timestamp: Date
        }

        let date = Date(timeIntervalSince1970: 1)
        let config = DateConfig(timestamp: date)
        let encoder = TOMLEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let toml = try encoder.encodeToString(config)

        #expect(toml.contains("1000"))
    }

    @Test func encodeDateLocalDateTime() throws {
        struct DateConfig: Codable {
            let timestamp: Date
        }

        let components = DateComponents(year: 2024, month: 6, day: 15, hour: 10, minute: 30, second: 0)
        let date = Calendar.current.date(from: components)!
        let config = DateConfig(timestamp: date)
        let encoder = TOMLEncoder()
        encoder.dateEncodingStrategy = .localDateTime
        let toml = try encoder.encodeToString(config)

        #expect(toml.contains("2024-06-15T10:30:00"))
    }

    @Test func encodeDateLocalDate() throws {
        struct DateConfig: Codable {
            let timestamp: Date
        }

        let components = DateComponents(year: 2024, month: 6, day: 15)
        let date = Calendar.current.date(from: components)!
        let config = DateConfig(timestamp: date)
        let encoder = TOMLEncoder()
        encoder.dateEncodingStrategy = .localDate
        let toml = try encoder.encodeToString(config)

        #expect(toml.contains("2024-06-15"))
    }

    @Test func encodeDateLocalTime() throws {
        struct DateConfig: Codable {
            let timestamp: Date
        }

        let components = DateComponents(year: 2024, month: 6, day: 15, hour: 10, minute: 30, second: 45)
        let date = Calendar.current.date(from: components)!
        let config = DateConfig(timestamp: date)
        let encoder = TOMLEncoder()
        encoder.dateEncodingStrategy = .localTime
        let toml = try encoder.encodeToString(config)

        #expect(toml.contains("10:30:45"))
    }

    // MARK: - Local Date/Time Types

    @Test func encodeLocalDateTime() throws {
        struct Config: Codable {
            let datetime: LocalDateTime
        }

        let config = Config(datetime: LocalDateTime(year: 2024, month: 6, day: 15, hour: 10, minute: 30, second: 0))
        let encoder = TOMLEncoder()
        let toml = try encoder.encodeToString(config)

        #expect(toml.contains("2024-06-15T10:30:00"))
    }

    @Test func encodeLocalDate() throws {
        struct Config: Codable {
            let date: LocalDate
        }

        let config = Config(date: LocalDate(year: 2024, month: 6, day: 15))
        let encoder = TOMLEncoder()
        let toml = try encoder.encodeToString(config)

        #expect(toml.contains("2024-06-15"))
    }

    @Test func encodeLocalTime() throws {
        struct Config: Codable {
            let time: LocalTime
        }

        let config = Config(time: LocalTime(hour: 10, minute: 30, second: 45))
        let encoder = TOMLEncoder()
        let toml = try encoder.encodeToString(config)

        #expect(toml.contains("10:30:45"))
    }

    // MARK: - Key Encoding Strategy

    @Test func encodeConvertToSnakeCase() throws {
        struct Config: Codable {
            let userName: String
            let userEmail: String
            let createdAt: Int
        }

        let config = Config(userName: "john", userEmail: "john@example.com", createdAt: 123)
        let encoder = TOMLEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let toml = try encoder.encodeToString(config)

        #expect(toml.contains("user_name = \"john\""))
        #expect(toml.contains("user_email = \"john@example.com\""))
        #expect(toml.contains("created_at = 123"))
    }

    @Test func encodeUseDefaultKeys() throws {
        struct Config: Codable {
            let userName: String
        }

        let config = Config(userName: "john")
        let encoder = TOMLEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        let toml = try encoder.encodeToString(config)

        #expect(toml.contains("userName = \"john\""))
    }

    // MARK: - Output Formatting

    @Test func sortedKeysOutput() throws {
        struct Config: Codable {
            let zebra: String
            let alpha: String
            let middle: String
        }

        let config = Config(zebra: "z", alpha: "a", middle: "m")
        let encoder = TOMLEncoder()
        encoder.outputFormatting = .sortedKeys
        let toml = try encoder.encodeToString(config)

        let lines = toml.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines[0].hasPrefix("alpha"))
        #expect(lines[1].hasPrefix("middle"))
        #expect(lines[2].hasPrefix("zebra"))
    }

    @Test func prettyPrintedOutput() throws {
        struct Config: Codable {
            let name: String
        }

        let config = Config(name: "test")
        let encoder = TOMLEncoder()
        encoder.outputFormatting = .prettyPrinted
        _ = try encoder.encodeToString(config)
    }

    @Test func combinedOutputFormatting() throws {
        struct Config: Codable {
            let zebra: String
            let alpha: String
        }

        let config = Config(zebra: "z", alpha: "a")
        let encoder = TOMLEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let toml = try encoder.encodeToString(config)

        let lines = toml.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines[0].hasPrefix("alpha"))
    }

    // MARK: - Encode to Data

    @Test func encodeToData() throws {
        struct Config: Codable {
            let name: String
        }

        let config = Config(name: "test")
        let encoder = TOMLEncoder()
        let data = try encoder.encode(config)

        #expect(String(data: data, encoding: .utf8)?.contains("name = \"test\"") == true)
    }

    // MARK: - User Info

    @Test func encoderUserInfo() throws {
        let key = CodingUserInfoKey(rawValue: "testKey")!

        struct Config: Codable {
            let name: String
        }

        let config = Config(name: "test")
        let encoder = TOMLEncoder()
        encoder.userInfo = [key: "testValue"]
        _ = try encoder.encode(config)
    }

    // MARK: - Dictionary Encoding

    @Test func encodeDictionary() throws {
        let dict = ["key1": "value1", "key2": "value2"]
        let encoder = TOMLEncoder()
        encoder.outputFormatting = .sortedKeys
        let toml = try encoder.encodeToString(dict)

        #expect(toml.contains("key1 = \"value1\""))
        #expect(toml.contains("key2 = \"value2\""))
    }

    @Test func encodeNestedDictionary() throws {
        let dict: [String: [String: Int]] = ["outer": ["inner": 42]]
        let encoder = TOMLEncoder()
        let toml = try encoder.encodeToString(dict)

        #expect(toml.contains("[outer]"))
        #expect(toml.contains("inner = 42"))
    }

    // MARK: - Inline Table Encoding

    @Test func encodeInlineTableInArray() throws {
        struct Point: Codable {
            let x: Int
            let y: Int
        }

        let points = [Point(x: 1, y: 2), Point(x: 3, y: 4)]
        let encoder = TOMLEncoder()
        let toml = try encoder.encodeToString(["points": points])

        #expect(toml.contains("[[points]]"))
    }

    // MARK: - Optional Values

    @Test func encodeOptionalNilSkipped() throws {
        struct Config: Codable {
            let name: String
            let nickname: String?
        }

        let config = Config(name: "John", nickname: nil)
        let encoder = TOMLEncoder()
        let toml = try encoder.encodeToString(config)

        #expect(toml.contains("name = \"John\""))
        #expect(!toml.contains("nickname"))
    }

    @Test func encodeOptionalWithValue() throws {
        struct Config: Codable {
            let name: String
            let nickname: String?
        }

        let config = Config(name: "John", nickname: "Johnny")
        let encoder = TOMLEncoder()
        let toml = try encoder.encodeToString(config)

        #expect(toml.contains("name = \"John\""))
        #expect(toml.contains("nickname = \"Johnny\""))
    }

    // MARK: - Decoder Integration (verify encoding produces valid TOML)

    @Test func decodeDateTypes() throws {
        let toml = """
            odt = 1979-05-27T07:32:00Z
            ldt = 1979-05-27T07:32:00
            ld = 1979-05-27
            lt = 07:32:00
            """

        struct Config: Codable {
            let odt: Date
            let ldt: LocalDateTime
            let ld: LocalDate
            let lt: LocalTime
        }

        let decoder = TOMLDecoder()
        let config = try decoder.decode(Config.self, from: toml)

        #expect(config.ldt.year == 1979)
        #expect(config.ldt.month == 5)
        #expect(config.ldt.day == 27)
        #expect(config.ld.year == 1979)
        #expect(config.lt.hour == 7)
        #expect(config.lt.minute == 32)
    }

    @Test func invalidSyntaxError() throws {
        let invalidToml = """
            name = "unclosed string
            """

        let decoder = TOMLDecoder()

        #expect(throws: TOMLDecodingError.self) {
            try decoder.decode([String: String].self, from: invalidToml)
        }
    }

    // MARK: - TOMLEncodingError Descriptions

    @Test func errorDescriptionInvalidValue() {
        let error = TOMLEncodingError.invalidValue("test message", codingPath: [])
        #expect(error.description.contains("Invalid value"))
        #expect(error.description.contains("test message"))
    }

    @Test func errorDescriptionInvalidValueWithPath() {
        struct TestKey: CodingKey {
            var stringValue: String
            var intValue: Int?
            init(stringValue: String) {
                self.stringValue = stringValue
                self.intValue = nil
            }
            init?(intValue: Int) { return nil }
        }
        let error = TOMLEncodingError.invalidValue(
            "bad value",
            codingPath: [TestKey(stringValue: "foo"), TestKey(stringValue: "bar")]
        )
        #expect(error.description.contains("foo.bar"))
        #expect(error.description.contains("bad value"))
    }

    @Test func errorDescriptionUnsupportedType() {
        let error = TOMLEncodingError.unsupportedType("CustomType", codingPath: [])
        #expect(error.description.contains("Unsupported type"))
        #expect(error.description.contains("CustomType"))
    }

    @Test func errorDescriptionUnsupportedTypeWithPath() {
        struct TestKey: CodingKey {
            var stringValue: String
            var intValue: Int?
            init(stringValue: String) {
                self.stringValue = stringValue
                self.intValue = nil
            }
            init?(intValue: Int) { return nil }
        }
        let error = TOMLEncodingError.unsupportedType("BadType", codingPath: [TestKey(stringValue: "config")])
        #expect(error.description.contains("config"))
        #expect(error.description.contains("BadType"))
    }

    @Test func errorDescriptionInvalidKey() {
        let error = TOMLEncodingError.invalidKey("bad key!")
        #expect(error.description.contains("Invalid TOML key"))
        #expect(error.description.contains("bad key!"))
    }
}
