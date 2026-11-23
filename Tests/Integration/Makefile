.PHONY: all build test test-decoder test-encoder clean

GO ?= go
# toml-test v2.2.0 does not have the invalid/encoding/bom-not-at-start-02 and -03 cases,
# so this pins the commit on main that adds them (it requires Go 1.27 or later).
# Change it to the next release when one is available.
TOML_TEST_VERSION ?= v2.2.1-0.20261027224220-96fd088448ec
TOML_TEST := $(GO) run github.com/toml-lang/toml-test/v2/cmd/toml-test@$(TOML_TEST_VERSION)
TOML_VERSIONS ?= 1.0.0 1.1.0
DECODER := .build/debug/toml-decoder
ENCODER := .build/debug/toml-encoder

# The decoder implements TOML 1.1.0, which allows these documents
# that TOML 1.0.0 rejects.
# `-skip-must-err` makes the run fail if a skipped case passes,
# so the list stays exact.
SKIP_1.0.0 := invalid/datetime/no-secs,invalid/local-datetime/no-secs,invalid/local-time/no-secs,invalid/inline-table/linebreak-01,invalid/inline-table/linebreak-02,invalid/inline-table/linebreak-03,invalid/inline-table/linebreak-04,invalid/inline-table/trailing-comma,invalid/string/basic-byte-escapes

all: test

build: $(DECODER) $(ENCODER)

$(DECODER) $(ENCODER): Sources/**/*.swift Package.swift ../..
	swift build

test: test-decoder test-encoder

test-decoder: $(addprefix test-decoder-,$(TOML_VERSIONS))

test-encoder: $(addprefix test-encoder-,$(TOML_VERSIONS))

# These pattern targets are not in .PHONY,
# because make does not apply pattern rules to phony targets.
test-decoder-%: $(DECODER)
	$(TOML_TEST) test -toml=$* -decoder=$(DECODER) $(if $(SKIP_$*),-skip='$(SKIP_$*)' -skip-must-err)

# toml-test checks the encoder's output with the decoder,
# so the encoder tests need both commands.
# Each `*` matches one path segment.
test-encoder-%: $(DECODER) $(ENCODER)
	$(TOML_TEST) test -toml=$* -decoder=$(DECODER) -encoder=$(ENCODER) -run='encoder/*,encoder/*/*'

clean:
	swift package clean
