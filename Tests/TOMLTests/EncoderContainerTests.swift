import Foundation
import Testing

import TOML

/// Tests that nested containers, super encoders,
/// and repeated container requests write their values
/// to the same places that `JSONEncoder` writes them.
@Suite("Encoder Container Tests")
struct EncoderContainerTests {

    // MARK: - Nested Containers

    /// Writes `x = 1`, then `x = 2` in a nested keyed container under `outer`,
    /// then `3` in a nested unkeyed container under `list`.
    struct NestedContainers: Codable, Equatable {
        enum CodingKeys: String, CodingKey {
            case x, outer, list
        }

        init() {}

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let outer = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .outer)
            var list = try container.nestedUnkeyedContainer(forKey: .list)
            guard
                try container.decode(Int.self, forKey: .x) == 1,
                try outer.decode(Int.self, forKey: .x) == 2,
                try list.decode(Int.self) == 3,
                list.isAtEnd
            else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unexpected values"))
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(1, forKey: .x)
            var outer = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .outer)
            try outer.encode(2, forKey: .x)
            var list = container.nestedUnkeyedContainer(forKey: .list)
            try list.encode(3)
        }
    }

    @Test func nestedKeyedAndUnkeyedContainers() throws {
        let tree = try expectSameStructure(NestedContainers())
        #expect(
            tree
                == .table([
                    "x": .integer(1),
                    "outer": .table(["x": .integer(2)]),
                    "list": .array([.integer(3)]),
                ])
        )
    }

    @Test func nestedContainersRoundTrip() throws {
        let data = try TOMLEncoder().encode(NestedContainers())
        #expect(try TOMLDecoder().decode(NestedContainers.self, from: data) == NestedContainers())
    }

    /// Writes keyed containers two levels deep,
    /// and keyed containers in a nested unkeyed container.
    struct DeepContainers: Codable, Equatable {
        enum CodingKeys: String, CodingKey {
            case name, outer, inner, rows, id
        }

        init() {}

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let outer = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .outer)
            let inner = try outer.nestedContainer(keyedBy: CodingKeys.self, forKey: .inner)
            var rows = try container.nestedUnkeyedContainer(forKey: .rows)
            let first = try rows.nestedContainer(keyedBy: CodingKeys.self)
            let second = try rows.nestedContainer(keyedBy: CodingKeys.self)
            guard
                try outer.decode(String.self, forKey: .name) == "outer",
                try inner.decode(String.self, forKey: .name) == "inner",
                try first.decode(Int.self, forKey: .id) == 1,
                try second.decode(Int.self, forKey: .id) == 2,
                rows.isAtEnd
            else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unexpected values"))
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            var outer = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .outer)
            try outer.encode("outer", forKey: .name)
            var inner = outer.nestedContainer(keyedBy: CodingKeys.self, forKey: .inner)
            try inner.encode("inner", forKey: .name)
            var rows = container.nestedUnkeyedContainer(forKey: .rows)
            for id in 1 ... 2 {
                var row = rows.nestedContainer(keyedBy: CodingKeys.self)
                try row.encode(id, forKey: .id)
            }
        }
    }

    @Test func containersTwoLevelsDeep() throws {
        let tree = try expectSameStructure(DeepContainers())
        #expect(
            tree
                == .table([
                    "outer": .table([
                        "name": .string("outer"),
                        "inner": .table(["name": .string("inner")]),
                    ]),
                    "rows": .array([.table(["id": .integer(1)]), .table(["id": .integer(2)])]),
                ])
        )
    }

    @Test func deepContainersRoundTrip() throws {
        let data = try TOMLEncoder().encode(DeepContainers())
        #expect(try TOMLDecoder().decode(DeepContainers.self, from: data) == DeepContainers())
    }

    // MARK: - Repeated Containers

    /// Asks one encoder for a keyed container twice.
    struct TwoKeyedContainers: Encodable {
        enum CodingKeys: String, CodingKey {
            case a, b
        }

        func encode(to encoder: any Encoder) throws {
            var first = encoder.container(keyedBy: CodingKeys.self)
            try first.encode(1, forKey: .a)
            var second = encoder.container(keyedBy: CodingKeys.self)
            try second.encode(2, forKey: .b)
        }
    }

    /// Asks one encoder for an unkeyed container twice.
    struct TwoUnkeyedContainers: Encodable {
        func encode(to encoder: any Encoder) throws {
            var first = encoder.unkeyedContainer()
            try first.encode(1)
            var second = encoder.unkeyedContainer()
            try second.encode(2)
        }
    }

    struct Wrapper<Value: Encodable>: Encodable {
        let value: Value
    }

    @Test func secondContainerKeepsFirstContainersValues() throws {
        #expect(
            try expectSameStructure(TwoKeyedContainers()) == .table(["a": .integer(1), "b": .integer(2)])
        )
        #expect(
            try expectSameStructure(Wrapper(value: TwoUnkeyedContainers()))
                == .table(["value": .array([.integer(1), .integer(2)])])
        )
    }

    /// Writes one key twice, and writes a table or an array at a key
    /// before it asks for a nested container there.
    ///
    /// The array value comes from an unkeyed container,
    /// because `JSONEncoder` writes some arrays, such as `[Int]`, in a way
    /// that it can't reopen as a nested container.
    struct RepeatedKeys: Encodable {
        enum CodingKeys: String, CodingKey {
            case x, outer, list
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(1, forKey: .x)
            try container.encode(2, forKey: .x)
            try container.encode(["x": 3], forKey: .outer)
            var outer = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .outer)
            try outer.encode(4, forKey: .list)
            var again = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .outer)
            try again.encode(5, forKey: .x)
            try container.encode(TwoUnkeyedContainers(), forKey: .list)
            var list = container.nestedUnkeyedContainer(forKey: .list)
            try list.encode(3)
        }
    }

    @Test func repeatedKeysMatchJSONEncoder() throws {
        let tree = try expectSameStructure(RepeatedKeys())
        #expect(
            tree
                == .table([
                    "x": .integer(2),
                    "outer": .table(["x": .integer(5), "list": .integer(4)]),
                    "list": .array([.integer(1), .integer(2), .integer(3)]),
                ])
        )
    }

    /// Asks one encoder for a keyed container and then an unkeyed container,
    /// which `JSONEncoder` doesn't allow.
    struct KeyedThenUnkeyed: Encodable {
        enum CodingKeys: String, CodingKey {
            case a
        }

        func encode(to encoder: any Encoder) throws {
            var keyed = encoder.container(keyedBy: CodingKeys.self)
            try keyed.encode(1, forKey: .a)
            var unkeyed = encoder.unkeyedContainer()
            try unkeyed.encode(2)
        }
    }

    /// Writes a value at a key,
    /// then asks for a nested keyed container at that key,
    /// which `JSONEncoder` doesn't allow.
    struct ValueThenNestedContainer: Encodable {
        enum CodingKeys: String, CodingKey {
            case a
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(1, forKey: .a)
            var nested = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .a)
            try nested.encode(2, forKey: .a)
        }
    }

    /// Encodes a value that asks for conflicting containers
    /// with its parent's super encoder.
    struct SuperEncoderConflict: Encodable {
        enum CodingKeys: String, CodingKey {
            case b
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(1, forKey: .b)
            try KeyedThenUnkeyed().encode(to: container.superEncoder())
        }
    }

    @Test func conflictingContainersThrow() {
        // In a wrapper, the array that the unkeyed container used to leave
        // is a valid document, so only the conflict makes this throw.
        expectInvalidValue(codingPath: []) {
            try TOMLEncoder().encode(Wrapper(value: KeyedThenUnkeyed()))
        }
        expectInvalidValue(codingPath: []) {
            try TOMLEncoder().encode(Wrapper(value: Wrapper(value: KeyedThenUnkeyed())))
        }
        expectInvalidValue(codingPath: ["a"]) {
            try TOMLEncoder().encode(ValueThenNestedContainer())
        }
        expectInvalidValue(codingPath: ["super"]) {
            try TOMLEncoder().encode(SuperEncoderConflict())
        }
    }

    /// Catches the error from a value that asks for conflicting containers,
    /// and writes other values in its place.
    struct FallbackAfterError: Encodable {
        enum CodingKeys: String, CodingKey {
            case bad, good, later
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            do {
                try container.encode(KeyedThenUnkeyed(), forKey: .bad)
            } catch {
                try container.encode(3, forKey: .good)
                try container.encode(Wrapper(value: 4), forKey: .later)
            }
        }
    }

    @Test func caughtContainerErrorPermitsFallback() throws {
        let toml = try TOMLEncoder().encode(FallbackAfterError())
        #expect(
            try TOMLDecoder().decode(EncodedTree.self, from: toml)
                == .table(["good": .integer(3), "later": .table(["value": .integer(4)])])
        )
    }

    @Test func encoderSucceedsAfterFailedEncode() throws {
        let encoder = TOMLEncoder()
        expectInvalidValue(codingPath: []) {
            try encoder.encode(Wrapper(value: KeyedThenUnkeyed()))
        }
        let toml = try encoder.encode(TwoKeyedContainers())
        #expect(try TOMLDecoder().decode(EncodedTree.self, from: toml) == .table(["a": .integer(1), "b": .integer(2)]))
    }

    private func expectInvalidValue(
        codingPath expectedPath: [String],
        sourceLocation: SourceLocation = #_sourceLocation,
        _ body: () throws -> Data
    ) {
        do {
            let data = try body()
            Issue.record(
                "Expected an encoding error, got \(String(decoding: data, as: UTF8.self))",
                sourceLocation: sourceLocation
            )
        } catch TOMLEncodingError.invalidValue(let message, let codingPath) {
            #expect(message.contains("container"), sourceLocation: sourceLocation)
            #expect(codingPath.map(\.stringValue) == expectedPath, sourceLocation: sourceLocation)
        } catch {
            Issue.record("Unexpected error: \(error)", sourceLocation: sourceLocation)
        }
    }

    // MARK: - Super Encoders and Class Hierarchies

    class Base: Codable {
        let a: Int

        enum CodingKeys: String, CodingKey {
            case a
        }

        init(a: Int) {
            self.a = a
        }
    }

    /// Encodes its superclass with the same encoder.
    class Derived: Base {
        let b: Int

        enum CodingKeys: String, CodingKey {
            case b
        }

        init(a: Int, b: Int) {
            self.b = b
            super.init(a: a)
        }

        required init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            b = try container.decode(Int.self, forKey: .b)
            try super.init(from: decoder)
        }

        override func encode(to encoder: any Encoder) throws {
            try super.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(b, forKey: .b)
        }
    }

    /// Adds a third level to ``Derived``.
    final class Leaf: Derived {
        let c: Int

        enum CodingKeys: String, CodingKey {
            case c
        }

        init(a: Int, b: Int, c: Int) {
            self.c = c
            super.init(a: a, b: b)
        }

        required init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            c = try container.decode(Int.self, forKey: .c)
            try super.init(from: decoder)
        }

        override func encode(to encoder: any Encoder) throws {
            try super.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(c, forKey: .c)
        }
    }

    /// Encodes its superclass with `superEncoder()`,
    /// after it encodes its own property,
    /// and decodes it with `superDecoder()`.
    final class SuperEncoded: Base {
        let b: Int

        enum CodingKeys: String, CodingKey {
            case b
        }

        init(a: Int, b: Int) {
            self.b = b
            super.init(a: a)
        }

        required init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            b = try container.decode(Int.self, forKey: .b)
            try super.init(from: container.superDecoder())
        }

        override func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            let superEncoder = container.superEncoder()
            try container.encode(b, forKey: .b)
            try super.encode(to: superEncoder)
        }
    }

    /// Encodes its superclass with `superEncoder(forKey:)`.
    final class SuperEncodedForKey: Base {
        let b: Int

        enum CodingKeys: String, CodingKey {
            case b, parent
        }

        init(a: Int, b: Int) {
            self.b = b
            super.init(a: a)
        }

        required init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            b = try container.decode(Int.self, forKey: .b)
            try super.init(from: container.superDecoder(forKey: .parent))
        }

        override func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(b, forKey: .b)
            try super.encode(to: container.superEncoder(forKey: .parent))
        }
    }

    @Test func subclassEncodesSuperclassWithSameEncoder() throws {
        let tree = try expectSameStructure(Derived(a: 1, b: 2))
        #expect(tree == .table(["a": .integer(1), "b": .integer(2)]))
    }

    @Test func threeLevelClassHierarchy() throws {
        let tree = try expectSameStructure(Leaf(a: 1, b: 2, c: 3))
        #expect(tree == .table(["a": .integer(1), "b": .integer(2), "c": .integer(3)]))
    }

    @Test func subclassEncodesSuperclassWithSuperEncoder() throws {
        let tree = try expectSameStructure(SuperEncoded(a: 1, b: 2))
        #expect(tree == .table(["b": .integer(2), "super": .table(["a": .integer(1)])]))
    }

    @Test func subclassDecodesSuperclassWithSuperDecoder() throws {
        let data = try TOMLEncoder().encode(SuperEncoded(a: 1, b: 2))
        let decoded = try TOMLDecoder().decode(SuperEncoded.self, from: data)
        #expect(decoded.a == 1)
        #expect(decoded.b == 2)
    }

    /// The key decoding strategy doesn't change the key `super`.
    @Test func superDecoderWithConvertFromSnakeCase() throws {
        let decoder = TOMLDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(SuperEncoded.self, from: "b = 2\n\n[super]\na = 1\n")
        #expect(decoded.a == 1)
        #expect(decoded.b == 2)
    }

    /// Like `JSONDecoder`, the keyed `superDecoder()` doesn't throw for a missing `super` key,
    /// but the decoder it returns has no keyed container.
    @Test func superDecoderForMissingKeyMatchesJSONDecoder() throws {
        let tomlError = decodingErrorDescription {
            _ = try TOMLDecoder().decode(SuperEncoded.self, from: "b = 2")
        }
        let jsonError = decodingErrorDescription {
            _ = try JSONDecoder().decode(SuperEncoded.self, from: Data(#"{"b": 2}"#.utf8))
        }
        #expect(tomlError == "valueNotFound at super")
        #expect(tomlError == jsonError)
    }

    /// Reads an optional integer from the single-value container of `superDecoder()`.
    struct OptionalSuperValue: Decodable {
        let isNil: Bool
        let value: Int?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let superContainer = try container.superDecoder().singleValueContainer()
            isNil = superContainer.decodeNil()
            value = try superContainer.decode(Int?.self)
        }

        enum CodingKeys: CodingKey {}
    }

    @Test func superDecoderSingleValueContainerMatchesJSONDecoder() throws {
        let tomlMissing = try TOMLDecoder().decode(OptionalSuperValue.self, from: "")
        let jsonMissing = try JSONDecoder().decode(OptionalSuperValue.self, from: Data("{}".utf8))
        #expect(tomlMissing.isNil && jsonMissing.isNil)
        #expect(tomlMissing.value == nil && jsonMissing.value == nil)

        let tomlPresent = try TOMLDecoder().decode(OptionalSuperValue.self, from: "super = 3")
        let jsonPresent = try JSONDecoder().decode(OptionalSuperValue.self, from: Data(#"{"super": 3}"#.utf8))
        #expect(!tomlPresent.isNil && !jsonPresent.isNil)
        #expect(tomlPresent.value == 3 && jsonPresent.value == 3)
    }

    /// Decodes a value of the type that `userInfo` names
    /// from the single-value container of `superDecoder()`.
    struct MissingSuperValue: Decodable {
        static let typeName = CodingUserInfoKey(rawValue: "typeName")!

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let value = try container.superDecoder().singleValueContainer()
            switch decoder.userInfo[Self.typeName] as? String {
            case "Int": _ = try value.decode(Int.self)
            case "Int8": _ = try value.decode(Int8.self)
            case "Int16": _ = try value.decode(Int16.self)
            case "Int32": _ = try value.decode(Int32.self)
            case "Int64": _ = try value.decode(Int64.self)
            case "UInt": _ = try value.decode(UInt.self)
            case "UInt8": _ = try value.decode(UInt8.self)
            case "UInt16": _ = try value.decode(UInt16.self)
            case "UInt32": _ = try value.decode(UInt32.self)
            case "UInt64": _ = try value.decode(UInt64.self)
            case "Float": _ = try value.decode(Float.self)
            case "Double": _ = try value.decode(Double.self)
            case "Bool": _ = try value.decode(Bool.self)
            default: _ = try value.decode(String.self)
            }
        }

        enum CodingKeys: CodingKey {}
    }

    /// Returns the type and coding path of the `DecodingError.valueNotFound` that `body` throws.
    private func valueNotFound(_ body: () throws -> Void) -> String {
        do {
            try body()
            return "no error"
        } catch DecodingError.valueNotFound(let type, let context) {
            return "\(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        } catch {
            return "\(error)"
        }
    }

    /// For a missing `super` key, the error names the requested type, as `JSONDecoder`'s does.
    @Test(
        arguments: [
            "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "Float",
            "Double", "Bool", "String",
        ]
    )
    func superDecoderMissingValueNamesRequestedType(typeName: String) {
        let tomlDecoder = TOMLDecoder()
        tomlDecoder.userInfo[MissingSuperValue.typeName] = typeName
        let jsonDecoder = JSONDecoder()
        jsonDecoder.userInfo[MissingSuperValue.typeName] = typeName

        let tomlError = valueNotFound { _ = try tomlDecoder.decode(MissingSuperValue.self, from: "") }
        let jsonError = valueNotFound { _ = try jsonDecoder.decode(MissingSuperValue.self, from: Data("{}".utf8)) }
        #expect(tomlError == "\(typeName) at super")
        // `JSONDecoder` throws `typeMismatch` for a `Bool` that's missing.
        if typeName != "Bool" {
            #expect(tomlError == jsonError)
        }
    }

    /// A subclass that passes its own decoder to `super.init(from:)` reads the whole table.
    @Test func subclassDecodesSuperclassWithSameDecoder() throws {
        let data = try TOMLEncoder().encode(Derived(a: 1, b: 2))
        let decoded = try TOMLDecoder().decode(Derived.self, from: data)
        #expect(decoded.a == 1)
        #expect(decoded.b == 2)
    }

    @Test func subclassEncodesSuperclassWithSuperEncoderForKey() throws {
        let tree = try expectSameStructure(SuperEncodedForKey(a: 1, b: 2))
        #expect(tree == .table(["b": .integer(2), "parent": .table(["a": .integer(1)])]))
    }

    /// Writes at super encoders' keys through the parent container
    /// before and after it releases the super encoders.
    struct LateSuperEncoderWrites: Encodable {
        enum CodingKeys: String, CodingKey {
            case a, b, `super`
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            let keyedSuperEncoder = container.superEncoder(forKey: .a)
            let superEncoder = container.superEncoder()
            try container.encode(42, forKey: .a)
            try container.encode(43, forKey: .super)
            // The super encoders write when they're released, so their values win.
            try 7.encode(to: keyedSuperEncoder)
            try 8.encode(to: superEncoder)
            // This super encoder is released before the parent writes at its key,
            // so the parent's value wins.
            try 9.encode(to: container.superEncoder(forKey: .b))
            try container.encode(10, forKey: .b)
        }
    }

    @Test func superEncoderValueWinsAtItsKey() throws {
        let tree = try expectSameStructure(LateSuperEncoderWrites())
        #expect(tree == .table(["a": .integer(7), "super": .integer(8), "b": .integer(10)]))
    }

    @Test func classHierarchiesRoundTrip() throws {
        let encoder = TOMLEncoder()
        let decoder = TOMLDecoder()

        let derived = try decoder.decode(Derived.self, from: encoder.encode(Derived(a: 1, b: 2)))
        #expect((derived.a, derived.b) == (1, 2))

        let leaf = try decoder.decode(Leaf.self, from: encoder.encode(Leaf(a: 1, b: 2, c: 3)))
        #expect((leaf.a, leaf.b, leaf.c) == (1, 2, 3))

        let superEncoded = try decoder.decode(
            SuperEncodedForKey.self,
            from: encoder.encode(SuperEncodedForKey(a: 1, b: 2))
        )
        #expect((superEncoded.a, superEncoded.b) == (1, 2))
    }

    /// Writes a nested keyed container, a nested unkeyed container,
    /// and a super encoder's value in an unkeyed container.
    struct UnkeyedNesting: Encodable {
        enum CodingKeys: String, CodingKey {
            case items, x
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            var items = container.nestedUnkeyedContainer(forKey: .items)
            try items.encode(1)
            var table = items.nestedContainer(keyedBy: CodingKeys.self)
            try table.encode(2, forKey: .x)
            var list = items.nestedUnkeyedContainer()
            try list.encode(3)
            try 4.encode(to: items.superEncoder())
            // The super encoder writes at the index it had when it was created,
            // even though its value is written after the next element.
            let superEncoder = items.superEncoder()
            try items.encode(6)
            try Base(a: 5).encode(to: superEncoder)
        }
    }

    @Test func unkeyedContainerNestingAndSuperEncoder() throws {
        let tree = try expectSameStructure(UnkeyedNesting())
        #expect(
            tree
                == .table([
                    "items": .array([
                        .integer(1),
                        .table(["x": .integer(2)]),
                        .array([.integer(3)]),
                        .integer(4),
                        .table(["a": .integer(5)]),
                        .integer(6),
                    ])
                ])
        )
    }

    // MARK: - Key Encoding Strategy

    class SnakeBase: Encodable {
        let baseValue = 1
    }

    /// Writes camel-case keys in nested containers and super encoders.
    final class SnakeDerived: SnakeBase {
        enum CodingKeys: String, CodingKey {
            case outerTable, innerValue, listItems, itemName, parentInfo
        }

        override func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            var outer = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .outerTable)
            try outer.encode(2, forKey: .innerValue)
            var list = container.nestedUnkeyedContainer(forKey: .listItems)
            var item = list.nestedContainer(keyedBy: CodingKeys.self)
            try item.encode("three", forKey: .itemName)
            try super.encode(to: container.superEncoder())
            try super.encode(to: container.superEncoder(forKey: .parentInfo))
        }
    }

    @Test func snakeCaseKeysInNestedContainersAndSuperEncoders() throws {
        let tree = try expectSameStructure(SnakeDerived(), snakeCaseKeys: true)
        #expect(
            tree
                == .table([
                    "outer_table": .table(["inner_value": .integer(2)]),
                    "list_items": .array([.table(["item_name": .string("three")])]),
                    "super": .table(["base_value": .integer(1)]),
                    "parent_info": .table(["base_value": .integer(1)]),
                ])
        )
    }

    // MARK: - Synthesized Conformance

    struct Package: Codable, Equatable {
        struct Author: Codable, Equatable {
            let name: String
            let email: String
        }

        struct Dependency: Codable, Equatable {
            let name: String
            let versions: [String]
        }

        let name: String
        let author: Author
        let dependencies: [Dependency]
        let tags: [String]
        let matrix: [[Int]]
    }

    /// A synthesized `Codable` struct encodes as it did before
    /// the encoder kept nested containers.
    @Test func synthesizedStructEncodesUnchanged() throws {
        let package = Package(
            name: "toml",
            author: .init(name: "Ada", email: "ada@example.com"),
            dependencies: [
                .init(name: "parser", versions: ["1.0", "1.1"]),
                .init(name: "printer", versions: []),
            ],
            tags: ["config", "format"],
            matrix: [[1, 2], [3]]
        )

        try expectSameStructure(package)

        let encoder = TOMLEncoder()
        encoder.outputFormatting = .sortedKeys
        let toml = try encoder.encodeToString(package)
        #expect(
            toml == """
                matrix = [[1, 2], [3]]
                name = "toml"
                tags = ["config", "format"]

                [author]
                email = "ada@example.com"
                name = "Ada"

                [[dependencies]]
                name = "parser"
                versions = ["1.0", "1.1"]

                [[dependencies]]
                name = "printer"
                versions = []

                """
        )
        #expect(try TOMLDecoder().decode(Package.self, from: toml) == package)
    }
}

