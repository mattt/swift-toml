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
