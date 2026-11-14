import Foundation
import Testing

import TOML

@Suite("TOML Input Encoding Tests")
struct TOMLInputEncodingTests {

    /// Invalid documents from the toml-test suite (`invalid/encoding`),
    /// as hexadecimal bytes.
    static let invalidDocuments: [(name: String, hex: String)] = [
        (
            "bad-codepoint",
            "2320496e76616c696420636f6465706f696e7420552b44383030203a20eda0800a"
        ),
        (
            "bad-utf8-at-end",
            "2320546865726520697320612030786461206174206166746572207468652071756f7465732c20616e64206e6f20454f4c2061"
                + "742074686520656e64206f66207468652066696c652e0a230a232054686973206973206120626974206f6620616e2065646765"
                + "20636173653a205468697320696e646963617465732074686572652073686f756c642062652074776f2062797465730a232028"
                + "3062313130315f313031302920627574207468657265206973206e6f206279746520746f20666f6c6c6f77206265636175736520"
                + "697427732074686520656e64206f66207468652066696c652e0a78203d20222222222222da"
        ),
        (
            "bad-utf8-in-array",
            "232068747470733a2f2f6769746875622e636f6d2f6d61727a65722f746f6d6c706c7573706c75732f6973737565732f3130300a"
                + "666c203d5b205b5b5b5b5b5b5b5b5b5b5b5b5b5b5b3680860000002d36c29f2000"
        ),
        (
            "bad-utf8-in-comment",
            "2320c30a"
        ),
        (
            "bad-utf8-in-multiline",
            "232054686520666f6c6c6f77696e67206c696e6520636f6e7461696e7320616e20696e76616c6964205554462d382073657175656e"
                + "63652e0a626164203d20222222c32222220a"
        ),
        (
            "bad-utf8-in-multiline-literal",
            "232054686520666f6c6c6f77696e67206c696e6520636f6e7461696e7320616e20696e76616c6964205554462d382073657175656e"
                + "63652e0a626164203d20272727c32727270a"
        ),
        (
            "bad-utf8-in-string",
            "232054686520666f6c6c6f77696e67206c696e6520636f6e7461696e7320616e20696e76616c6964205554462d382073657175656e"
                + "63652e0a626164203d2022c3220a"
        ),
        (
            "bad-utf8-in-string-literal",
            "232054686520666f6c6c6f77696e67206c696e6520636f6e7461696e7320616e20696e76616c6964205554462d382073657175656e"
                + "63652e0a626164203d2027c3270a"
        ),
        (
            "bom-not-at-start-01",
            "2320436f6e7461696e73205554462d3820424f4d206265747765656e203d20616e6420310a613defbbbf310a"
        ),
        (
            "bom-not-at-start-02",
            "efbbbfefbbbf2320436f6e7461696e732074776f205554462d3820424f4d53206174207468652073746172740a613d310a"
        ),
        (
            "bom-not-at-start-03",
            "efbbbfefbbbf613d310a2320436f6e7461696e732074776f205554462d3820424f4d53206174207468652073746172740a"
        ),
        (
            "utf16-bom",
            "feff00230020005500540046002d003100360020007700690074006800200042004f004d000a"
        ),
    ]

    @Test(arguments: invalidDocuments.map(\.name))
    func rejectsInvalidEncodingFromData(_ name: String) throws {
        let hex = try #require(Self.invalidDocuments.first { $0.name == name }?.hex)
        let data = try #require(Data(hexString: hex))

        #expect(throws: TOMLDecodingError.self) {
            try TOMLDecoder().decode([String: Int].self, from: data)
        }
    }

    @Test func rejectsTwoByteOrderMarksFromString() {
        let toml = "\u{FEFF}\u{FEFF}a = 1\n"

        #expect(throws: TOMLDecodingError.self) {
            try TOMLDecoder().decode([String: Int].self, from: toml)
        }
    }

    @Test func acceptsOneByteOrderMarkFromData() throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("a = 1\n".utf8)
        let value = try TOMLDecoder().decode([String: Int].self, from: data)
        #expect(value == ["a": 1])
    }

    @Test func acceptsOneByteOrderMarkFromString() throws {
        let value = try TOMLDecoder().decode([String: Int].self, from: "\u{FEFF}a = 1\n")
        #expect(value == ["a": 1])
    }

    @Test func acceptsByteOrderMarkCharacterInString() throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("a = \"\u{FEFF}x\"\n".utf8)
        let value = try TOMLDecoder().decode([String: String].self, from: data)
        #expect(value == ["a": "\u{FEFF}x"])
    }

    @Test func acceptsNonASCIIFromData() throws {
        let data = Data("a = \"caf\u{E9} \u{1F600}\"\n".utf8)
        let value = try TOMLDecoder().decode([String: String].self, from: data)
        #expect(value == ["a": "caf\u{E9} \u{1F600}"])
    }

    @Test func rejectsDataOverMaxInputSize() {
        let decoder = TOMLDecoder()
        decoder.limits.maxInputSize = 4
        let data = Data("a = 12345\n".utf8)

        #expect(throws: TOMLDecodingError.self) {
            try decoder.decode([String: Int].self, from: data)
        }
    }
}

extension Data {
    fileprivate init?(hexString: String) {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hexString.utf8.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2, limitedBy: hexString.endIndex) ?? hexString.endIndex
            guard let byte = UInt8(hexString[index ..< next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
