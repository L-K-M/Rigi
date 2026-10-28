#!/usr/bin/env bash
# Build the native Rigi library and gallery, optionally clean or run the gallery.
# Usage: bash scripts/build.sh [--clean] [--run]
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
clean=0
run=0
for argument in "$@"; do
  case "$argument" in
    --clean) clean=1 ;;
    --run) run=1 ;;
    -h|--help) printf '%s\n' 'Usage: bash scripts/build.sh [--clean] [--run]'; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$argument" >&2; exit 2 ;;
  esac
done

if [[ "$(uname -s)" != Darwin ]]; then
  printf '%s\n' 'Rigi requires macOS and AppKit.' >&2
  exit 1
fi

if ((clean)); then swift package --package-path "$ROOT" clean; fi
swift test --package-path "$ROOT"
swift build --package-path "$ROOT" -c release
if ((run)); then swift run --package-path "$ROOT" -c release RigiGallery; fi
