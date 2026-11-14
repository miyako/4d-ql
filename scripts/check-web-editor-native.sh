#!/bin/bash
# Run only the isolated, repository-owned test project in the full 4D application.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FOURD=${FOURD:-"/Applications/4D 21.2/4D.app/Contents/MacOS/4D"}
DEST=${1:?Usage: bash scripts/check-web-editor-native.sh OUTPUT_DIRECTORY [--continuous-probe|--cell-list-probe|--colspan-probe|--rowspan-probe|--nowitness-probe|--objpage-probe|--recheck]}
[ "${2:-}" = "" ] || [ "$2" = "--continuous-probe" ] || [ "$2" = "--cell-list-probe" ] || [ "$2" = "--colspan-probe" ] || [ "$2" = "--rowspan-probe" ] || [ "$2" = "--nowitness-probe" ] || [ "$2" = "--objpage-probe" ] || [ "$2" = "--recheck" ] || { echo "Unknown native gate mode." >&2; exit 1; }
[ -x "$FOURD" ] || { echo "Full 4D application not found; set FOURD. tool4d cannot validate Write Pro." >&2; exit 1; }
if [ "${2:-}" = "--recheck" ]; then
  [ -s "$DEST/Input/cases.json" ] && [ -s "$DEST/Project/wpfixture.4DProject" ] || { echo "Recheck requires existing generated evidence." >&2; exit 1; }
  [ ! -e "$DEST/final-native.log" ] || { echo "Final native recheck evidence already exists; it will not be overwritten." >&2; exit 1; }
else
  [ ! -e "$DEST" ] || { echo "Choose a new output directory; existing evidence will not be overwritten." >&2; exit 1; }
fi
LOCK="$HOME/.copilot/4d-ql-native-gate.lock"
mkdir -p "$HOME/.copilot"
mkdir "$LOCK" 2>/dev/null || { echo "Another native gate owns $LOCK. Coordinate ownership; never remove a live lock." >&2; exit 1; }
trap 'rmdir "$LOCK"' EXIT
if ps -axo comm= | grep -F '/4D.app/Contents/MacOS/4D' >/dev/null; then
  echo "Full native 4D is already running. Coordinate ownership; never interrupt another process." >&2
  exit 1
fi
if [ "${2:-}" != "--recheck" ]; then
  mkdir -p "$DEST/Input" "$DEST/Output"
  cp -R "$ROOT/Tests/Fixtures/wpfixture/Project" "$DEST/Project"
  cp -R "$ROOT/Tests/Fixtures/wpfixture/Resources" "$DEST/Resources"
fi
DEST=$(cd "$DEST" && pwd)
run_4d() {
python3 - "$FOURD" "$DEST" "$1" "$2" <<'PY'
import pathlib
import subprocess
import sys

application, destination, method, logfile = sys.argv[1:]
root = pathlib.Path(destination)
with (root / logfile).open("w") as log:
    process = subprocess.Popen(
        [application, "--project=" + str(root / "Project/wpfixture.4DProject"),
         "--dataless", "--skip-onstartup", "--startup-method=" + method],
        stdout=log, stderr=subprocess.STDOUT,
    )
    try:
        code = process.wait(timeout=300)
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        raise SystemExit("Full 4D did not finish in 300 seconds; inspect native.log and any application dialog. No native pass is claimed.")
    if code:
        raise SystemExit(f"Full 4D exited with {code}; inspect native.log. No native pass is claimed.")
PY
}
if [ "${2:-}" = "--recheck" ]; then
  run_4d wp_web_check final-native.log
  (cd "$ROOT/web-editor" && node scripts/native-roundtrip.mjs verify "$DEST") > "$DEST/final-verify.log" 2>&1
  cat "$DEST/final-verify.log"
  exit 0
fi
if [ "${2:-}" = "--objpage-probe" ]; then
  run_4d wp_objpage_check objpage-native.log
  python3 - "$DEST" <<'PY'
import json
import pathlib
import sys
root = pathlib.Path(sys.argv[1]) / "Output"
errors = json.loads((root / "objpage-errors.json").read_text())
report = json.loads((root / "objpage-report.json").read_text())
if errors or report.get("version") != "F0012102" or len(report.get("cases", [])) != 11:
    raise SystemExit("Native object pagination probe failed: " + json.dumps(errors, ensure_ascii=False))
PY
  echo "Independent native object pagination evidence retained in $DEST"
  exit 0
fi
if [ "${2:-}" = "--nowitness-probe" ]; then
  run_4d wp_nowitness_check nowitness-native.log
  python3 - "$DEST" <<'PY'
import json
import pathlib
import sys
root = pathlib.Path(sys.argv[1]) / "Output"
errors = json.loads((root / "nowitness-errors.json").read_text())
report = json.loads((root / "nowitness-report.json").read_text())
if errors or report.get("version") != "F0012102" or len(report.get("cases", [])) != 14:
    raise SystemExit("Native no-witness probe failed: " + json.dumps(errors, ensure_ascii=False))
