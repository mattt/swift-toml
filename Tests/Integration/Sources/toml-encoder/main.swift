import Foundation
import TOML

@main
struct TOMLEncoderCLI {
    static func main() {
        do {
            let input = FileHandle.standardInput.readDataToEndOfFile()
            guard let jsonString = String(data: input, encoding: .utf8) else {
                FileHandle.standardError.write(Data("Error: Invalid UTF-8 input\n".utf8))
                exit(1)
            }

            let value = try parseTaggedJSON(jsonString)
            let encoder = TOMLEncoder()
            encoder.outputFormatting = .sortedKeys
            let toml = try encoder.encodeToString(value)
            print(toml, terminator: "")
        } catch {
            FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
            exit(1)
        }
    }
}

func parseTaggedJSON(_ json: String) throws -> TaggedValue {
    guard let data = json.data(using: .utf8) else {
        throw EncoderError.invalidInput("Invalid UTF-8")
    }

    let parsed = try JSONSerialization.jsonObject(with: data)
    return try convertJSONToTagged(parsed)
}

func convertJSONToTagged(_ json: Any) throws -> TaggedValue {
    if let dict = json as? [String: Any] {
        if let typeStr = dict["type"] as? String,
            let valueStr = dict["value"] as? String
        {
            return try parseTaggedValue(type: typeStr, value: valueStr)
        }

        var table: [String: TaggedValue] = [:]
        for (key, value) in dict {
            table[key] = try convertJSONToTagged(value)
        }
        return .table(table)
    }

    if let array = json as? [Any] {
        let values = try array.map { try convertJSONToTagged($0) }
        return .array(values)
    }

    throw EncoderError.invalidInput("Unexpected JSON structure")
}

func parseTaggedValue(type: String, value: String) throws -> TaggedValue {
    switch type {
    case "string":
        return .string(value)

    case "integer":
        guard let i = Int64(value) else {
            throw EncoderError.invalidInput("Invalid integer: \(value)")
        }
        return .integer(i)

    case "float":
        if value == "nan" || value == "+nan" {
            return .float(Double.nan)
        } else if value == "inf" || value == "+inf" {
            return .float(Double.infinity)
        } else if value == "-inf" {
            return .float(-Double.infinity)
        }
        guard let f = Double(value) else {
            throw EncoderError.invalidInput("Invalid float: \(value)")
        }
        return .float(f)

    case "bool":
        return .boolean(value == "true")

    case "datetime":
        guard let date = parseOffsetDateTime(value) else {
            throw EncoderError.invalidInput("Invalid datetime: \(value)")
        }
        return .offsetDateTime(date)

    case "datetime-local":
        guard let dt = parseLocalDateTime(value) else {
            throw EncoderError.invalidInput("Invalid datetime-local: \(value)")
        }
        return .localDateTime(dt)

    case "date-local":
        guard let d = parseLocalDate(value) else {
            throw EncoderError.invalidInput("Invalid date-local: \(value)")
        }
        return .localDate(d)

    case "time-local":
        guard let t = parseLocalTime(value) else {
            throw EncoderError.invalidInput("Invalid time-local: \(value)")
        }
        return .localTime(t)

    default:
        throw EncoderError.invalidInput("Unknown type: \(type)")
    }
}

func parseOffsetDateTime(_ s: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: s) {
        return date
    }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: s)
}

func parseLocalDateTime(_ s: String) -> LocalDateTime? {
    let parts = s.split(separator: "T")
    guard parts.count == 2,
        let date = parseLocalDateComponents(String(parts[0])),
        let time = parseLocalTimeComponents(String(parts[1]))
    else {
        return nil
    }
    return LocalDateTime(
        year: date.year,
        month: date.month,
        day: date.day,
        hour: time.hour,
        minute: time.minute,
        second: time.second,
        nanosecond: time.nanosecond
    )
}

func parseLocalDate(_ s: String) -> LocalDate? {
    parseLocalDateComponents(s)
}

func parseLocalTime(_ s: String) -> LocalTime? {
    parseLocalTimeComponents(s)
}

private func parseLocalDateComponents(_ s: String) -> LocalDate? {
    let parts = s.split(separator: "-")
    guard parts.count == 3,
        let year = Int(parts[0]),
        let month = Int(parts[1]),
        let day = Int(parts[2])
    else {
        return nil
    }
    return LocalDate(year: year, month: month, day: day)
}

private func parseLocalTimeComponents(_ s: String) -> LocalTime? {
    var timeStr = s
    var nanosecond = 0

    if let dotIndex = s.firstIndex(of: ".") {
        let fracPart = String(s[s.index(after: dotIndex)...])
        timeStr = String(s[..<dotIndex])
        let paddedFrac = fracPart.padding(toLength: 9, withPad: "0", startingAt: 0)
        nanosecond = Int(paddedFrac.prefix(9)) ?? 0
    }

    let parts = timeStr.split(separator: ":")
    guard parts.count >= 2,
        let hour = Int(parts[0]),
        let minute = Int(parts[1])
    else {
        return nil
    }

    let second = parts.count >= 3 ? Int(parts[2]) ?? 0 : 0
    return LocalTime(hour: hour, minute: minute, second: second, nanosecond: nanosecond)
}

enum EncoderError: Error {
    case invalidInput(String)
}

enum TaggedValue: Encodable, Sendable {
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

    func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let s):
            var container = encoder.singleValueContainer()
            try container.encode(s)
        case .integer(let i):
            var container = encoder.singleValueContainer()
            try container.encode(i)
        case .float(let f):
            var container = encoder.singleValueContainer()
            try container.encode(f)
        case .boolean(let b):
            var container = encoder.singleValueContainer()
            try container.encode(b)
        case .offsetDateTime(let date):
            var container = encoder.singleValueContainer()
            try container.encode(date)
        case .localDateTime(let dt):
            var container = encoder.singleValueContainer()
            try container.encode(dt)
        case .localDate(let d):
            var container = encoder.singleValueContainer()
            try container.encode(d)
        case .localTime(let t):
            var container = encoder.singleValueContainer()
            try container.encode(t)
        case .array(let arr):
            var container = encoder.unkeyedContainer()
            for element in arr {
                try container.encode(element)
            }
        case .table(let dict):
            var container = encoder.container(keyedBy: DynamicKey.self)
            for (key, value) in dict {
                try container.encode(value, forKey: DynamicKey(stringValue: key)!)
            }
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
