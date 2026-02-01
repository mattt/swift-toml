#!/bin/bash
# Updates toml++ to the latest version from GitHub releases.
# Usage: ./Scripts/update-tomlplusplus.sh [--check] [--github-output <path>]
#
# Supply-chain note:
# This script downloads C++ header code from a third-party GitHub repository.
# For CI, use --check only (no download).
# To reduce risk when updating locally, 
# pin to a specific tag and verify checksums if needed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TOML_HPP="$PROJECT_ROOT/Sources/CTomlPlusPlus/toml.hpp"
TOMLPP_REPO="marzer/tomlplusplus"

CHECK_ONLY=0
GITHUB_OUTPUT_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)
            CHECK_ONLY=1
            shift
            ;;
        --github-output)
            if [[ $# -lt 2 || -z "${2:-}" ]]; then
                echo "Error: --github-output requires a path argument" >&2
                exit 2
            fi
            GITHUB_OUTPUT_PATH="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
        *)
            break
            ;;
    esac
done

# Get current version from toml.hpp
if [[ -f "$TOML_HPP" ]]; then
    CURRENT_MAJOR=$(grep -o 'TOML_LIB_MAJOR[[:space:]]*[0-9]*' "$TOML_HPP" | grep -o '[0-9]*$' | head -1) || true
    CURRENT_MINOR=$(grep -o 'TOML_LIB_MINOR[[:space:]]*[0-9]*' "$TOML_HPP" | grep -o '[0-9]*$' | head -1) || true
    CURRENT_PATCH=$(grep -o 'TOML_LIB_PATCH[[:space:]]*[0-9]*' "$TOML_HPP" | grep -o '[0-9]*$' | head -1) || true
    if [[ -n "${CURRENT_MAJOR:-}" && -n "${CURRENT_MINOR:-}" && -n "${CURRENT_PATCH:-}" ]]; then
        CURRENT_VERSION="v${CURRENT_MAJOR}.${CURRENT_MINOR}.${CURRENT_PATCH}"
    else
        CURRENT_VERSION="unknown"
        echo "Warning: Could not parse version from toml.hpp (missing or unexpected format)" >&2
    fi
    echo "Current toml++ version: $CURRENT_VERSION"
else
    CURRENT_VERSION="none"
    echo "No existing toml.hpp found"
fi

# Get latest version from GitHub API
echo "Checking for latest release..."
GITHUB_JSON=$(curl -sf "https://api.github.com/repos/${TOMLPP_REPO}/releases/latest") || {
    echo "Error: Failed to fetch latest release from GitHub (network error or non-2xx response)" >&2
    exit 1
}
if command -v jq &>/dev/null; then
    LATEST_VERSION=$(printf '%s' "$GITHUB_JSON" | jq -r '.tag_name // empty')
else
    LATEST_VERSION=$(printf '%s' "$GITHUB_JSON" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
fi
if [[ -z "${LATEST_VERSION:-}" ]]; then
    echo "Error: Could not parse latest version from GitHub API response" >&2
    exit 1
fi

# Validate version format to prevent command injection
if [[ ! "$LATEST_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Unexpected version format: $LATEST_VERSION" >&2
    exit 1
fi

echo "Latest toml++ version: $LATEST_VERSION"

if [[ -n "$GITHUB_OUTPUT_PATH" ]]; then
    {
        echo "current=${CURRENT_VERSION}"
        echo "latest=${LATEST_VERSION}"
        if [[ "$CURRENT_VERSION" != "$LATEST_VERSION" ]]; then
            echo "update_available=true"
        else
            echo "update_available=false"
        fi
    } >> "$GITHUB_OUTPUT_PATH"
fi

if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
    echo "Already up to date!"
    exit 0
fi

if [[ "$CHECK_ONLY" == "1" ]]; then
    echo "Update available."
    exit 0
fi

# Download the latest single-header version
echo "Downloading toml++ $LATEST_VERSION..."
DOWNLOAD_URL="https://raw.githubusercontent.com/${TOMLPP_REPO}/${LATEST_VERSION}/toml.hpp"
TOML_TMP="$TOML_HPP.tmp"
trap 'rm -f "$TOML_TMP"' EXIT

if ! curl -fL "$DOWNLOAD_URL" -o "$TOML_TMP"; then
    echo "Error: Failed to download toml++" >&2
    exit 1
fi

if ! grep -q "TOML_LIB_MAJOR" "$TOML_TMP"; then
    echo "Error: Downloaded file failed verification (missing TOML_LIB_MAJOR)" >&2
    exit 1
fi

mv "$TOML_TMP" "$TOML_HPP"
trap - EXIT
echo "Successfully updated toml++ to $LATEST_VERSION"

echo ""
echo "Next steps:"
echo "  1. Run 'swift test' to verify compatibility"
echo "  2. Run 'cd Tests/Integration && make test' for full compliance testing"
echo "  3. Commit the changes if all tests pass"
