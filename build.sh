#!/usr/bin/env bash
# Copyright 2026 pauloipf
# SPDX-License-Identifier: Apache-2.0
#
# Compiles arm64vm and signs it with the virtualization entitlement.
set -euo pipefail

cd "$(dirname "$0")"

if [[ "$(uname -m)" != "arm64" ]]; then
    echo "Error: requires a Mac with Apple Silicon (arm64)." >&2
    exit 1
fi

macos_major="$(sw_vers -productVersion | cut -d. -f1)"
if (( macos_major < 14 )); then
    echo "Error: requires macOS 14 or later (found $(sw_vers -productVersion))." >&2
    exit 1
fi

if ! command -v swiftc >/dev/null 2>&1; then
    echo "Error: swiftc not found. Install the Xcode Command Line Tools: xcode-select --install" >&2
    exit 1
fi

echo "Compiling..."
swiftc -O main.swift -o arm64vm

echo "Signing with entitlements.plist..."
codesign --entitlements entitlements.plist --force -s - arm64vm

echo "Done: ./arm64vm --help"
