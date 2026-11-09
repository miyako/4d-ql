#!/bin/bash
# Regenerate the controlled .4st fixtures in an isolated temporary database.
# TOOL4D=/path/to/tool4d bash scripts/make-set-fixtures.sh
# MILLION_RECORDS=1 also regenerates fixtures from a real million-record table.
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
python3 - "$WORK/out" <<'PY'
import pathlib
import struct
import sys

out = pathlib.Path(sys.argv[1])
def write_set(name, span, positions):
    pages = (span + 32767) // 32768
    bitmaps = {}
    for record in positions:
        page = record // 32768
        bitmap = bitmaps.setdefault(page, bytearray(4096))
        bitmap[(record % 32768) // 8] |= 1 << (record % 8)
    tags = bytes(7 if page in bitmaps else 0 for page in range(pages))
    with (out / (name + "-input.4st")).open("wb") as stream:
        stream.write(struct.pack(">iI", -1, 0) + b"70D4" + struct.pack("<III", 1, span, pages))
        stream.write(tags)
        for page in sorted(bitmaps):
            stream.write(bitmaps[page])

write_set("billion-sparse", 1_000_000_000,
          [0, 32767, 32768, 2097151, 2097152, 536870911, 536870912, 999999999])
write_set("large-bitmap", 1025 * 32768, range(0, 1025 * 32768, 32768))
PY
"$TOOL4D" --project="$WORK/Project/encfixture.4DProject" --data="$WORK/Data/sets.4DD" \
    --create-data --skip-onstartup --startup-method=make_sets --user-param="$WORK/out/"
python3 - "$WORK/out" <<'PY'
import pathlib
import struct
import sys

out = pathlib.Path(sys.argv[1])
for name in ("billion-sparse", "large-bitmap"):
    original = (out / (name + "-input.4st")).read_bytes()
    saved = (out / (name + ".4st")).read_bytes()
    if saved != original:
        raise SystemExit("4D round-trip changed " + name)
empty = (out / "large-address-empty.4st").read_bytes()
tags = empty[24:1050]
if (struct.unpack_from("<III", empty, 12) != (1, 33587201, 1026)
        or tags[:-1] != bytes(1025) or tags[-1] not in (0, 7)
        or empty[1050:] != bytes(4096 if tags[-1] == 7 else 0)):
    raise SystemExit("Unexpected native large-address set layout")
print("==> Verified native 1,026-page directory and byte-exact large/billion-address round trips")
PY
OUT="$ROOT/Tests/FourDFileKitTests/Fixtures/Sets/generated"
mkdir -p "$OUT"
for name in empty full first boundary last page middle two-pages tail ends large-address-empty billion-sparse; do
    [ -s "$WORK/out/$name.4st" ] || { echo "Missing fixture: $name" >&2; exit 1; }
done
for name in empty full first boundary last page middle two-pages tail ends large-address-empty billion-sparse; do
    cp "$WORK/out/$name.4st" "$OUT/"
done
if [ "${MILLION_RECORDS:-0}" = "1" ]; then
    cp -R Tests/Fixtures/encfixture/Project "$WORK/MillionProject"
    mkdir -p "$WORK/MillionData"
    "$TOOL4D" --project="$WORK/MillionProject/encfixture.4DProject" --data="$WORK/MillionData/sets.4DD" \
        --create-data --skip-onstartup --startup-method=make_million_sets --user-param="$WORK/out/"
    for name in million-full million-alternating; do
        [ -s "$WORK/out/$name.4st" ] || { echo "Missing fixture: $name" >&2; exit 1; }
        cp "$WORK/out/$name.4st" "$OUT/"
    done
fi
echo "==> Fixtures copied to $OUT"
echo "==> Temporary database retained at $WORK"
