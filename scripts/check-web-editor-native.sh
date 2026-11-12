#!/bin/bash
# Run only the isolated, repository-owned test project in the full 4D application.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FOURD=${FOURD:-"/Applications/4D 21.2/4D.app/Contents/MacOS/4D"}
DEST=${1:?Usage: bash scripts/check-web-editor-native.sh NEW_OUTPUT_DIRECTORY}
[ -x "$FOURD" ] || { echo "Full 4D application not found; set FOURD. tool4d cannot validate Write Pro." >&2; exit 1; }
[ ! -e "$DEST" ] || { echo "Choose a new output directory; existing evidence will not be overwritten." >&2; exit 1; }
LOCK="$HOME/.copilot/4d-ql-native-gate.lock"
mkdir -p "$HOME/.copilot"
mkdir "$LOCK" 2>/dev/null || { echo "Another native gate owns $LOCK. Coordinate ownership; never remove a live lock." >&2; exit 1; }
trap 'rmdir "$LOCK"' EXIT
if ps -axo comm= | grep -F '/4D.app/Contents/MacOS/4D' >/dev/null; then
  echo "Full native 4D is already running. Coordinate ownership; never interrupt another process." >&2
  exit 1
fi
mkdir -p "$DEST/Input" "$DEST/Output"
DEST=$(cd "$DEST" && pwd)
cp -R "$ROOT/Tests/Fixtures/wpfixture/Project" "$DEST/Project"
cp -R "$ROOT/Tests/Fixtures/wpfixture/Resources" "$DEST/Resources"
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
        code = process.wait(timeout=180)
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        raise SystemExit("Full 4D did not finish in 180 seconds; inspect native.log and any application dialog. No native pass is claimed.")
    if code:
        raise SystemExit(f"Full 4D exited with {code}; inspect native.log. No native pass is claimed.")
PY
}
run_4d wp_page_check page-native.log
[ -s "$DEST/Output/page-report.json" ] || { echo "Full 4D produced no page report; inspect $DEST/page-native.log." >&2; exit 1; }
run_4d wp_range_check range-native.log
[ -s "$DEST/Output/range-report.json" ] || { echo "Full 4D produced no range report; inspect $DEST/range-native.log." >&2; exit 1; }
(cd "$ROOT/web-editor" && npm run build && node scripts/native-roundtrip.mjs prepare "$DEST")
run_4d wp_web_check native.log
[ -s "$DEST/Output/native-report.json" ] || { echo "Full 4D produced no report; inspect $DEST/native.log. No native pass is claimed." >&2; exit 1; }
(cd "$ROOT/web-editor" && node scripts/native-roundtrip.mjs verify "$DEST")
echo "Native evidence retained in $DEST"
