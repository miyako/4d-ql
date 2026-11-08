#!/usr/bin/env python3
"""Authored R5 saved-padding/alignment probe; no third-party callbacks or code."""

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def prepare(project):
    if project.exists():
        return
    pages = [{"objects": {}}, {"objects": {}}, {"objects": {}}, {"objects": {}}]
    variants = [
        ("omitted", {}),
        ("zero", dict(paddingLeft=0, paddingRight=0, paddingTop=0, paddingBottom=0)),
        ("left10", dict(paddingLeft=10)),
        ("top9bottom4", dict(paddingTop=9, paddingBottom=4)),
        ("all10", dict(paddingLeft=10, paddingRight=10, paddingTop=10, paddingBottom=10)),
    ]
    for row, (variant, padding) in enumerate(variants):
        for col, (kind, alignment) in enumerate([
            ("text", "top"), ("input", "top"), ("text", "middle"), ("input", "middle")
        ]):
            name = f"{kind}_{alignment}_{variant}"
            obj = dict(type=kind, left=20 + col * 220, top=40 + row * 104,
                       width=180, height=64, fontFamily="Arial", fontSize=13,
                       stroke="#000000", fill="#ffffff", borderStyle="solid",
                       borderColor="#c0c0c0", borderRadius=0, textAlign="left",
                       verticalAlign=alignment, **padding)
            if kind == "text":
                obj["text"] = "Hgj"
            else:
                obj.update(dataSource="Hgj", multiline="no")
            pages[1]["objects"][name] = obj
    for row, size in enumerate([13, 15]):
        for col, alignment in enumerate(["top", "middle", "bottom"]):
            for padded in [False, True]:
                name = f"textCR_{size}_{alignment}_{'padded' if padded else 'zero'}"
                pages[2]["objects"][name] = dict(
                    type="text", text="Hgj\r\rHgj", left=20 + col * 290,
                    top=40 + row * 260 + int(padded) * 116, width=250, height=94,
                    fontFamily="Arial", fontSize=size, stroke="#000000",
                    fill="#ffffff", borderStyle="solid", borderColor="#c0c0c0",
                    borderRadius=0, textAlign="left", verticalAlign=alignment,
                    paddingLeft=10 if padded else 0, paddingRight=7 if padded else 0,
                    paddingTop=9 if padded else 0, paddingBottom=15 if padded else 0)
    for row, (variant, padding) in enumerate(
            [variants[0], variants[1], variants[2], variants[4]]):
        for col, (style, multiline) in enumerate([
            ("default", "no"), ("solid4", "no"), ("default", "yes"), ("solid4", "yes")
        ]):
            obj = dict(type="input", dataSource="Hgj", left=20 + col * 220,
                       top=40 + row * 130, width=180, height=64,
                       fontFamily="Arial", fontSize=13, stroke="#000000",
                       fill="#ffffff", textAlign="left", verticalAlign="middle",
                       multiline=multiline, **padding)
            if style == "solid4":
                obj.update(borderStyle="solid", borderRadius=4, borderColor="#c0c0c0")
            pages[3]["objects"][f"input_{style}_{multiline}_{variant}"] = obj
    form = {"$4d": {"version": "1", "kind": "form"}, "destination": "detailScreen",
            "width": 900, "height": 600, "pages": pages}
    for name in ["PaddingProbe", "PaddingProbe_LoadedSafe"]:
        write(project / f"Project/Sources/Forms/{name}/form.4DForm", form)
    write(project / "Project/FormBenchmark.4DProject",
          {"compatibilityVersion": 2100, "tokenizedText": False})
    write(project / "Project/Sources/dependencies.json", {"dependencies": {}})
    write(project / "Project/Sources/Forms/BenchmarkTheme/form.4DForm", {
        "$4d": {"version": "1", "kind": "form"}, "destination": "detailScreen",
        "width": 40, "height": 40, "pages": [{"objects": {}}, {"objects": {
            "theme": dict(type="text", left=0, top=0, width=40, height=20,
                          text="Theme", fontSize=11)}}]})
    write(project / "benchmark.json", {
        "declarativeOnly": True, "title": "Authored R5 padding and paragraph alignment",
        "forms": ["PaddingProbe"], "pages": [1, 2, 3], "themes": ["glassLight", "glassDark"],
        "noncomparableObjects": {}, "context": [
            "Only authored methods and bindings run. Hgj is an authored process variable with the identical string value Hgj.",
            "Named-static and loaded-offscreen/no-events PNGs are separate modes.",
            "Text/input saved padding and verticalAlign require 21 R5; no Classic LTS equivalence is claimed.",
            "Black ink bounds are measured inside each declared object; grey borders are excluded.",
        ]})
    spec = importlib.util.spec_from_file_location("hdi", ROOT / "scripts/form-hdi-benchmark.py")
    hdi = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(hdi)
    names = {str(i): list(page["objects"]) for i, page in enumerate(pages)}
    literal = json.dumps(json.dumps(names))
    getters = f"""    var $names : Object
    $names:=JSON Parse({literal})
    var $object : Text
    $context.objects:=New collection
    For each ($object; $names[String($page)])
        $context.objects.push({{name: $object; padding: OBJECT Get padding(*; $object); verticalAlignment: OBJECT Get vertical alignment(*; $object); font: OBJECT Get font(*; $object); fontSize: OBJECT Get font size(*; $object)}})
    End for each
"""
    method = hdi.CAPTURE.replace(
        "var $param : Text", 'var Hgj : Text\nHgj:="Hgj"\nvar $param : Text'
    ).replace("    FORM SCREENSHOT($picture)", getters + "    FORM SCREENSHOT($picture)")
    path = project / "Project/Sources/Methods/benchmark_capture.4dm"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(method)


