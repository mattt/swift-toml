import Foundation
import Testing

import TOML

@Suite("Integer Range Tests")
struct IntegerRangeTests {

    /// An integer value at or just past one bound of an integer type.
    struct Bound: Sendable, CustomTestStringConvertible {
        let type: String
        let value: Int64
        let fits: Bool

        var testDescription: String {
            "\(value) as \(type)"
        }
    }

    /// The bounds of each integer type and, where TOML can represent it,
    /// the value one past each bound.
    static let bounds: [Bound] =
        bounds(of: Int.self) + bounds(of: Int8.self) + bounds(of: Int16.self)
        + bounds(of: Int32.self) + bounds(of: Int64.self) + bounds(of: UInt.self)
        + bounds(of: UInt8.self) + bounds(of: UInt16.self) + bounds(of: UInt32.self)
        + bounds(of: UInt64.self)

    static func bounds<T: FixedWidthInteger>(of type: T.Type) -> [Bound] {
        let name = "\(type)"
        let lower = Int64(clamping: T.min)
        let upper = Int64(clamping: T.max)
        var bounds = [
            Bound(type: name, value: lower, fits: true),
            Bound(type: name, value: upper, fits: true),
        ]
        if lower > .min {
            bounds.append(Bound(type: name, value: lower - 1, fits: false))
        }
        if upper < .max {
            bounds.append(Bound(type: name, value: upper + 1, fits: false))
        }
        return bounds
    }

    static let typeKey = CodingUserInfoKey(rawValue: "type")!

    /// Decodes `n` with the keyed container's method for the type in `userInfo`.
    struct KeyedProbe: Decodable {
        let value: Int64

        enum CodingKeys: String, CodingKey {
            case n
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch decoder.userInfo[IntegerRangeTests.typeKey] as? String {
            case "Int": value = Int64(try container.decode(Int.self, forKey: .n))
            case "Int8": value = Int64(try container.decode(Int8.self, forKey: .n))
            case "Int16": value = Int64(try container.decode(Int16.self, forKey: .n))
            case "Int32": value = Int64(try container.decode(Int32.self, forKey: .n))
            case "Int64": value = try container.decode(Int64.self, forKey: .n)
            case "UInt": value = Int64(try container.decode(UInt.self, forKey: .n))
            case "UInt8": value = Int64(try container.decode(UInt8.self, forKey: .n))
            case "UInt16": value = Int64(try container.decode(UInt16.self, forKey: .n))
            case "UInt32": value = Int64(try container.decode(UInt32.self, forKey: .n))
            case "UInt64": value = Int64(try container.decode(UInt64.self, forKey: .n))
            default: fatalError("Unknown type")
            }
        }
    }

    /// Decodes the second element of an array
    /// with the unkeyed container's method for the type in `userInfo`.
    struct UnkeyedProbe: Decodable {
        let value: Int64