// MARK: - Error Comparison

/// Returns the case and coding path of the `DecodingError` that `body` throws,
/// so that tests can compare errors from `TOMLDecoder` and `JSONDecoder`.
func decodingErrorDescription(_ body: () throws -> Void) -> String {
    do {
        try body()
        return "no error"
    } catch let error as DecodingError {
        let name: String
        let context: DecodingError.Context
        switch error {
        case .typeMismatch(_, let c): (name, context) = ("typeMismatch", c)
        case .valueNotFound(_, let c): (name, context) = ("valueNotFound", c)
        case .keyNotFound(_, let c): (name, context) = ("keyNotFound", c)
        case .dataCorrupted(let c): (name, context) = ("dataCorrupted", c)
        @unknown default: return "unknown DecodingError"
        }
        return "\(name) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
    } catch {
        return "\(type(of: error))"
    }
}

// MARK: - Structure Comparison

/// A value decoded from TOML or JSON,
/// so that tests can compare the structure that each encoder writes.
///
/// The tests don't encode floating-point values,
/// because JSON can't tell `1.0` from `1`.
indirect enum EncodedTree: Decodable, Equatable, CustomStringConvertible {
    case boolean(Bool)
    case integer(Int64)
    case float(Double)
    case string(String)
    case array([EncodedTree])
    case table([String: EncodedTree])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .float(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: EncodedTree].self) {
            self = .table(value)
        } else {
            self = .array(try container.decode([EncodedTree].self))
        }
    }

    var description: String {
        switch self {
        case .boolean(let value): return "\(value)"
        case .integer(let value): return "\(value)"
        case .float(let value): return "\(value)"
        case .string(let value): return "\"\(value)\""
        case .array(let values): return "[\(values.map(\.description).joined(separator: ", "))]"
        case .table(let entries):
            let items = entries.keys.sorted().map { "\($0): \(entries[$0]!)" }
            return "{\(items.joined(separator: ", "))}"
        }
    }
}

/// Encodes a value with `TOMLEncoder` and `JSONEncoder`,
/// expects both outputs to decode to the same structure,
/// and returns the structure of the TOML output.
@discardableResult
func expectSameStructure<T: Encodable>(
    _ value: T,
    snakeCaseKeys: Bool = false,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> EncodedTree {
    let tomlEncoder = TOMLEncoder()
    let jsonEncoder = JSONEncoder()
    if snakeCaseKeys {
        tomlEncoder.keyEncodingStrategy = .convertToSnakeCase
        jsonEncoder.keyEncodingStrategy = .convertToSnakeCase
    }

    let toml = try TOMLDecoder().decode(EncodedTree.self, from: tomlEncoder.encode(value))
    let json = try JSONDecoder().decode(EncodedTree.self, from: jsonEncoder.encode(value))
    #expect(toml == json, sourceLocation: sourceLocation)
    return toml
}