def ink(image, obj):
    x, y, w, h = (obj[key] for key in ("left", "top", "width", "height"))
    crop = image.convert("RGB").crop((x + 1, y + 1, x + w - 1, y + h - 1))
    from PIL import ImageChops
    r, g, b = crop.split()
    mask = ImageChops.lighter(ImageChops.lighter(r, g), b).point(
        lambda p: 255 if p < 120 else 0)
    bbox = mask.getbbox()
    bounds = [bbox[0] + x + 1, bbox[1] + y + 1,
              bbox[2] + x + 1, bbox[3] + y + 1] if bbox else None
    rows = [j + y + 1 for j in range(mask.height)
            if mask.crop((0, j, mask.width, j + 1)).getbbox()]
    bands = []
    for j in rows:
        if not bands or j > bands[-1][1]:
            bands.append([j, j + 1])
        else:
            bands[-1][1] = j + 1
    return {"bounds": bounds, "relativeBounds": [
        bounds[0] - x, bounds[1] - y, bounds[2] - x, bounds[3] - y
    ] if bounds else None, "rowBands": bands}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--fourdql", type=Path, default=ROOT / ".build/debug/fourdql")
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--compare-only", action="store_true")
    args = parser.parse_args()
    output = args.output.expanduser().resolve()
    if output == ROOT or ROOT in output.parents or "tmp" in output.parts:
        parser.error("Probe output must be in private session artifacts, not the repository")
    project = output / "project"
    prepare(project)
    if args.prepare_only:
        return 0
    command = [sys.executable, str(ROOT / "scripts/form-benchmark.py"),
               "--project", str(project), "--output", str(output / "comparison"),
               "--fourdql", str(args.fourdql.resolve()), "--schema",
               "/Applications/4D 21 R5/4D.app/Contents/Resources/JSONSchemas/formsSchema.json"]
    command.append("--compare-only" if args.compare_only else "--native-loaded-companion")
    result = subprocess.run(command)
    if result.returncode:
        return result.returncode
    spec = importlib.util.spec_from_file_location("benchmark", ROOT / "scripts/form-benchmark.py")
    benchmark = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(benchmark)
    form = benchmark.read_json(project / "Project/Sources/Forms/PaddingProbe/form.4DForm")
    cache = benchmark.read_json(output / "comparison/native-cache.json")
    metrics = benchmark.read_json(output / "comparison/metrics.json")
    report = {"status": "complete", "blackInkThreshold": "all RGB channels <120",
              "nativeMode": "named-static; loaded-offscreen-no-events reported separately",
              "rendererSHA256": metrics["rendererSHA256"],
              "rendererSource": metrics["rendererSource"],
              "nativeInvocations": [capture["invocation"] for capture in cache["captures"].values()],
              "context": [
                  "Input/text defaults and zero padding report zero on all four sides.",
                  "Named-static saved alignment is distinct from loaded-offscreen input placement.",
                  "Glyph bounds use a black-ink threshold, not widget coordinates or a pass threshold.",
                  "Arial paragraph advances must not be generalized to Helvetica or automatic fonts.",
              ],
              "cases": []}
    for key, capture in cache["captures"].items():
        directory = output / "comparison" / key
        context = capture["context"]
        images = {}
        for mode, filename in [("named", "native-raw.png"), ("loaded", "native-loaded-raw.png"),
                               ("preview", "preview-raw.png")]:
            if mode == "loaded" and hashlib.sha256(
                    (directory / filename).read_bytes()).hexdigest() != context["loadedCompanionImage"]["sha256"]:
                raise RuntimeError(f"Loaded companion cache image hash mismatch: {directory}")
            images[mode], _ = benchmark.verified_image(directory / filename, (900, 600))
        objects = []
        getters = {item["name"]: item for item in context["objects"]}
        for name, obj in form["pages"][context["page"]]["objects"].items():
            objects.append({"name": name, "sourceProperties": obj, "getters": getters[name],
                            **{mode: ink(image, obj) for mode, image in images.items()}})
        report["cases"].append({"key": key, "objects": objects})
    write(output / "ink-and-padding.json", report)
    print(f"Padding/getter report: {output / 'ink-and-padding.json'}")
    return 0


if __name__ == "__main__":
    sys.dont_write_bytecode = True
    sys.exit(main())
