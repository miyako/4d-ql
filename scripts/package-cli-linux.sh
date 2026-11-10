#!/usr/bin/env bash
# Build on Ubuntu 24.04 x86_64; recipients do not need Swift installed.
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "usage: $0 VERSION [OUTPUT_DIRECTORY]" >&2
    exit 2
fi

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
python3 scripts/package-cli-linux.py --check-host
swift build -c release --product fourdql
bin_dir="$(swift build -c release --show-bin-path)"
python3 scripts/package-cli-linux.py \
    --version "$1" --output-dir "${2:-dist}" --binary "$bin_dir/fourdql"
