#!/bin/bash
# Regenerate the controlled .4st fixtures in an isolated temporary database.
# TOOL4D=/path/to/tool4d bash scripts/make-set-fixtures.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
if [ -z "${TOOL4D:-}" ]; then
    TOOL4D="/Applications/4D 21 R5/tool4d.app/Contents/MacOS/tool4d"
fi
[ -x "$TOOL4D" ] || { echo "tool4d not found; set TOOL4D" >&2; exit 1; }
WORK=$(mktemp -d "${TMPDIR:-/tmp}/fourd-set-fixtures.XXXXXX")
echo "==> $("$TOOL4D" --version)"
echo "==> Temporary project: $WORK"
mkdir -p "$WORK/Data" "$WORK/out"
cp -R Tests/Fixtures/encfixture/Project "$WORK/Project"
"$TOOL4D" --project="$WORK/Project/encfixture.4DProject" --data="$WORK/Data/sets.4DD" \
    --create-data --skip-onstartup --startup-method=make_sets --user-param="$WORK/out/"
OUT="$ROOT/Tests/FourDFileKitTests/Fixtures/Sets/generated"
mkdir -p "$OUT"
for name in empty full first boundary last page middle two-pages tail ends; do
    [ -s "$WORK/out/$name.4st" ] || { echo "Missing fixture: $name" >&2; exit 1; }
done
for name in empty full first boundary last page middle two-pages tail ends; do
    cp "$WORK/out/$name.4st" "$OUT/"
done
echo "==> Fixtures copied to $OUT"
echo "==> Temporary database retained at $WORK"
