#!/bin/bash
# Regenerate native .4vp and Excel references, then verify their observed schema.
# Full 4D is required: tool4d cannot host the offscreen View Pro Web Area.
# The dependency manager resolves 4D ViewPro from dependencies.json. It can reuse
# the component cached by the user's blank view-pro-test project.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
FOURD="${FOURD:-/Applications/4D 21 R4/4D.app/Contents/MacOS/4D}"
[ -x "$FOURD" ] || { echo "Set FOURD to a full 4D executable" >&2; exit 1; }
PROJECT="$ROOT/Tests/Fixtures/vpfixture"
OUT="$ROOT/Tests/FourDFileKitTests/Fixtures/ViewPro"
mkdir -p "$PROJECT/Output"
rm -f "$PROJECT/Output/"*.4vp "$PROJECT/Output/"*.xlsx "$PROJECT/Output/result.json" "$PROJECT/Output/error.txt"
echo "==> $FOURD"
python3 - "$FOURD" "$PROJECT" <<'PY'
import pathlib, subprocess, sys
executable, project = sys.argv[1:]
log = pathlib.Path(project) / "Output/run.log"
with log.open("w") as stream:
    process = subprocess.Popen([executable, "--project=" + project + "/Project/vpfixture.4DProject",
                                "--dataless", "--skip-onstartup", "--startup-method=vp_probe"],
                               stdout=stream, stderr=subprocess.STDOUT)
    try:
        code = process.wait(timeout=120)
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        raise SystemExit("4D timed out after 120 seconds; see " + str(log))
if code:
    raise SystemExit("4D exited with status " + str(code) + "; see " + str(log))
PY
cat "$PROJECT/Output/run.log"
[ ! -e "$PROJECT/Output/error.txt" ] || { cat "$PROJECT/Output/error.txt" >&2; exit 1; }
python3 - "$PROJECT/Output" <<'PY'
import json, pathlib, sys, zipfile, xml.etree.ElementTree as ET
root = pathlib.Path(sys.argv[1])
result = json.loads((root / "result.json").read_text())
assert result.get("success") is True and result.get("exports") == 10, result
names = ["typed", "layout", "values-only", "no-format-info", "roundtrip",
         "xlsx-roundtrip", "enriched", "enriched-xlsx-roundtrip"]
books = {name: json.loads((root / (name + ".4vp")).read_bytes()) for name in names}
typed = books["typed"]["spreadJS"]["sheets"]["Sheet1"]["data"]["dataTable"]
assert typed["0"]["0"]["value"] == "Hello View Pro"
assert typed["0"]["1"]["value"] == 1234.5
assert typed["0"]["2"]["value"] is True and typed["1"]["2"]["value"] is False
assert typed["0"]["3"]["value"] == "/OADate(45351)/"
assert typed["0"]["4"] == {"value": 2469, "formula": "B1*2"}
assert typed["1"]["4"]["value"]["_calcError"] == "#DIV/0!"
layout = books["layout"]["spreadJS"]
sheet = layout["sheets"]["Data"]
assert sheet["index"] == 1 and len(layout["sheets"]) == 4
assert sheet["spans"] == [{"row": 4, "col": 0, "rowCount": 2, "colCount": 4}]
assert sheet["rows"][9] == {"size": 27, "visible": False}
assert sheet["columns"][2] == {"size": 90, "visible": False}
assert sheet["data"]["dataTable"]["4"]["0"]["style"]["parentName"] == "SharedHeading"
assert layout["namedStyles"][0]["name"] == "SharedHeading"
assert sheet["namedStyles"][0]["name"] == "LocalMoney"
assert sheet["data"]["dataTable"]["12"]["0"]["hyperlink"]["url"] == "https://example.com/fixture"
for name in ["roundtrip", "xlsx-roundtrip", "enriched", "enriched-xlsx-roundtrip"]:
    data = books[name]["spreadJS"]["sheets"]["Data"]["data"]["dataTable"]
    assert data["0"]["4"] == {"value": 2469, "formula": "B1*2"}, name
    assert data["12"]["0"]["hyperlink"]["url"] == "https://example.com/fixture", name
values = books["values-only"]["spreadJS"]["sheets"]["Data"]["data"]["dataTable"]
assert values["0"]["4"] == {"value": 2469}
plain = books["no-format-info"]["spreadJS"]["sheets"]["Data"]["data"]["dataTable"]
assert "formatInfo" not in plain["0"]["1"]["style"]
for name in ["enriched", "enriched-xlsx-roundtrip"]:
    sheets = books[name]["spreadJS"]["sheets"]
    assert sheets["Hidden candidate"]["visible"] == 0
    assert sheets["Very hidden candidate"]["visible"] == 2
    runs = sheets["First"]["data"]["dataTable"]["2"]["0"]["value"]["richText"]
    assert "".join(run["text"] for run in runs) == "Bold plain"
ns = {"s": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
for name in ["layout", "enriched"]:
    with zipfile.ZipFile(root / (name + ".xlsx")) as archive:
        assert archive.testzip() is None
        workbook = ET.fromstring(archive.read("xl/workbook.xml"))
        sheets = workbook.find("s:sheets", ns)
        assert [s.attrib["name"] for s in sheets] == ["First", "Data", "Hidden candidate", "Very hidden candidate"]
        if name == "enriched":
            assert sheets[2].attrib["state"] == "hidden"
            assert sheets[3].attrib["state"] == "veryHidden"
            strings = ET.fromstring(archive.read("xl/sharedStrings.xml"))
            rich = [si for si in strings if si.find("s:r", ns) is not None]
            assert any("".join(si.itertext()) == "Bold plain" for si in rich)
print("Verified 8 native .4vp files, 2 Excel references, types, styles, formulas, spans, hidden sheets and rich text.")
PY
mkdir -p "$OUT"
cp "$PROJECT/Output/"*.4vp "$OUT/"
cp "$PROJECT/Output/"*.xlsx "$OUT/"
echo "==> Native fixtures copied to $OUT"
