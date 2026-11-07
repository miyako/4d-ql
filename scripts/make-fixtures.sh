#!/bin/bash
# Regenerates the test data files in Tests/FourDFileKitTests/Fixtures with tool4d:
#   plain.4DD      a data file whose structure has encryptable tables, never encrypted
#   encrypted.4DD  the same data after Encrypt data file
#   journaled.4DD  the same data with a journal file configured
#
#   TOOL4D=/path/to/tool4d scripts/make-fixtures.sh
# (defaults to the newest tool4d under /Applications/4D*)
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
PROJ="$ROOT/Tests/Fixtures/encfixture"
OUT="$ROOT/Tests/FourDFileKitTests/Fixtures"

if [ -z "${TOOL4D:-}" ]; then
    TOOL4D=$(ls -d /Applications/4D*/tool4d.app/Contents/MacOS/tool4d 2>/dev/null | sort -V | tail -1 || true)
fi
[ -x "${TOOL4D:-}" ] || { echo "tool4d not found; set TOOL4D" >&2; exit 1; }
echo "==> $("$TOOL4D" --version)"

rm -rf "$PROJ/Data" "$PROJ/archive"
mkdir -p "$PROJ/Data" "$OUT"

"$TOOL4D" --project="$PROJ/Project/encfixture.4DProject" --data="$PROJ/Data/plain.4DD" \
    --create-data --skip-onstartup --startup-method=make_data

cp "$PROJ/Data/plain.4DD" "$PROJ/Data/encrypted.4DD"
cp "$PROJ/Data/plain.4DIndx" "$PROJ/Data/encrypted.4DIndx"
"$TOOL4D" --project="$PROJ/Project/encfixture.4DProject" --dataless --skip-onstartup \
    --user-param="$PROJ/Data/encrypted.4DD" --startup-method=encrypt_data

cmp -s "$PROJ/Data/plain.4DD" "$PROJ/Data/encrypted.4DD" && { echo "encryption did not change the file" >&2; exit 1; }

# Journal path is stored in the data file's extra properties.
cp "$PROJ/Data/plain.4DD" "$PROJ/Data/journaled.4DD"
cp "$PROJ/Data/plain.4DIndx" "$PROJ/Data/journaled.4DIndx"
"$TOOL4D" --project="$PROJ/Project/encfixture.4DProject" --data="$PROJ/Data/journaled.4DD" \
    --skip-onstartup --startup-method=enable_journal

cp "$PROJ/Data/plain.4DD" "$PROJ/Data/encrypted.4DD" "$PROJ/Data/journaled.4DD" "$OUT/"
ls -la "$OUT"
