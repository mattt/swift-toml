import Foundation
import TOML

@main
struct TOMLDecoderCLI {
    static func main() {
        do {
            // Pass the raw bytes to the decoder, as a library user would,
            // so that the test covers the decoder's UTF-8 handling.
            let input = FileHandle.standardInput.readDataToEndOfFile()
            let decoder = TOMLDecoder()
            let value = try decoder.decode(TOMLValue.self, from: input)
            let json = value.toJSON()
            print(json)
        } catch {
            FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
            exit(1)
        }
    }
}

extension TOMLValue {
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
