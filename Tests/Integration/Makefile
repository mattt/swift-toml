.PHONY: all build test test-decoder test-encoder clean

GO ?= go
# toml-test v2.2.0 does not have the invalid/encoding/bom-not-at-start-02 and -03 cases,
# so this pins the commit on main that adds them (it requires Go 1.27 or later).
# Change it to the next release when one is available.
TOML_TEST_VERSION ?= v2.2.1-0.20261027224220-96fd088448ec
TOML_TEST := $(GO) run github.com/toml-lang/toml-test/v2/cmd/toml-test@$(TOML_TEST_VERSION)
TOML_VERSION ?= 1.0.0
DECODER := .build/debug/toml-decoder
ENCODER := .build/debug/toml-encoder

all: test

build: $(DECODER) $(ENCODER)

$(DECODER) $(ENCODER): Sources/**/*.swift Package.swift ../..
	swift build

test: test-decoder test-encoder

test-decoder: $(DECODER)
	$(TOML_TEST) test -toml=$(TOML_VERSION) -decoder=$(DECODER)

# toml-test checks the encoder's output with the decoder,
# so the encoder tests need both commands.
# Each `*` matches one path segment.
test-encoder: $(DECODER) $(ENCODER)
	$(TOML_TEST) test -toml=$(TOML_VERSION) -decoder=$(DECODER) -encoder=$(ENCODER) -run='encoder/*,encoder/*/*'

clean:
	swift package clean
