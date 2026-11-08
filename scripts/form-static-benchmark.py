#!/usr/bin/env python3
"""Bounded native reference capture of the authored FormStaticProject fixture.

Only an authored capture method runs. Raw schema limitations remain visible;
the fixture's inheritance, inline subform, and localization data are not repaired.
"""

import argparse
import hashlib
import html
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
from html.parser import HTMLParser

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "Tests/FourDFileKitTests/Fixtures/FormStaticProject"
SCHEMA = Path("/Applications/4D 21 R5/4D.app/Contents/Resources/JSONSchemas/formsSchema.json")
ENGINE = Path("/Applications/4D 21 R5/4D.app/Contents/MacOS/4D")
CAPTURE = """var $report : Object
$report:={initialApplicationScheme: Get Application color scheme; defaultLocale: Get database localization; systemLocale: Get database localization(User system localization); captures: New collection; localeChecks: New collection}
SET APPLICATION COLOR SCHEME("light")
$report.requestedApplicationScheme:=Get Application color scheme
var $name : Text
var $width; $height; $pages : Integer
var $picture : Picture
var $item : Object
var $file : 4D.File
ARRAY TEXT($names; 0)
ARRAY POINTER($pointers; 0)
ARRAY INTEGER($objectPages; 0)
var $i; $left; $top; $right; $bottom : Integer
var $object : Text
For each ($name; New collection("Root"; "Base"; "Panel"))
    LOG EVENT(Into system standard outputs; "Named capture "+$name; Information message)
    FORM GET PROPERTIES($name; $width; $height; $pages)
    $item:={form: $name; page: 1; mode: "named-static"; width: $width; height: $height; pages: $pages; locale: Get database localization(Current localization); objects: New collection}
    FORM SCREENSHOT($name; $picture; 1)
    $file:=File("/RESOURCES/static-native/"+$name+".png")
    $file.parent.create()
    WRITE PICTURE FILE($file.platformPath; $picture)
    $item.file:=$file.path
    $report.captures.push($item)
    File("/RESOURCES/static-native/context.json").setText(JSON Stringify($report; *))
End for each
For each ($item; $report.captures)
    $name:=$item.form
    LOG EVENT(Into system standard outputs; "Load getters "+$name; Information message)
    FORM LOAD($name)
    FORM GOTO PAGE(1)
    $item.loadedTheme:=FORM theme
    $item.loadedScheme:=FORM Get color scheme
    FORM GET OBJECTS($names; $pointers; $objectPages; Form current page+Form inherited)
    For ($i; 1; Size of array($names))
        $object:=$names{$i}
        OBJECT GET COORDINATES(*; $object; $left; $top; $right; $bottom)
        $item.objects.push({name: $object; page: $objectPages{$i}; bounds: New collection($left; $top; $right; $bottom); type: OBJECT Get type(*; $object); title: OBJECT Get title(*; $object); font: OBJECT Get font(*; $object); fontSize: OBJECT Get font size(*; $object)})
    End for
    If ($name="Root")
        FORM SCREENSHOT($picture)
        WRITE PICTURE FILE(File("/RESOURCES/static-native/Root.loaded.png").platformPath; $picture)
        $item.loadedCompanion:={mode: "loaded-offscreen-no-events"; file: "/RESOURCES/static-native/Root.loaded.png"; locale: Get database localization(Current localization)}
    End if
    FORM UNLOAD
    File("/RESOURCES/static-native/context.json").setText(JSON Stringify($report; *))
End for each
For each ($name; New collection("en"; "fr"))
    SET DATABASE LOCALIZATION($name; *)
    $item:={requestedLocale: $name; setLocaleOK: OK; actualLocale: Get database localization(Current localization); save: Localized string("save"); window: Localized string("window"); base: Localized string("base")}
    $report.localeChecks.push($item)
End for each
File("/RESOURCES/static-native/context.json").setText(JSON Stringify($report; *))
LOG EVENT(Into system standard outputs; JSON Stringify($report; *); Information message)
QUIT 4D
"""


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def benchmark_module():
    spec = importlib.util.spec_from_file_location("benchmark", ROOT / "scripts/form-benchmark.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def prepare(output):
    project = output / "project"
    if project.exists():
        raise RuntimeError("Use a new output for native capture; existing private projects are immutable capture provenance")
    permitted = {".4dform", ".json", ".css", ".svg", ".png", ".jpg", ".xlf", ".xliff"}
    sources = []
    for path in FIXTURE.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in permitted:
            continue
        relative = path.relative_to(FIXTURE)
        if any(part in ("Methods", "ObjectMethods", "Components", "Macros") for part in relative.parts):
            continue
        data = path.read_bytes()
        if path.suffix.lower() in (".4dform", ".json"):
            value = json.loads(data.decode("utf-8-sig"))

            def clean(item):
                if isinstance(item, list):
                    return [clean(v) for v in item]
                if isinstance(item, dict):
                    return {k: clean(v) for k, v in item.items() if k not in {
                        "method", "events", "action", "formClass", "menuBar", "shortcutKey", "shortcutModifiers"
                    } and not k.lower().endswith("source") and "formula" not in k.lower()}
                return item
            sanitized = clean(value)
            if sanitized != value:
                data = (json.dumps(sanitized, ensure_ascii=False, indent=2) + "\n").encode()
        target = project / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        sources.append({"path": str(relative), "fixtureSHA256": hashlib.sha256(path.read_bytes()).hexdigest(),
                        "nativeSHA256": hashlib.sha256(data).hexdigest()})
    write(project / "Project/FormBenchmark.4DProject", {"compatibilityVersion": 2100, "tokenizedText": False})
    write(project / "Project/Sources/dependencies.json", {"dependencies": {}})
    method = project / "Project/Sources/Methods/benchmark_capture.4dm"
    method.parent.mkdir(parents=True, exist_ok=True)
    method.write_text(CAPTURE)
    validation = subprocess.run(
        [str(ROOT / "tools/4dform/boon"), str(SCHEMA),
         *[str(p) for p in sorted(project.rglob("*.4DForm"))]],
        capture_output=True, text=True)
    (output / "schema-validation.log").write_text(validation.stdout + validation.stderr)
    write(output / "source-audit.json", {
        "copiedSources": sources, "schemaExitCode": validation.returncode,
        "authoredMethods": [str(method.relative_to(project))],
        "notes": ["Raw malformed/unsupported properties are retained as native capability evidence.",
                  "Only page1 is captured, plus inherited/shared page0. Page2 labels with missing coordinates remain source limitations.",
                  "No upstream project methods, components, events, actions, or bindings are installed.",
                  "Locale changes use SET DATABASE LOCALIZATION with *: this private database's current session only."]})
    return project


def summarize(output, project, benchmark):
    path = project / "Resources/static-native/context.json"
    context = benchmark.read_json(path) if path.exists() else {"captures": []}
    report = {"status": "incomplete", "context": context, "images": [],
              "engineVersion": (output / "engine-version.log").read_text().strip(),
              "invocation": benchmark.read_json(output / "native.log.json"),
              "methodSHA256": hashlib.sha256(
                  (project / "Project/Sources/Methods/benchmark_capture.4dm").read_bytes()).hexdigest(),
              "sourceForms": {name: benchmark.read_json(
                  project / f"Project/Sources/Forms/{name}/form.4DForm")
                  for name in ("Root", "Base", "Panel", "Grand")},
              "nativeMode": "named-static; Root loaded-offscreen/no-events is separately labeled",
              "caveats": ["Named-static ignores CSS.", "Inline object-valued detailForm fails the native schema.",
                          "Base and Panel page2 labels lack coordinates; no page2 native claim is made.",
                          "No interactive runtime events/data or locale changes to installed apps/settings are performed."]}
    for capture in context["captures"]:
        for filename in [capture["form"] + ".png"] + (
                ["Root.loaded.png"] if capture.get("loadedCompanion") else []):
            original = project / "Resources/static-native" / filename
            if not original.exists():
                continue
            from PIL import Image
            with Image.open(original) as image:
                image.load()
                size = image.size
            w, h = capture["width"], capture["height"]
            expected = (w, h) if w and h else size
            dimension_gap = False
            if w and h and (size[0] / w not in (1, 2, 3) or size[1] != h * size[0] / w):
                # A named inherited form may use a wider ancestor canvas than
                # FORM GET PROPERTIES. Keep its actual geometry; never fit it.
                expected = size
                dimension_gap = True
            try:
                image, info = benchmark.verified_image(original, expected)
                target = output / "images" / filename
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(original, target.with_name(target.stem + ".raw.png"))
                image.save(target)
                report["images"].append({"file": str(target.relative_to(output)), "form": capture["form"],
                                         "mode": "loaded-offscreen-no-events" if ".loaded." in filename else "named-static",
                                         "formPropertiesSize": [w, h],
                                         "dimensionMismatch": dimension_gap,
                                         "geometryComparable": not dimension_gap,
                                         "sizeInference": "native FORM GET PROPERTIES" if w and h else
                                         "PNG decoded size; missing declared/native dimensions, logical scale unverified",
                                         **info})
                if dimension_gap:
                    report["images"][-1]["sizeInference"] = (
                        "Actual decoded PNG canvas retained; not rescaled to FORM GET PROPERTIES. "
                        "1x inferred from unchanged height and the other 1x captures."
                    )
            except RuntimeError as error:
                report["images"].append({"file": filename, "form": capture["form"],
                                         "mode": capture["mode"], "status": "incomplete", "error": str(error)})
    report["status"] = "complete" if (
        len(report["images"]) == 4
        and all("error" not in image for image in report["images"])
        and report["invocation"]["exitCode"] == 0
        and not report["invocation"]["timedOut"]
    ) else "incomplete"
    write(output / "report.json", report)
    gallery = ['<!doctype html><meta charset="utf-8"><title>Static forms native reference</title>',
               '<style>body{font:14px system-ui;margin:24px}img{display:block;border:1px solid #888}</style>',
               f'<h1>Static forms: {report["status"]}</h1><a href="report.json">Report/getters</a>',
               '<p>Raw source/schema caveats retained; named and loaded modes are not interchangeable.</p>']
    for image in report["images"]:
        if "error" in image:
            gallery.append(f'<p>{html.escape(image["error"])}</p>')
            continue
        gallery.append(f'<h2>{html.escape(image["form"] + " — " + image["mode"])}</h2>'
                       f'<img src="{html.escape(image["file"])}">')
    (output / "gallery.html").write_text("\n".join(gallery))
    return report


class CanvasParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.sizes = []
        self.themes = []

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if "form-appearance" in values.get("class", "").split():
            self.themes.append(values["data-theme"])
        if tag == "svg" and values.get("role") == "img":
            viewbox = values.get("viewbox", values.get("viewBox", "")).split()
            if len(viewbox) == 4:
                self.sizes.append((int(float(viewbox[2])), int(float(viewbox[3]))))


def compare_previews(output, project, executable, benchmark):
    """Compare cached named references on shared geometry, never fit native PNGs."""
    from PIL import Image, ImageChops, ImageDraw
    candidate = output / "fourdql-static-candidate"
    shutil.copy2(executable.resolve(), candidate)
    snapshot = output / "form-static-snapshot"
    benchmark.run(["swiftc", ROOT / "scripts/form-benchmark-snapshot.swift", "-o", snapshot,
                   "-framework", "AppKit", "-framework", "WebKit"], output / "snapshot-compile.log", 120)
    report = {"status": "incomplete", "rendererSource": str(executable.resolve()),
              "rendererSHA256": hashlib.sha256(candidate.read_bytes()).hexdigest(),
              "mode": "named-static; CSS/loaded/inline-invalid cases are not equivalent",
              "cases": []}
    for name in ("Root", "Base", "Panel"):
        directory = output / "comparison" / name
        directory.mkdir(parents=True, exist_ok=True)
        try:
            result = subprocess.run([str(candidate), "--html",
                                     str(project / f"Project/Sources/Forms/{name}/form.4DForm")],
                                    capture_output=True, timeout=60)
            (directory / "renderer.log").write_bytes(result.stderr)
            if result.returncode or b"<script" in result.stdout.lower():
                raise RuntimeError("Renderer failed or generated an unexpected script")
            html_path = directory / "preview.html"
            html_path.write_bytes(result.stdout)
            parser = CanvasParser()
            parser.feed(result.stdout.decode())
            if not parser.sizes:
                raise RuntimeError("No root SVG role=img viewBox found")
            preview_size = parser.sizes[0]
            theme = "glassLight" if "glassLight" in parser.themes else "glassDark"
            benchmark.run([snapshot, html_path, directory / "preview-raw.png", theme, 1,
                           *preview_size], directory / "snapshot.log", 35)
            preview, _ = benchmark.verified_image(directory / "preview-raw.png", preview_size)
            preview.save(directory / "preview.png")
            with Image.open(output / "images" / (name + ".png")) as source:
                native = source.convert("RGBA")
            common = (min(native.width, preview.width), min(native.height, preview.height))
            native_crop, preview_crop = native.crop((0, 0, *common)), preview.crop((0, 0, *common))
            nbg, pbg = benchmark.background_color(native_crop), benchmark.background_color(preview_crop)
            values, difference = benchmark.measure(
                benchmark.opaque(native_crop, nbg), benchmark.opaque(preview_crop, pbg), nbg, pbg)
            Image.blend(native_crop, preview_crop, 0.5).save(directory / "overlay.png")
            benchmark.heatmap(difference).save(directory / "difference.png")
            regions = []
            if name == "Root":
                for label, bounds, excluded in [
                    ("inherited-layering", (0, 0, 150, 46), []),
                    ("panel", (100, 50, 220, 130), [(110, 70, 160, 100)]),
                    ("again", (300, 50, 420, 130), [(310, 70, 360, 100)]),
                    ("panel-background", (100, 50, 200, 70), []),
                    ("panel-picture", (100, 80, 220, 120), [(110, 80, 160, 100)]),
                    ("explicit", (20, 160, 110, 180), []),
                    ("automatic", (20, 200, 200, 220), []),
                ]:
                    n, p = native.crop(bounds), preview.crop(bounds)
                    folder = directory / "regions" / label
                    folder.mkdir(parents=True, exist_ok=True)
                    n.save(folder / "native.png")
                    p.save(folder / "preview.png")
                    for image in (n, p):
                        draw = ImageDraw.Draw(image)
                        for x, y, right, bottom in excluded:
                            draw.rectangle((x - bounds[0], y - bounds[1],
                                            right - bounds[0] - 1, bottom - bounds[1] - 1),
                                           fill=(255, 255, 255, 255))
                    nm, pm = benchmark.opaque(n, (255, 255, 255)), benchmark.opaque(p, (255, 255, 255))
                    region_metrics, region_difference = benchmark.measure(
                        nm, pm, (255, 255, 255), (255, 255, 255), bounds[:2])
                    Image.blend(n, p, 0.5).save(folder / "overlay-excluded.png")
                    benchmark.heatmap(region_difference).save(folder / "difference-excluded.png")
                    color_masks = {}
                    for mode, image in [("native", nm), ("preview", pm)]:
                        channels = ImageChops.difference(
                            image, Image.new("RGB", image.size, (171, 205, 239))).split()
                        blue = ImageChops.lighter(ImageChops.lighter(channels[0], channels[1]), channels[2])
                        color_masks[mode] = benchmark.bbox_global(
                            blue.point(lambda value: 255 if value <= 5 else 0), bounds[:2])
                    regions.append({"name": label, "bounds": list(bounds),
                                    "excludedInvalidInlineBounds": excluded,
                                    "metrics": region_metrics, "blueTileBounds": color_masks,
                                    "artifacts": str(folder.relative_to(output))})
            report["cases"].append({
                "form": name, "status": "verified-common-area", "nativeSize": list(native.size),
                "previewTheme": theme,
                "namedThemeComparable": theme == "glassLight",
                "previewSize": list(preview.size), "commonAreaSize": list(common),
                "geometryMatches": native.size == preview.size, "metrics": values,
                "regions": regions,
                "caveats": ["Native canvas is not resized. Metrics cover only the common top-left region.",
                            "Named capture ignores CSS; CSS differences are context, not renderer error.",
                            "Invalid object-valued detailForm cannot be ranked as native-equivalent."]})
        except (RuntimeError, OSError, ValueError, subprocess.TimeoutExpired) as error:
            report["cases"].append({"form": name, "status": "incomplete", "error": str(error)})
            print(f"INCOMPLETE {name}: {error}", file=sys.stderr)
    report["status"] = "complete-common-area" if all(
        case["status"] == "verified-common-area" for case in report["cases"]) else "incomplete"
    write(output / "preview-comparison.json", report)
    gallery = ['<!doctype html><meta charset="utf-8"><title>Static cached comparison</title>',
               '<style>body{font:14px system-ui;margin:24px}section{margin-bottom:24px}'
               'img{border:1px solid #ccc}figure{display:inline-block;vertical-align:top}</style>',
               '<h1>Cached native versus preview</h1><a href="preview-comparison.json">Metrics</a>',
               '<p>Native geometry is never rescaled. CSS, forced-dark Base, and invalid inline subforms are context gaps.</p>']
    for case in report["cases"]:
        gallery.append(f'<section><h2>{case["form"]}</h2>')
        if case["status"] == "incomplete":
            gallery.append(f'<p>{html.escape(case["error"])}</p></section>')
            continue
        for region in case["regions"]:
            gallery.append(f'<h3>{region["name"]}; foreground error '
                           f'{region["metrics"]["foregroundMeanAbsoluteRGBError"]}; '
                           f'invalid inline excluded: {region["excludedInvalidInlineBounds"]}</h3>')
            for filename in ("native.png", "preview.png", "overlay-excluded.png", "difference-excluded.png"):
                gallery.append(f'<figure><figcaption>{filename}</figcaption>'
                               f'<img src="{region["artifacts"]}/{filename}"></figure>')
        gallery.append('</section>')
    (output / "comparison-gallery.html").write_text("\n".join(gallery))
    print(f'{report["status"]}: {output / "preview-comparison.json"}')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--summarize-only", action="store_true")
    parser.add_argument("--compare-only", action="store_true",
                        help="Reuse cached native PNGs; requires --fourdql and never launches 4D")
    parser.add_argument("--fourdql", type=Path, help="Optional renderer for cached comparisons after the parent builds it")
    args = parser.parse_args()
    output = args.output.expanduser().resolve()
    if output == ROOT or ROOT in output.parents or "tmp" in output.parts:
        parser.error("Use a private session artifact output outside the repository and temporary directories")
    output.mkdir(parents=True, exist_ok=True)
    benchmark = benchmark_module()
    if args.compare_only and not args.fourdql:
        parser.error("--compare-only requires --fourdql")
    project = output / "project" if args.summarize_only or args.compare_only else prepare(output)
    failure = None
    if not args.summarize_only and not args.compare_only:
        assert benchmark.read_json(project / "Project/Sources/dependencies.json") == {"dependencies": {}}
        benchmark.run([ENGINE, "--version"], output / "engine-version.log", 90)
        try:
            benchmark.run([ENGINE, f"--project={project / 'Project/FormBenchmark.4DProject'}",
                           "--dataless", "--skip-onstartup", "--startup-method=benchmark_capture"],
                          output / "native.log", 90)
        except RuntimeError as error:
            failure = str(error)
    report = summarize(output, project, benchmark)
    if failure:
        report["status"] = "incomplete"
        report["captureFailure"] = failure
        write(output / "report.json", report)
    if args.fourdql:
        comparison = compare_previews(output, project, args.fourdql, benchmark)
        if comparison["status"] == "incomplete":
            return 1
    print(f'{report["status"]}: {output / "gallery.html"}')
    return 0 if report["status"] == "complete" else 1


if __name__ == "__main__":
    sys.dont_write_bytecode = True
    sys.exit(main())
