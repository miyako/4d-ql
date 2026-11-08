#!/usr/bin/env python3
"""Private authored native subform-overflow probe, one bounded R5 invocation."""

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
ENGINE = Path("/Applications/4D 21 R5/4D.app/Contents/MacOS/4D")
SVG = """<svg xmlns="http://www.w3.org/2000/svg" width="160" height="40" viewBox="0 0 160 40">
<rect width="160" height="40" fill="#abcdef"/>
<rect width="5" height="40" fill="#ff0000"/>
<rect x="155" width="5" height="40" fill="#00ff00"/>
</svg>
"""
METHOD = """SET APPLICATION COLOR SCHEME("light")
var $picture : Picture
var $context : Object
$context:={form: "Root"; page: 1; namedMode: "named-static"; loadedMode: "loaded-offscreen-no-events"; applicationScheme: Get Application color scheme; locale: Get database localization(Current localization)}
var $width; $height; $pages : Integer
FORM GET PROPERTIES("Root"; $width; $height; $pages)
$context.width:=$width
$context.height:=$height
$context.pages:=$pages
var $file : 4D.File
$file:=File("/RESOURCES/clip-probe/Root.named.png")
$file.parent.create()
FORM SCREENSHOT("Root"; $picture; 1)
WRITE PICTURE FILE(File("/RESOURCES/clip-probe/Root.named.png").platformPath; $picture)
FORM LOAD("Root")
FORM GOTO PAGE(1)
$context.loadedTheme:=FORM theme
$context.loadedScheme:=FORM Get color scheme
var $left; $top; $right; $bottom : Integer
OBJECT GET COORDINATES(*; "panel"; $left; $top; $right; $bottom)
$context.panelBounds:=New collection($left; $top; $right; $bottom)
FORM SCREENSHOT($picture)
WRITE PICTURE FILE(File("/RESOURCES/clip-probe/Root.loaded.png").platformPath; $picture)
FORM UNLOAD
File("/RESOURCES/clip-probe/context.json").setText(JSON Stringify($context; *))
LOG EVENT(Into system standard outputs; JSON Stringify($context; *); Information message)
QUIT 4D
"""


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--summarize-only", action="store_true")
    args = parser.parse_args()
    output = args.output.expanduser().resolve()
    if output == ROOT or ROOT in output.parents or "tmp" in output.parts:
        parser.error("Use a private session artifact directory")
    output.mkdir(parents=True, exist_ok=True)
    project = output / "project"
    spec = importlib.util.spec_from_file_location("benchmark", ROOT / "scripts/form-benchmark.py")
    benchmark = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(benchmark)
    if not args.summarize_only:
        if project.exists():
            parser.error("Native captures require a fresh output; preserve existing cases")
        write(project / "Project/FormBenchmark.4DProject",
              {"compatibilityVersion": 2100, "tokenizedText": False})
        write(project / "Project/Sources/dependencies.json", {"dependencies": {}})
        metadata = {"$4d": {"version": "1", "kind": "form"}, "destination": "detailScreen"}
        write(project / "Project/Sources/Forms/Root/form.4DForm", {
            **metadata, "width": 400, "height": 200,
            "pages": [{"objects": {}}, {"objects": {"panel": {
                "type": "subform", "detailForm": "Child", "left": 100,
                "top": 50, "width": 120, "height": 80}}}]})
        write(project / "Project/Sources/Forms/Child/form.4DForm", {
            **metadata, "width": 160, "height": 80,
            "pages": [{"objects": {}}, {"objects": {"overflowPicture": {
                "type": "picture", "picture": "Images/overflow.svg",
                "pictureFormat": "scaled", "left": -5, "top": 30,
                "width": 160, "height": 40}}}]})
        asset = project / "Project/Sources/Forms/Child/Images/overflow.svg"
        asset.parent.mkdir(parents=True, exist_ok=True)
        asset.write_text(SVG)
        method = project / "Project/Sources/Methods/benchmark_capture.4dm"
        method.parent.mkdir(parents=True, exist_ok=True)
        method.write_text(METHOD)
        schema = Path("/Applications/4D 21 R5/4D.app/Contents/Resources/JSONSchemas/formsSchema.json")
        benchmark.run([ROOT / "tools/4dform/boon", schema,
                       *sorted(project.rglob("*.4DForm"))], output / "schema.log")
        assert benchmark.read_json(project / "Project/Sources/dependencies.json") == {"dependencies": {}}
        benchmark.run([ENGINE, "--version"], output / "engine-version.log", 90)
        benchmark.run([ENGINE, f"--project={project / 'Project/FormBenchmark.4DProject'}",
                       "--dataless", "--skip-onstartup", "--startup-method=benchmark_capture"],
                      output / "native.log", 90)
    from PIL import Image, ImageChops
    context = benchmark.read_json(project / "Resources/clip-probe/context.json")
    assert context["width"] == 400 and context["height"] == 200
    assert context["loadedTheme"] == "LiquidGlass" and context["loadedScheme"] == "light"
    report = {"status": "complete", "context": context,
              "engineVersion": (output / "engine-version.log").read_text().strip(),
              "invocation": benchmark.read_json(output / "native.log.json"),
              "sourceForms": {name: benchmark.read_json(
                  project / f"Project/Sources/Forms/{name}/form.4DForm") for name in ("Root", "Child")},
              "expectedVisibleBounds": [100, 80, 220, 120],
              "unclippedPictureBounds": [95, 80, 255, 120],
              "sourceMarkers": {"red": [0, 0, 5, 40], "green": [155, 0, 160, 40]},
              "images": [], "caveats": [
                  "Loaded-offscreen/no-events is not a live DIALOG reference.",
                  "Absent loaded pixels cannot prove loaded clipping.",
                  "Exact-color pixel masks describe passive asset paint, not widget API coordinates."]}
    for mode in ("named", "loaded"):
        original = project / f"Resources/clip-probe/Root.{mode}.png"
        try:
            image, info = benchmark.verified_image(original, (400, 200))
        except RuntimeError as error:
            if mode != "loaded":
                raise
            with Image.open(original) as decoded:
                decoded.load()
                if decoded.size != (400, 200):
                    raise
                image = decoded.convert("RGBA")
            info = {"status": "incomplete-loaded-context", "validationError": str(error),
                    "rawPixelSize": [400, 200], "sha256": hashlib.sha256(original.read_bytes()).hexdigest()}
        target = output / f"Root.{mode}.png"
        image.save(target)
        pixels = {}
        for name, color in [("blue", (171, 205, 239)), ("red", (255, 0, 0)), ("green", (0, 255, 0))]:
            channels = ImageChops.difference(image.convert("RGB"), Image.new("RGB", image.size, color)).split()
            mask = ImageChops.lighter(ImageChops.lighter(channels[0], channels[1]), channels[2]).point(
                lambda p: 255 if p == 0 else 0)
            pixels[name] = {"bounds": mask.getbbox(), "exactPixels": mask.histogram()[255]}
        report["images"].append({"mode": mode, **info, "coloredPixels": pixels})
    named = report["images"][0]["coloredPixels"]
    report["namedClippingVerified"] = (
        list(named["blue"]["bounds"] or []) == report["expectedVisibleBounds"]
        and named["blue"]["exactPixels"] == 4800
        and named["red"]["exactPixels"] == named["green"]["exactPixels"] == 0)
    if report["images"][1].get("status") == "incomplete-loaded-context":
        report["status"] = "complete-named-reference; loaded-incomplete"
    write(output / "report.json", report)
    (output / "gallery.html").write_text(
        '<!doctype html><meta charset="utf-8"><title>Native clipping probe</title>'
        '<h1>Native subform overflow</h1><a href="report.json">Pixel bounds/provenance</a>'
        '<h2>Named</h2><img src="Root.named.png">'
        '<h2>Loaded offscreen/no events</h2><img src="Root.loaded.png">')
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    sys.dont_write_bytecode = True
    sys.exit(main())