PY
  echo "Independent native no-witness evidence retained in $DEST"
  exit 0
fi
if [ "${2:-}" = "--rowspan-probe" ]; then
  run_4d wp_rowspan_check rowspan-native.log
  python3 - "$DEST" <<'PY'
import json
import pathlib
import sys
root = pathlib.Path(sys.argv[1]) / "Output"
errors = json.loads((root / "rowspan-errors.json").read_text())
report = json.loads((root / "rowspan-report.json").read_text())
if errors or report.get("version") != "F0012102" or len(report.get("cases", [])) != 13:
    raise SystemExit("Native rowspan probe failed: " + json.dumps(errors, ensure_ascii=False))
PY
  echo "Independent native rowspan evidence retained in $DEST"
  exit 0
fi
if [ "${2:-}" = "--colspan-probe" ]; then
  run_4d wp_colspan_check colspan-native.log
  python3 - "$DEST" <<'PY'
import json
import pathlib
import sys
root = pathlib.Path(sys.argv[1]) / "Output"
errors = json.loads((root / "colspan-errors.json").read_text())
report = json.loads((root / "colspan-report.json").read_text())
if errors or report.get("version") != "F0012102" or len(report.get("cases", [])) != 10:
    raise SystemExit("Native colspan probe failed: " + json.dumps(errors, ensure_ascii=False))
PY
  echo "Independent native colspan evidence retained in $DEST"
  exit 0
fi
if [ "${2:-}" = "--cell-list-probe" ]; then
  run_4d wp_cell_list_check cell-list-native.log
  python3 - "$DEST" <<'PY'
import json
import pathlib
import sys
root = pathlib.Path(sys.argv[1]) / "Output"
errors = json.loads((root / "cell-list-errors.json").read_text())
report = json.loads((root / "cell-list-report.json").read_text())
if errors or report.get("version") != "F0012102" or len(report.get("cases", [])) != 18:
    raise SystemExit("Native cell list probe failed: " + json.dumps(errors, ensure_ascii=False))
PY
  echo "Independent native cell list evidence retained in $DEST"
  exit 0
fi
if [ "${2:-}" = "--continuous-probe" ]; then
  run_4d wp_continuous_paged_check continuous-native.log
  python3 - "$DEST" <<'PY'
import json
import pathlib
import sys
root = pathlib.Path(sys.argv[1]) / "Output"
errors = json.loads((root / "continuous-paged-errors.json").read_text())
report = json.loads((root / "continuous-paged-report.json").read_text())
if errors or report.get("version") != "F0012102" or len(report.get("cases", [])) != 14:
    raise SystemExit("Native continuous seam probe failed: " + json.dumps(errors, ensure_ascii=False))
PY
  echo "Independent native continuous seam evidence retained in $DEST"
  exit 0
fi
run_4d wp_media_check media-native.log
python3 - "$DEST" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1]) / "Output"
errors = json.loads((root / "media-errors.json").read_text())
report = json.loads((root / "media-report.json").read_text())
if errors or report.get("version") != "F0012102" or len(report.get("cases", [])) != 7:
    raise SystemExit("Native media probe failed: " + json.dumps(errors, ensure_ascii=False))
for case in report["cases"]:
    stages = case["stages"]
    if len(stages) != 7 or len(stages[0]["stats"]["objects"]) != 2:
        raise SystemExit("Missing native media creation/operation evidence.")
    if any(stage["stats"]["body"] != stages[0]["stats"]["body"] for stage in stages):
        raise SystemExit("Native object mutation changed the body tape or bookmarks.")
objects = json.loads((root / "object-report.json").read_text())
if objects.get("version") != "F0012102" or len(objects.get("cases", [])) != 3:
    raise SystemExit("Missing independent native object lifecycle evidence.")
for case in objects["cases"]:
    stages = case["stages"]
    if len(stages) != 14 or [len(stages[i]["stats"]["objects"]) for i in [0, 1, 2, 11, 12, 13]] != [2, 3, 4, 3, 2, 4]:
        raise SystemExit("Missing native object creation/deletion/recreation stages.")
    if any(stage["stats"]["body"] != stages[0]["stats"]["body"] for stage in stages):
        raise SystemExit("Native object lifecycle changed body coordinates or bookmarks.")
PY
run_4d wp_header_check header-native.log
[ -s "$DEST/Output/header-report.json" ] || { echo "Full 4D produced no header report; inspect $DEST/header-native.log." >&2; exit 1; }
python3 - "$DEST" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1]) / "Output"
errors = json.loads((root / "header-errors.json").read_text())
report = json.loads((root / "header-report.json").read_text())
if errors or report.get("version") != "F0012102" or len(report.get("cases", [])) != 7:
    raise SystemExit("Native header/footer probe failed: " + json.dumps(errors, ensure_ascii=False))
