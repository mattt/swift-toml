# toml-test Integration

This subpackage contains CLI tools for running the [toml-test](https://github.com/toml-lang/toml-test) compliance suite.

## Prerequisites

- Go 1.27 or later (for running toml-test)

The Makefile pins the toml-test version in `TOML_TEST_VERSION`
and runs the tests for each TOML version in `TOML_VERSIONS` (default: `1.0.0 1.1.0`).
The decoder implements TOML 1.1.0,
so the 1.0.0 decoder run skips the invalid cases that TOML 1.1.0 allows.
`SKIP_1.0.0` in the Makefile lists them.

## Usage

```bash
cd Tests/Integration
make                    # build and run all tests
make test-decoder       # decoder tests only
make test-encoder       # encoder tests only
make test-decoder-1.1.0 # decoder tests for one TOML version
make build              # build without running tests
make clean              # clean build artifacts
```

## Manual Testing

### Decoder

Reads TOML bytes from stdin, decodes them with `TOMLDecoder.decode(_:from:)` for `Data`,
and outputs tagged JSON:

```bash
echo 'name = "test"' | ./.build/debug/toml-decoder
# {"name":{"type":"string","value":"test"}}
```

### Encoder

Reads tagged JSON from stdin and outputs TOML:

```bash
echo '{"name":{"type":"string","value":"test"}}' | ./.build/debug/toml-encoder
# name = "test"
```

## Options

Run the tests for only one TOML version:

```bash
make TOML_VERSIONS=1.1.0
```

Skip specific tests:

```bash
go run github.com/toml-lang/toml-test/v2/cmd/toml-test@<version> test -decoder=./.build/debug/toml-decoder -skip='valid/float/inf-and-nan'
```

Run specific tests:

```bash
go run github.com/toml-lang/toml-test/v2/cmd/toml-test@<version> test -decoder=./.build/debug/toml-decoder -run='valid/string/*'
```

Replace `<version>` with the value of `TOML_TEST_VERSION` in the Makefile.
