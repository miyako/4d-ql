#!/usr/bin/env python3
"""Prepare private, pinned HDI declarative projects and run the visual benchmark.

No upstream methods, components, events, actions or form classes are installed.
Run under `caffeinate -di` on macOS. Upstream material stays outside the repository.
"""

import argparse
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SPECS = {
    "HDI_FormObj_VericalAlignAndPadding": ("3bf5a6ca1224a26c5ed3164877d211d4f4aaf9d2", [2, 3]),
    "HDI_Buttons": ("a92651b371ee87829fda59ae09de09241d864b29", [2, 3]),
    "HDI_RoundedCorner": ("e335f3ddb73ae66e0eaf5f3ba2829e8f5d33bf26", [2, 3]),
}
PASSIVE = {".png", ".jpg", ".jpeg", ".gif", ".tif", ".tiff", ".bmp", ".webp", ".ico", ".svg"}
CALLBACKS = {"method", "events", "action", "formClass", "menuBar", "editor", "shortcutKey", "shortcutModifiers"}
CAPTURE = """var $param : Text
Get database parameter(User param value; $param)
var $parts : Collection
$parts:=Split string($param; ":")
SET APPLICATION COLOR SCHEME($parts[0])
var $name : Text
$name:=$parts[1]
var $page : Integer
$page:=Num($parts[2])
var $file : 4D.File
$file:=File($parts.slice(4).join(":"))
$file.parent.create()
var $width; $height; $pages : Integer
FORM GET PROPERTIES($name; $width; $height; $pages)
var $context : Object
$context:={mode: "named-static"; form: $name; page: $page; width: $width; height: $height; pages: $pages; applicationScheme: Get Application color scheme}
FORM LOAD("BenchmarkTheme")
$context.loadedTheme:=FORM theme
$context.loadedScheme:=FORM Get color scheme
FORM UNLOAD
var $picture : Picture
FORM SCREENSHOT($name; $picture; $page)
WRITE PICTURE FILE($file.platformPath; $picture)
If ($parts[3]="1")
    FORM LOAD($name+"_LoadedSafe")
    FORM GOTO PAGE($page)
    $context.companion:={mode: "loaded-offscreen-no-events"; bindings: "removed; no runtime values invented"; font: OBJECT Get font(*; "Button1"); fontSize: OBJECT Get font size(*; "Button1")}
    FORM SCREENSHOT($picture)
    WRITE PICTURE FILE(File($file.path+".loaded.png").platformPath; $picture)
    FORM UNLOAD
End if
File($file.path+".json").setText(JSON Stringify($context; *))
LOG EVENT(Into system standard outputs; JSON Stringify($context; *); Information message)
QUIT 4D
"""


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def sanitize(value, removed, location="", loaded=False):
    if isinstance(value, list):
        return [sanitize(v, removed, f"{location}/{i}", loaded) for i, v in enumerate(value)]
    if not isinstance(value, dict):
        return value
    result = {}
    for key, item in value.items():
        if key in CALLBACKS or (loaded and (key.lower().endswith("source") or "formula" in key.lower())):
            removed.append({"path": location + "/" + key, "value": item, "loadedOnly": loaded})
            continue
        result[key] = sanitize(item, removed, location + "/" + key, loaded)
    return result


def download(root, name, sha):
    archive = root / "archives" / (name + ".zip")
    if not archive.exists():
        archive.parent.mkdir(parents=True, exist_ok=True)
        archive.write_bytes(urllib.request.urlopen(
            f"https://codeload.github.com/4d-depot/{name}/zip/{sha}", timeout=60).read())
    destination = root / "upstream" / name
    if not destination.exists():
        with zipfile.ZipFile(io.BytesIO(archive.read_bytes())) as contents:
            for item in contents.infolist():
                rel = Path(*Path(item.filename).parts[1:])
                if item.is_dir() or not rel.parts:
                    continue
                if rel.is_absolute() or ".." in rel.parts:
                    raise RuntimeError("Unsafe upstream archive path")
                target = destination / rel
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(contents.read(item))
    return destination


