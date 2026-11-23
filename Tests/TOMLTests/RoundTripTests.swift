import Foundation
import Testing

import TOML

@Suite("Round Trip Tests")
struct RoundTripTests {
    @Test func simpleObject() throws {
        struct Config: Codable, Equatable {
            let name: String
            let version: Int
            let debug: Bool
        }

        let original = Config(name: "MyApp", version: 42, debug: false)

        let encoder = TOMLEncoder()
        let encoded = try encoder.encode(original)

        let decoder = TOMLDecoder()
        let decoded = try decoder.decode(Config.self, from: encoded)

        #expect(original == decoded)
    }

    @Test(arguments: [TOMLEncoder.URLEncodingStrategy.deferredToURL, .absoluteString])
    func urls(strategy: TOMLEncoder.URLEncodingStrategy) throws {
        struct Config: Codable, Equatable {
            let homepage: URL
            let mirrors: [URL]
        }

        let original = Config(
            homepage: URL(string: "https://example.com/")!,
            mirrors: [URL(string: "https://a.example.com/")!, URL(string: "https://b.example.com/")!]
        )

        let encoder = TOMLEncoder()
        encoder.urlEncodingStrategy = strategy
        let encoded = try encoder.encode(original)

        let decoded = try TOMLDecoder().decode(Config.self, from: encoded)

        #expect(original == decoded)
    }

    @Test(arguments: [
        (TOMLEncoder.DateEncodingStrategy.secondsSince1970, TOMLDecoder.DateDecodingStrategy.secondsSince1970),
        (.millisecondsSince1970, .millisecondsSince1970),
    ])
    func numericDates(
        encoding: TOMLEncoder.DateEncodingStrategy,
        decoding: TOMLDecoder.DateDecodingStrategy
    ) throws {
        struct Config: Codable, Equatable {
            let created: Date
            let history: [Date]
        }

        let original = Config(
            created: Date(timeIntervalSince1970: 1_700_000_000),
            history: [Date(timeIntervalSince1970: 1_600_000_000.25), Date(timeIntervalSince1970: 0)]
        )

        let encoder = TOMLEncoder()
        encoder.dateEncodingStrategy = encoding
        let encoded = try encoder.encode(original)

        let decoder = TOMLDecoder()
        decoder.dateDecodingStrategy = decoding
        let decoded = try decoder.decode(Config.self, from: encoded)

        #expect(original == decoded)
    }
}
