.PHONY: build test update-tomlplusplus clean

# Build the package
build:
	swift build

# Run all tests (unit + integration)
test:
	swift test
	cd Tests/Integration && make test

# Update toml++ to the latest version
update-tomlplusplus:
	./scripts/update-tomlplusplus.sh

# Clean build artifacts
clean:
	swift package clean
	rm -rf .build
