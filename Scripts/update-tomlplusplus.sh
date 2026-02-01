#!/bin/bash
# Updates toml++ to the latest version from GitHub releases
# Usage: ./Scripts/update-tomlplusplus.sh [--check] [--github-output <path>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TOML_HPP="$PROJECT_ROOT/Sources/CTomlPlusPlus/toml.hpp"

CHECK_ONLY=0
GITHUB_OUTPUT_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)
            CHECK_ONLY=1
            shift
            ;;
        --github-output)
            GITHUB_OUTPUT_PATH="${2:-}"
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
    CURRENT_MAJOR=$(grep -o 'TOML_LIB_MAJOR[[:space:]]*[0-9]*' "$TOML_HPP" | grep -o '[0-9]*$' | head -1)
    CURRENT_MINOR=$(grep -o 'TOML_LIB_MINOR[[:space:]]*[0-9]*' "$TOML_HPP" | grep -o '[0-9]*$' | head -1)
    CURRENT_PATCH=$(grep -o 'TOML_LIB_PATCH[[:space:]]*[0-9]*' "$TOML_HPP" | grep -o '[0-9]*$' | head -1)
    CURRENT_VERSION="v${CURRENT_MAJOR}.${CURRENT_MINOR}.${CURRENT_PATCH}"
    echo "Current toml++ version: $CURRENT_VERSION"
else
    CURRENT_VERSION="none"
    echo "No existing toml.hpp found"
fi

# Get latest version from GitHub API
echo "Checking for latest release..."
LATEST_VERSION=$(curl -s https://api.github.com/repos/marzer/tomlplusplus/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')

if [[ -z "$LATEST_VERSION" ]]; then
    echo "Error: Failed to fetch latest version from GitHub"
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
DOWNLOAD_URL="https://raw.githubusercontent.com/marzer/tomlplusplus/${LATEST_VERSION}/toml.hpp"

if curl -fL "$DOWNLOAD_URL" -o "$TOML_HPP.tmp"; then
    mv "$TOML_HPP.tmp" "$TOML_HPP"
    echo "Successfully updated toml++ to $LATEST_VERSION"

    # Verify the download
    if grep -q "TOML_LIB_MAJOR" "$TOML_HPP"; then
        echo "Verification passed"
    else
        echo "Warning: Downloaded file may be corrupted"
        exit 1
    fi
else
    echo "Error: Failed to download toml++"
    rm -f "$TOML_HPP.tmp"
    exit 1
fi

echo ""
echo "Next steps:"
echo "  1. Run 'swift test' to verify compatibility"
echo "  2. Run 'cd Tests/Integration && make test' for full compliance testing"
echo "  3. Commit the changes if all tests pass"