def prepare(root, name, sha, pages):
    upstream = download(root, name, sha)
    destination = root / "prepared" / name
    if destination.exists():
        return destination
    destination.mkdir(parents=True)
    removed = []
    for source in upstream.rglob("*"):
        if not source.is_file():
            continue
        rel = source.relative_to(upstream)
        allowed = source.suffix.lower() in PASSIVE or source.suffix == ".css" or (
            source.suffix == ".json" and source.name == "tips.json")
        if not allowed:
            continue
        target = destination / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        if source.suffix == ".json":
            write(target, sanitize(load(source), removed, str(rel)))
        else:
            data = source.read_bytes()
            if source.suffix.lower() == ".svg" and re.search(
                    rb"<\s*(script|foreignObject)\b|\bon\w+\s*=|(?:href\s*=\s*[\"'])(?:https?:|javascript:)",
                    data, re.I):
                raise RuntimeError(f"Nonpassive SVG rejected: {source}")
            if source.suffix == ".css" and re.search(rb"@import|url\s*\(", data, re.I):
                raise RuntimeError(f"External CSS reference rejected: {source}")
            target.write_bytes(data)
    form_path = upstream / "Project/Sources/Forms/HDI2/form.4DForm"
    original = load(form_path)
    form = sanitize(original, removed, "HDI2")
    if "width" not in form or "height" not in form:
        form["width"] = form.get("windowMinWidth", 960)
        form["height"] = form.get("windowMinHeight", 640)
    write(destination / "Project/Sources/Forms/HDI2/form.4DForm", form)
    loaded = sanitize(form, removed, "HDI2_LoadedSafe", loaded=True)
    loaded_folder = destination / "Project/Sources/Forms/HDI2_LoadedSafe"
    write(loaded_folder / "form.4DForm", loaded)
    local_images = destination / "Project/Sources/Forms/HDI2/Images"
    if local_images.exists():
        shutil.copytree(local_images, loaded_folder / "Images")
    write(destination / "Project/FormBenchmark.4DProject",
          {"compatibilityVersion": 2100, "tokenizedText": False})
    write(destination / "Project/Sources/dependencies.json", {"dependencies": {}})
    write(destination / "Project/Sources/Forms/BenchmarkTheme/form.4DForm",
          {"$4d": {"version": "1", "kind": "form"}, "destination": "detailScreen",
           "width": 40, "height": 40,
           "pages": [{"objects": {}}, {"objects": {"themeLabel": {
               "type": "text", "left": 0, "top": 0, "width": 40, "height": 20,
               "text": "Theme", "fontSize": 11}}}]})
    method = destination / "Project/Sources/Methods/benchmark_capture.4dm"
    method.parent.mkdir(parents=True, exist_ok=True)
    method.write_text(CAPTURE)
    spec = importlib.util.spec_from_file_location("benchmark", ROOT / "scripts/form-benchmark.py")
    benchmark = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(benchmark)
    excluded = {}
    css = "\n".join(f.read_text(encoding="utf-8-sig") for f in destination.rglob("*.css")
                    if not f.name.endswith("_windows.css"))
    for page in form["pages"]:
        for object_name, obj in page.get("objects", {}).items():
            if any("." + cls in css for cls in obj.get("class", "").split()):
                excluded[object_name] = "Named-static ignores project CSS; loaded companion is a separately labeled, bindings-stripped mode."
    context = [
        f"Public repository 4d-depot/{name}, pinned {sha}; inspected privately, not vendored or licensed for redistribution.",
        "No upstream methods, components, macros, form classes, events, actions or shortcuts are installed. Only the authored capture method runs.",
        "Named-static retains original expression strings as design-time placeholders; it never executes original runtime methods.",
        "Saved alignment/padding/radius values are distinct from runtime setters. No original data, padding state or selection values are invented.",
        "Loaded companions have all data/formula bindings removed and are offscreen, no-events captures. Only CSS/static controls can be compared there.",
        "Page 0 is shared. Editor-only metadata and executable callbacks are removed; declared canvas is fixed to saved dimensions/minimum window dimensions.",
    ]
    write(destination / "benchmark.json", {"title": f"Real HDI calibration — {name}",
          "declarativeOnly": True, "forms": ["HDI2"], "pages": pages,
          "themes": ["classicLight", "classicDark", "glassLight", "glassDark"],
          "noncomparableObjects": {"HDI2": excluded}, "context": context})
    write(root / "audit" / (name + ".json"), {
        "upstreamCommit": sha, "originalFormSHA256": hashlib.sha256(form_path.read_bytes()).hexdigest(),
        "originalFormProperties": original, "removedProperties": removed,
        "canvasNormalization": {"sourceWidth": original.get("width"), "sourceHeight": original.get("height"),
                                "width": form["width"], "height": form["height"]},
        "licenseFiles": [str(f.relative_to(upstream)) for f in upstream.rglob("*LICENSE*")]})
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--fourdql", type=Path, required=True)
    parser.add_argument("--repos", nargs="+", choices=list(SPECS), default=list(SPECS))
    parser.add_argument("--themes", nargs="+", default=["classicLight", "classicDark", "glassLight", "glassDark"])
    parser.add_argument("--compare-only", action="store_true")
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--loaded-companion", action="store_true",
                        help="Only the HDI_Buttons first selected page/Glass-light case gets a safe CSS companion")
    args = parser.parse_args()
    root = args.output.expanduser().resolve()
    if root == ROOT or ROOT in root.parents:
        parser.error("HDI material must remain in a private artifact area outside the repository")
    root.mkdir(parents=True, exist_ok=True)
    codes = []
    for name in args.repos:
        sha, pages = SPECS[name]
        project = prepare(root, name, sha, pages)
        if args.prepare_only:
            continue
        command = [sys.executable, str(ROOT / "scripts/form-benchmark.py"),
                   "--project", str(project), "--output", str(root / "comparison" / name),
                   "--fourdql", str(args.fourdql.resolve()), "--pages", *map(str, pages),
                   "--themes", *args.themes]
        if args.compare_only:
            command.append("--compare-only")
        result = subprocess.run(command)
        codes.append(result.returncode)
        if result.returncode and not args.compare_only:
            break
        if args.loaded_companion and name == "HDI_Buttons" and not args.compare_only and result.returncode == 0:
            companion = [sys.executable, str(ROOT / "scripts/form-benchmark.py"),
                         "--project", str(project), "--output", str(root / "css-companion" / name),
                         "--fourdql", str(args.fourdql.resolve()), "--pages", str(pages[0]),
                         "--themes", "glassLight", "--native-loaded-companion"]
            codes.append(subprocess.run(companion).returncode)
    return max(codes, default=0)


if __name__ == "__main__":
    sys.dont_write_bytecode = True
    sys.exit(main())
