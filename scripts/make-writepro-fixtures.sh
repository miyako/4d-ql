#!/bin/bash
# Regenerate the 4D Write Pro (.4wp) fixtures and their PDF references.
# 4D Write Pro is not part of tool4d, so this needs a full 4D application:
#   FOURD="/Applications/4D 21.2/4D.app/Contents/MacOS/4D" bash scripts/make-writepro-fixtures.sh
# The probe project (Tests/Fixtures/wpfixture) builds each document with the
# WP commands, exports it as .4wp and .pdf to its Output folder, then quits.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
if [ -z "${FOURD:-}" ]; then
    FOURD=$(ls -d /Applications/4D*/4D.app/Contents/MacOS/4D 2>/dev/null | tail -1 || true)
fi
[ -x "${FOURD:-}" ] || { echo "4D not found; set FOURD to the 4D executable" >&2; exit 1; }
PROJECT="$ROOT/Tests/Fixtures/wpfixture"
OUT="$ROOT/Tests/FourDFileKitTests/Fixtures/WritePro"
rm -rf "$PROJECT/Output"
echo "==> $FOURD"
"$FOURD" --project="$PROJECT/Project/wpfixture.4DProject" --dataless --skip-onstartup --startup-method=wp_probe 2>&1 | grep -v '^$' || true
for name in text layout objects table media more; do
    [ -s "$PROJECT/Output/$name.4wp" ] || { echo "missing $name.4wp; see the probe log above" >&2; exit 1; }
done
mkdir -p "$OUT"
cp "$PROJECT"/Output/*.4wp "$OUT/"
echo "==> Fixtures copied to $OUT (PDF references stay in $PROJECT/Output)"
