SWIFT ?= swift
CLANG_FORMAT ?= clang-format

# C++ sources to format/lint (excludes vendored Sources/CTomlPlusPlus/toml.hpp)
CPP_SOURCES ?= Sources/CTomlPlusPlus/ctoml.cpp Sources/CTomlPlusPlus/include/ctoml.h

.PHONY: build test test-unit test-integration update check format format-swift lint lint-swift format-cpp lint-cpp clean

# Default target: build, test, and lint
all: build test lint

# Build the package
build:
	$(SWIFT) build

# Run all tests (unit + integration)
test: test-unit test-integration

# Run unit tests
test-unit:
	$(SWIFT) test

# Run integration tests
test-integration:
	cd Tests/Integration && make test

# Update toml++ to the latest version
update:
	./scripts/update-tomlplusplus.sh

# Check for toml++ updates without downloading
check:
	./scripts/update-tomlplusplus.sh --check

# Format Swift and C/C++ sources
format: format-swift format-cpp

# Format C/C++ bridge sources
format-cpp:
	$(CLANG_FORMAT) -i $(CPP_SOURCES)

# Format Swift sources
format-swift:
	$(SWIFT) format --in-place --recursive .

# Lint Swift and C/C++ sources
lint: lint-swift lint-cpp

# Lint C/C++ bridge formatting
lint-cpp:
	$(CLANG_FORMAT) --dry-run --Werror $(CPP_SOURCES)

# Lint Swift formatting
lint-swift:
	$(SWIFT) format lint --strict --recursive .

# Clean build artifacts
clean:
	$(SWIFT) package clean
	rm -rf .build
