#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$script_dir/.." && pwd)"

test -d "$root/core"
test -d "$root/platforms/mac"
test -d "$root/platforms/win"
test -f "$root/.gitignore"
test -f "$root/CMakeLists.txt"
test -f "$root/README.md"
test -f "$root/docs/architecture.md"
test -f "$root/core/CMakeLists.txt"
test -f "$root/platforms/mac/packaging/README.md"
test -f "$root/platforms/win/src/README.md"
test -f "$root/platforms/win/tests/README.md"
test -f "$root/platforms/win/packaging/README.md"
