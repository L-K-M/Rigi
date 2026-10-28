#!/usr/bin/env bash
# Tag a verified Rigi library revision. The shared engine owns release mechanics.
# Usage: bash scripts/release.sh X.Y.Z [--push]
set -euo pipefail

export RELEASE_APP_NAME="Rigi"
export RELEASE_KIND="tag-only"
export RELEASE_INVOKED_AS="bash scripts/release.sh"
export RELEASE_PRE_TAG="bash scripts/build.sh"
export RELEASE_CI_NOTE="CI verifies the tag and publishes the source release."
BIN="${LKM_RELEASE_BIN:-lkm-release}"
command -v "$BIN" >/dev/null 2>&1 || {
  printf '%s\n' 'Install lkm-release from https://github.com/L-K-M/release-tool.' >&2
  exit 1
}
exec "$BIN" "$@"
