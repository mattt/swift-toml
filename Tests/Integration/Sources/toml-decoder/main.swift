import Foundation
import TOML

@main
struct TOMLDecoderCLI {
    static func main() {
        do {
            let input = FileHandle.standardInput.readDataToEndOfFile()
            guard let tomlString = String(data: input, encoding: .utf8) else {
                FileHandle.standardError.write(Data("Error: Invalid UTF-8 input\n".utf8))
                exit(1)
            }

            let decoder = TOMLDecoder()
            let value = try decoder.decode(TaggedValue.self, from: tomlString)
            let json = value.toJSON()
            print(json)
        } catch {
            FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
            exit(1)
        }
    }
}

enum TaggedValue: Decodable, Sendable {
    case string(String)
    case integer(Int64)
    case float(Double)
    case boolean(Bool)
    case offsetDateTime(Date)
    case localDateTime(LocalDateTime)
    case localDate(LocalDate)
    case localTime(LocalTime)
    case array([TaggedValue])
    case table([String: TaggedValue])

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: DynamicKey.self) {
            var table: [String: TaggedValue] = [:]
            for key in container.allKeys {
                table[key.stringValue] = try container.decode(TaggedValue.self, forKey: key)
            }
            self = .table(table)
            return
        }

        if var container = try? decoder.unkeyedContainer() {
            var array: [TaggedValue] = []
            while !container.isAtEnd {
                array.append(try container.decode(TaggedValue.self))
            }
            self = .array(array)
            return
        }

        let container = try decoder.singleValueContainer()

        if let d = try? container.decode(LocalDate.self) {
            self = .localDate(d)
            return
        }
        if let dt = try? container.decode(LocalDateTime.self) {
            self = .localDateTime(dt)
            return
        }
        if let t = try? container.decode(LocalTime.self) {
            self = .localTime(t)
            return
        }
        if let date = try? container.decode(Date.self) {
            self = .offsetDateTime(date)
            return
        }
        if let b = try? container.decode(Bool.self) {
            self = .boolean(b)
            return
        }
        if let i = try? container.decode(Int64.self) {
            self = .integer(i)
            return
        }
        if let f = try? container.decode(Double.self) {
            self = .float(f)
            return
        }
        if let s = try? container.decode(String.self) {
            self = .string(s)
            return
        }

        throw DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unable to decode value")
        )
    }

    func toJSON() -> String {
        var result = ""
        writeJSON(to: &result)
        return result
    }

    private func writeJSON(to output: inout String) {
        switch self {
        case .string(let s):
            output += #"{"type":"string","value":"\#(escapeJSON(s))"}"#

        case .integer(let i):
            output += #"{"type":"integer","value":"\#(i)"}"#

        case .float(let f):
            let valueStr: String
            if f.isNaN {
                valueStr = "nan"
            } else if f.isInfinite {
                valueStr = f > 0 ? "inf" : "-inf"
            } else {
                valueStr = formatFloat(f)
            }
            output += #"{"type":"float","value":"\#(valueStr)"}"#

        case .boolean(let b):
            output += #"{"type":"bool","value":"\#(b ? "true" : "false")"}"#

        case .offsetDateTime(let date):
            let formatted = formatOffsetDateTime(date)
            output += #"{"type":"datetime","value":"\#(formatted)"}"#

        case .localDateTime(let dt):
            let formatted = formatLocalDateTime(dt)
            output += #"{"type":"datetime-local","value":"\#(formatted)"}"#

        case .localDate(let d):
            let formatted = String(format: "%04d-%02d-%02d", d.year, d.month, d.day)
            output += #"{"type":"date-local","value":"\#(formatted)"}"#

        case .localTime(let t):
            let formatted = formatLocalTime(t)
            output += #"{"type":"time-local","value":"\#(formatted)"}"#

        case .array(let arr):
            output += "["
            for (index, element) in arr.enumerated() {
                if index > 0 { output += "," }
                element.writeJSON(to: &output)
            }
            output += "]"

        case .table(let dict):
            output += "{"
            let sortedKeys = dict.keys.sorted()
            for (index, key) in sortedKeys.enumerated() {
                if index > 0 { output += "," }
                output += #""\#(escapeJSON(key))":"#
                dict[key]!.writeJSON(to: &output)
            }
            output += "}"
        }
    }
}

struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private func escapeJSON(_ s: String) -> String {
    var result = ""
    // Iterate over Unicode scalars to preserve individual CR and LF characters
    // (Swift treats CR+LF as a single Character grapheme cluster)
    for scalar in s.unicodeScalars {
        switch scalar {
        case "\"": result += "\\\""
        case "\\": result += "\\\\"
        case "\n": result += "\\n"
        case "\r": result += "\\r"
        case "\t": result += "\\t"
        default:
            if scalar.isASCII && scalar.value < 32 {
                result += String(format: "\\u%04X", scalar.value)
            } else {
                result.append(Character(scalar))
            }
        }
    }
    return result
}

private func formatFloat(_ f: Double) -> String {
    if f == f.rounded() && Swift.abs(f) < 1e15 {
        return String(format: "%.1f", f)
    }
    return String(f)
}

private func formatOffsetDateTime(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private func formatLocalDateTime(_ dt: LocalDateTime) -> String {
    var result = String(
        format: "%04d-%02d-%02dT%02d:%02d:%02d",
        dt.year,
        dt.month,
        dt.day,
        dt.hour,
        dt.minute,
        dt.second
    )
    if dt.nanosecond > 0 {
        let ms = dt.nanosecond / 1_000_000
        result += String(format: ".%03d", ms)
    }
    return result
}

private func formatLocalTime(_ t: LocalTime) -> String {
    var result = String(format: "%02d:%02d:%02d", t.hour, t.minute, t.second)
    if t.nanosecond > 0 {
        let ms = t.nanosecond / 1_000_000
        result += String(format: ".%03d", ms)
    }
    return result
}