if [error["code"] for error in report.get("bookmarkErrors", [])] != [110]:
    raise SystemExit("Missing native header-bookmark rejection evidence.")
if any(len(case.get("stages", [])) != 14 for case in report["cases"]):
    raise SystemExit("Missing native header/footer mutation stages.")
variants = json.loads((root / "variant-report.json").read_text())
if variants.get("version") != "F0012102" or len(variants.get("cases", [])) != 9 or any(
    len(case.get("stages", [])) != 13 for case in variants["cases"]
):
    raise SystemExit("Missing native variant copy/removal/positioning evidence.")
if [[error["code"] for error in item["errors"]] for item in variants["validation"]] != [[204], [], [], [], [], [], []]:
    raise SystemExit("Unexpected native area-margin validation behavior.")
PY
run_4d wp_layout_check layout-native.log
[ -s "$DEST/Output/layout-report.json" ] || { echo "Full 4D produced no layout report; inspect $DEST/layout-native.log." >&2; exit 1; }
python3 - "$DEST" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1]) / "Output"
errors = json.loads((root / "layout-errors.json").read_text())
if errors:
    raise SystemExit("Native column/tab probe failed: " + json.dumps(errors, ensure_ascii=False))
report = json.loads((root / "layout-report.json").read_text())
if report.get("version") != "F0012102" or len(report.get("cases", [])) != 49:
    raise SystemExit("Missing column/tab cases or unexpected full-4D version; no native pass is claimed.")
PY
run_4d wp_section_check section-native.log
[ -s "$DEST/Output/section-report.json" ] || { echo "Full 4D produced no section report; inspect $DEST/section-native.log." >&2; exit 1; }
python3 - "$DEST" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1]) / "Output"
errors = json.loads((root / "section-errors.json").read_text())
if errors:
    raise SystemExit("Native section probe failed: " + json.dumps(errors, ensure_ascii=False))
report = json.loads((root / "section-report.json").read_text())
if report.get("version") != "F0012102" or len(report.get("cases", [])) != 27:
    raise SystemExit("Missing section cases or unexpected full-4D version; no native pass is claimed.")
PY
run_4d wp_page_check page-native.log
[ -s "$DEST/Output/page-report.json" ] || { echo "Full 4D produced no page report; inspect $DEST/page-native.log." >&2; exit 1; }
run_4d wp_print_check print-native.log
[ -s "$DEST/Output/print-report.json" ] || { echo "Full 4D produced no print report; inspect $DEST/print-native.log." >&2; exit 1; }
python3 - "$DEST" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1]) / "Output"
errors = json.loads((root / "print-errors.json").read_text())
report = json.loads((root / "paged-report.json").read_text())
if errors or report.get("version") != "F0012102" or len(report.get("cases", [])) != 4 or any(
    len(case.get("stages", [])) != 2 for case in report["cases"]
):
    raise SystemExit("Native paged oracle failed: " + json.dumps(errors, ensure_ascii=False))
expanded = json.loads((root / "expanded-report.json").read_text())
if expanded.get("version") != "F0012102" or len(expanded.get("cases", [])) != 3:
    raise SystemExit("Missing independent expanded pagination originals/targets.")
tables = json.loads((root / "paged-table-report.json").read_text())
if tables.get("version") != "F0012102" or len(tables.get("cases", [])) != 3:
    raise SystemExit("Missing independent paged table originals, getters and PDF references.")
columns = json.loads((root / "paged-column-report.json").read_text())
if columns.get("version") != "F0012102" or len(columns.get("cases", [])) != 7:
    raise SystemExit("Missing independent paged column originals, getters and PDF references.")
continuous = json.loads((root / "continuous-paged-report.json").read_text())
if continuous.get("version") != "F0012102" or len(continuous.get("cases", [])) != 14:
    raise SystemExit("Missing independent continuous section originals, getters and PDF references.")
cell_lists = json.loads((root / "cell-list-report.json").read_text())
if cell_lists.get("version") != "F0012102" or len(cell_lists.get("cases", [])) != 18:
    raise SystemExit("Missing independent cell list originals, getters and PDF references.")
PY
run_4d wp_range_check range-native.log
run_4d wp_colspan_check colspan-native.log
run_4d wp_rowspan_check rowspan-native.log
run_4d wp_nowitness_check nowitness-native.log
run_4d wp_objpage_check objpage-native.log
[ -s "$DEST/Output/range-report.json" ] || { echo "Full 4D produced no range report; inspect $DEST/range-native.log." >&2; exit 1; }
(cd "$ROOT/web-editor" && npm run build && node scripts/native-roundtrip.mjs prepare "$DEST")
run_4d wp_web_check native.log
[ -s "$DEST/Output/native-report.json" ] || { echo "Full 4D produced no report; inspect $DEST/native.log. No native pass is claimed." >&2; exit 1; }
(cd "$ROOT/web-editor" && node scripts/native-roundtrip.mjs verify "$DEST")
echo "Native evidence retained in $DEST"