        init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            _ = try container.decode(Int64.self)
            switch decoder.userInfo[IntegerRangeTests.typeKey] as? String {
            case "Int": value = Int64(try container.decode(Int.self))
            case "Int8": value = Int64(try container.decode(Int8.self))
            case "Int16": value = Int64(try container.decode(Int16.self))
            case "Int32": value = Int64(try container.decode(Int32.self))
            case "Int64": value = try container.decode(Int64.self)
            case "UInt": value = Int64(try container.decode(UInt.self))
            case "UInt8": value = Int64(try container.decode(UInt8.self))
            case "UInt16": value = Int64(try container.decode(UInt16.self))
            case "UInt32": value = Int64(try container.decode(UInt32.self))
            case "UInt64": value = Int64(try container.decode(UInt64.self))
            default: fatalError("Unknown type")
            }
        }
    }

    /// Decodes a value with the single-value container's method for the type in `userInfo`.
    struct SingleValueProbe: Decodable {
        let value: Int64

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            switch decoder.userInfo[IntegerRangeTests.typeKey] as? String {
            case "Int": value = Int64(try container.decode(Int.self))
            case "Int8": value = Int64(try container.decode(Int8.self))
            case "Int16": value = Int64(try container.decode(Int16.self))
            case "Int32": value = Int64(try container.decode(Int32.self))
            case "Int64": value = try container.decode(Int64.self)
            case "UInt": value = Int64(try container.decode(UInt.self))
            case "UInt8": value = Int64(try container.decode(UInt8.self))
            case "UInt16": value = Int64(try container.decode(UInt16.self))
            case "UInt32": value = Int64(try container.decode(UInt32.self))
            case "UInt64": value = Int64(try container.decode(UInt64.self))
            default: fatalError("Unknown type")
            }
        }
    }

    struct Wrapper<Value: Decodable>: Decodable {
        let n: Value
    }

    /// Decodes `type` from `toml` and checks the value or the error for `bound`.
    private func check<T: Decodable>(
        _ type: T.Type,
        from toml: String,
        bound: Bound,
        codingPath: [String],
        value: (T) -> Int64
    ) {
        let decoder = TOMLDecoder()
        decoder.userInfo[Self.typeKey] = bound.type
        do {
            let decoded = try decoder.decode(type, from: toml)
            #expect(bound.fits, "Expected an error for \(bound.value) as \(bound.type)")
            #expect(value(decoded) == bound.value)
        } catch DecodingError.dataCorrupted(let context) {
            #expect(!bound.fits, "Unexpected error: \(context.debugDescription)")
            #expect(context.codingPath.map(\.stringValue) == codingPath)
            #expect(context.debugDescription.contains("\(bound.value)"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test(arguments: bounds)
    func keyedContainer(_ bound: Bound) {
        check(KeyedProbe.self, from: "n = \(bound.value)", bound: bound, codingPath: ["n"]) { $0.value }
    }

    @Test(arguments: bounds)
    func unkeyedContainer(_ bound: Bound) {
        check(
            Wrapper<UnkeyedProbe>.self,
            from: "n = [0, \(bound.value)]",
            bound: bound,
            codingPath: ["n", "Index 1"]
        ) { $0.n.value }
    }

    @Test(arguments: bounds)
    func singleValueContainer(_ bound: Bound) {
        check(Wrapper<SingleValueProbe>.self, from: "n = \(bound.value)", bound: bound, codingPath: ["n"]) {
            $0.n.value
        }
    }

    @Test func decodeOutOfRangeArrayElement() {
        do {
            _ = try TOMLDecoder().decode([String: [Int8]].self, from: "a = [1, 200]")
            Issue.record("Expected a decoding error")
        } catch DecodingError.dataCorrupted(let context) {
            #expect(context.codingPath.map(\.stringValue) == ["a", "Index 1"])
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func decodeNegativeUnsignedInteger() {
        struct Config: Decodable {
            let n: UInt
        }

        #expect(throws: DecodingError.self) {
            try TOMLDecoder().decode(Config.self, from: "n = -1")
        }
    }

    // MARK: - Encoding

    /// Encodes `n` with the single-value container,
    /// because a generic property uses the generic `encode` method.
    struct Keyed<Value: Encodable>: Encodable {
        let n: Value
    }

    struct KeyedUInt64: Encodable {
        let n: UInt64
    }

    struct KeyedUInt: Encodable {
        let n: UInt
    }

    /// Encodes each value with the unkeyed container's concrete method.
    struct Unkeyed: Encodable {
        let values: [UInt64]

        func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            for value in values {
                try container.encode(value)
            }
        }
    }

    /// Encodes each value with the unkeyed container's concrete `UInt` method.
    struct UnkeyedUInt: Encodable {
        let values: [UInt]

        func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            for value in values {
                try container.encode(value)
            }
        }
    }

    private func expectInvalidValue(
        lastPathComponent: String? = nil,
        _ body: () throws -> Void
    ) {
        do {
            try body()
            Issue.record("Expected an encoding error")
        } catch TOMLEncodingError.invalidValue(let message, let codingPath) {
            #expect(message.contains("\(Int64.max)"))
            if let lastPathComponent {
                #expect(codingPath.last?.stringValue == lastPathComponent)
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func encodeUnsignedIntegersAboveInt64Max() {
        let encoder = TOMLEncoder()
        let pastInt64 = UInt64(Int64.max) + 1

        for value in [UInt64.max, pastInt64] {
            expectInvalidValue(lastPathComponent: "n") { _ = try encoder.encodeToString(KeyedUInt64(n: value)) }
            expectInvalidValue(lastPathComponent: "Index 1") {
                _ = try encoder.encodeToString(Keyed(n: Unkeyed(values: [0, value])))
            }
            expectInvalidValue { _ = try encoder.encodeToString(Keyed(n: [value])) }
        }

        for value in [UInt.max, UInt(Int64.max) + 1] {
            expectInvalidValue(lastPathComponent: "n") { _ = try encoder.encodeToString(KeyedUInt(n: value)) }
            expectInvalidValue(lastPathComponent: "Index 0") {
                _ = try encoder.encodeToString(Keyed(n: UnkeyedUInt(values: [value])))
            }
            expectInvalidValue { _ = try encoder.encodeToString(Keyed(n: [value])) }
        }
    }

    @Test func encodeUnsignedIntegersAtInt64Max() throws {
        let encoder = TOMLEncoder()
        #expect(try encoder.encodeToString(KeyedUInt64(n: UInt64(Int64.max))) == "n = \(Int64.max)\n")
        #expect(try encoder.encodeToString(KeyedUInt(n: UInt(Int64.max))) == "n = \(Int64.max)\n")
        #expect(try encoder.encodeToString(Keyed(n: UInt64(Int64.max))) == "n = \(Int64.max)\n")
        #expect(
            try encoder.encodeToString(Keyed(n: Unkeyed(values: [UInt64(Int64.max)]))) == "n = [\(Int64.max)]\n"
        )
    }
}
