#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v pwsh >/dev/null 2>&1; then
  echo "Mission Centre needs PowerShell 7+ on macOS."
  echo "Install it with: brew install powershell"
  exit 1
fi

pwsh -NoLogo -ExecutionPolicy Bypass -File "$SCRIPT_DIR/Mission-Centre.ps1"
