# Swift TOML

A Swift implementation of [TOML](https://toml.io) (Tom's Obvious, Minimal Language),
a human-readable configuration file format. 
Built on [toml++](https://github.com/marzer/tomlplusplus)
for fast, spec-compliant parsing with full Swift Codable support.

## Features

- [x] **100% passing on [toml-test](https://github.com/toml-lang/toml-test) compliance suite**
- [x] Full [TOML v1.0.0](https://toml.io/en/v1.0.0) specification support
- [x] All data types: strings, integers, floats, booleans, arrays, tables
- [x] All date-time types: offset date-time, local date-time, local date, local time
- [x] Inline tables and arrays of tables
- [x] Dotted keys and nested tables
- [x] Configurable date encoding/decoding strategies
- [x] Key strategies for `snake_case` ↔ `camelCase` conversion
- [x] Sorted keys option for deterministic output
- [x] Configurable decoding limits for security
- [x] Detailed error reporting with line and column numbers
- [x] Special float values: `nan`, `inf`, `-inf`

## Requirements

- Swift 6.0+ / Xcode 16+
- iOS 13.0+ / macOS 10.15+ / watchOS 6.0+ / tvOS 13.0+ / visionOS 1.0+

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/mattt/swift-toml.git", from: "1.0.0")
]
```

Then add the dependency to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: ["TOML"]
)
```

## Usage

```swift
import TOML

struct Config: Codable {
    var title: String
    var port: Int
    var debug: Bool
}

// Decoding
let toml = """
title = "My App"
port = 8080
debug = true
"""

let decoder = TOMLDecoder()
let config = try decoder.decode(Config.self, from: toml)
print(config.title) // "My App"

// Encoding
let encoder = TOMLEncoder()
let data = try encoder.encode(config)
print(String(data: data, encoding: .utf8)!)
// title = "My App"
// port = 8080
// debug = true
```

### Nested Tables

```swift
struct ServerConfig: Codable {
    var server: Server
    var database: Database
}

struct Server: Codable {
    var host: String
    var port: Int
}

struct Database: Codable {
    var url: String
    var maxConnections: Int
}

let toml = """
[server]
host = "localhost"
port = 8080

[database]
url = "postgres://localhost/mydb"
maxConnections = 10
"""

let decoder = TOMLDecoder()
let config = try decoder.decode(ServerConfig.self, from: toml)
```

### Arrays of Tables

```swift
struct Package: Codable {
    var name: String
    var dependencies: [Dependency]
}

struct Dependency: Codable {
    var name: String
    var version: String
}

let toml = """
name = "my-package"

[[dependencies]]
name = "swift-argument-parser"
version = "1.0.0"

[[dependencies]]
name = "swift-log"
version = "1.4.0"
"""

let decoder = TOMLDecoder()
let package = try decoder.decode(Package.self, from: toml)
```

### Date and Time Types

TOML supports four date-time types. Use the built-in types for local dates and times:

```swift
struct Event: Codable {
    var timestamp: Date            // Offset date-time
    var scheduledAt: LocalDateTime // Local date-time (no timezone)
    var date: LocalDate            // Just a date
    var time: LocalTime            // Just a time
}

let toml = """
timestamp = 2024-01-15T09:30:00Z
scheduledAt = 2024-01-15T09:30:00
date = 2024-01-15
time = 09:30:00
"""

let decoder = TOMLDecoder()
let event = try decoder.decode(Event.self, from: toml)
```

### Key Decoding Strategy

Automatically convert snake_case keys to camelCase:

```swift
struct User: Codable {
    var firstName: String  // Maps from first_name
    var lastName: String   // Maps from last_name
}

let toml = """
first_name = "Ada"
last_name = "Lovelace"
"""

let decoder = TOMLDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase
let user = try decoder.decode(User.self, from: toml)
```

### Encoding Strategies

Control how dates and keys are encoded:

```swift
let encoder = TOMLEncoder()
encoder.dateEncodingStrategy = .localDateTime
encoder.keyEncodingStrategy = .convertToSnakeCase
encoder.outputFormatting = .sortedKeys

let data = try encoder.encode(myValue)
```

### Decoding Limits

Protect against malicious or malformed input:

```swift
let decoder = TOMLDecoder()
decoder.limits.maxInputSize = 1024 * 1024  // 1 MB (default: 10 MB)
decoder.limits.maxDepth = 64               // default: 128
decoder.limits.maxTableKeys = 1000         // default: 10,000
decoder.limits.maxArrayLength = 10_000     // default: 100,000
```

For trusted input where you need no restrictions:

```swift
decoder.limits = .unlimited
```

## Development

### Updating toml++

This library bundles [toml++](https://github.com/marzer/tomlplusplus) as a single-header file. To update to the latest version:

```bash
./scripts/update-tomlplusplus.sh
swift test
cd Tests/Integration && make test
```

A GitHub Action runs weekly to check for toml++ updates and creates an issue when a new version is available.

### Running Tests

```bash
make test  # runs unit tests + integration tests
```

## License

This project is available under the MIT license.
See the LICENSE file for more info.
