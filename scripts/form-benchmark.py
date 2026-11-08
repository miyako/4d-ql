#!/usr/bin/env python3
"""Self-authored .4DForm visual benchmark (macOS, full 4D + WebKit + Pillow).

Capture and compare:
  python3 scripts/form-benchmark.py --output /absolute/session-artifacts/form-benchmark
After rebuilding build/fourdql, retain native captures:
  python3 scripts/form-benchmark.py --output /absolute/session-artifacts/form-benchmark --compare-only
Quick corpus validation (no engines or compiler):
  python3 scripts/form-benchmark.py --validate-only

No pass threshold is asserted. A complete run means verified capture coverage,
not visual equivalence. Native named screenshots ignore CSS; affected objects
are labeled and excluded from comparable rankings. The gallery keeps them visible.
The corpus remains compatibilityVersion 2000. Writable engine copies use 2100
(21 LTS compatible) to avoid 4D 21's legacy-component migration prompt. Only this
project metadata changes; the forms, references and resources stay byte-identical.
"""

import argparse
from collections import Counter
import hashlib
import html
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

from PIL import Image, ImageChops, ImageStat

ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "Tests/FourDFileKitTests/Fixtures/FormBenchmarkProject"
DEFAULT_SCHEMA = Path("/Applications/4D 21 R4/4D.app/Contents/Resources/JSONSchemas/formsSchema.json")
ENGINES = {
    "classic": "/Applications/4D 21.2/4D.app/Contents/MacOS/4D",
    "glass": "/Applications/4D 21 R5/4D.app/Contents/MacOS/4D",
}


def read_json(path):
    return json.loads(path.read_text())


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def digest_files(root):
    digest = hashlib.sha256()
    for path in sorted(root.rglob("*")):
        if path.is_file():
            digest.update(str(path.relative_to(root)).encode())
            digest.update(path.read_bytes())
    return digest.hexdigest()


def run(command, log, timeout=60):
    """Retain exit status and kill only the child PID created by this call."""
    log.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    with log.open("wb") as stream:
        child = subprocess.Popen([str(x) for x in command], stdout=stream, stderr=subprocess.STDOUT)
        timed_out = False
        try:
            code = child.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            child.terminate()
            try:
                code = child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                code = child.wait()
    result = {"command": [str(x) for x in command], "pid": child.pid, "exitCode": code,
              "timedOut": timed_out, "seconds": round(time.monotonic() - started, 3),
              "log": str(log)}
    write_json(log.with_suffix(log.suffix + ".json"), result)
    if code or timed_out:
        raise RuntimeError(f"Command failed (exit {code}, timeout {timed_out}): {log}")
    return result


def resolved_object(obj, form_dir):
    ref = obj.get("$ref")
    if not ref:
        return dict(obj)
    filename, fragment = ref.split("#", 1)
    value = read_json(form_dir / filename)
    for component in fragment.lstrip("/").split("/"):
        value = value[component.replace("~1", "/").replace("~0", "~")]
    return {**resolved_object(value, form_dir), **{k: v for k, v in obj.items() if k != "$ref"}}


def validate(args, manifest):
    project = read_json(CORPUS / "Project/FormBenchmark.4DProject")
    assert project["compatibilityVersion"] == 2000 and project["tokenizedText"] is False
    assert read_json(CORPUS / "Project/Sources/dependencies.json") == {"dependencies": {}}
    forms = {}
    for name in manifest["forms"]:
        path = CORPUS / f"Project/Sources/Forms/{name}/form.4DForm"
        form = read_json(path)
        assert len(form["pages"]) == 3, f"{name}: expected shared page 0 plus pages 1 and 2"
        for page in form["pages"]:
            for obj in page["objects"].values():
                resolved_object(obj, path.parent)
        forms[name] = (path, form)
    # The public schema permits $ref extension keys but does not itself resolve
    # 4D's external object templates; resolve and validate those separately below.
    command = [args.validator, args.schema, *[path for path, _ in forms.values()]]
    result = subprocess.run([str(x) for x in command], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError("Form schema validation failed:\n" + result.stdout + result.stderr)
    for path, form in forms.values():
        expanded = json.loads(json.dumps(form))
        for page in expanded["pages"]:
            page["objects"] = {name: resolved_object(obj, path.parent) for name, obj in page["objects"].items()}
        scratch = ROOT / f"scripts/.form-benchmark-expanded-{os.getpid()}.json"
        try:
            write_json(scratch, expanded)
            result = subprocess.run([str(args.validator), str(args.schema), str(scratch)],
                                    capture_output=True, text=True)
        finally:
            scratch.unlink(missing_ok=True)
        if result.returncode:
            raise RuntimeError(f"Expanded form schema validation failed ({path}):\n" + result.stdout + result.stderr)
    print(f"Schema verified: {len(forms)} forms; dependencies and JSON pointers verified.", flush=True)
    return forms


def verified_image(path, expected):
    with Image.open(path) as image:
        image.load()
        w, h = image.size
        scale = w / expected[0]
        if scale not in (1, 2, 3) or h != expected[1] * scale:
            raise RuntimeError(f"{path}: {image.size}, expected {expected} points at integer backing scale")
        if not ImageChops.difference(image.convert("RGB"), Image.new("RGB", image.size, image.getpixel((0, 0))[:3])).getbbox():
            raise RuntimeError(f"{path}: blank decoded capture")
        rgba = image.convert("RGBA")
        if rgba.getchannel("A").getbbox() is None:
            raise RuntimeError(f"{path}: fully transparent decoded capture")
        if scale != 1:
            # Only normalize known integer backing scale, never fit/crop geometry.
            rgba = rgba.resize(expected, Image.Resampling.LANCZOS)
        return rgba, {"rawPixelSize": [w, h], "logicalSize": list(expected), "backingScale": scale,
                      "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def opaque(image, background):
    return Image.alpha_composite(Image.new("RGBA", image.size, (*background, 255)), image).convert("RGB")


def background_color(image):
    colors = Counter(image.get_flattened_data() if hasattr(image, "get_flattened_data") else image.getdata())
    opaque_colors = [(count, color[:3]) for color, count in colors.items() if color[3] == 255]
    if not opaque_colors:
        return (255, 255, 255)
    return max(opaque_colors)[1]


def mask(image, background):
    d = ImageChops.difference(image, Image.new("RGB", image.size, background))
    r, g, b = d.split()
    # 12/255 is foreground segmentation tolerance, NOT an acceptance threshold.
    return ImageChops.lighter(ImageChops.lighter(r, g), b).point(lambda p: 255 if p > 12 else 0)


def bbox_global(mask_image, origin):
    box = mask_image.getbbox()
    return [box[0] + origin[0], box[1] + origin[1], box[2] + origin[0], box[3] + origin[1]] if box else None


def measure(native, preview, native_background, preview_background, origin=(0, 0)):
    nmask, pmask = mask(native, native_background), mask(preview, preview_background)
    union, intersection = ImageChops.lighter(nmask, pmask), ImageChops.darker(nmask, pmask)
    pixels = union.histogram()[255]
    difference = ImageChops.difference(native, preview)
    a, b = bbox_global(nmask, origin), bbox_global(pmask, origin)
    values = {
        "meanAbsoluteRGBError": round(sum(ImageStat.Stat(difference).mean) / (3 * 255), 6),
        "foregroundMeanAbsoluteRGBError": round(sum(ImageStat.Stat(difference, union).mean) / (3 * 255), 6) if pixels else None,
        "foregroundPixels": pixels,
        "foregroundMaskIoU": round(intersection.histogram()[255] / pixels, 6) if pixels else None,
        "nativeForegroundBounds": a, "previewForegroundBounds": b,
        "boundsDeltaPreviewMinusNative": [b[i] - a[i] for i in range(4)] if a and b else None,
        "boundsStatus": "both" if a and b else "native-only" if a else "preview-only" if b else "empty",
    }
    return values, difference


def heatmap(difference):
    r, g, b = difference.split()
    intensity = ImageChops.lighter(ImageChops.lighter(r, g), b)
    return Image.merge("RGB", (intensity, intensity.point(lambda p: max(0, p * 2 - 255)),
                              Image.new("L", difference.size, 0)))


def crop_objects(form, form_dir, page):
    objects = {**form["pages"][0]["objects"], **form["pages"][page]["objects"]}
    result = {}
    for name, source in objects.items():
        obj = resolved_object(source, form_dir)
        if obj.get("visibility") == "hidden":
            continue
        x, y = obj["left"], obj["top"]
        w = obj.get("width", obj.get("right", x + 100) - x)
        # The crop includes omitted-height defaults without asserting their value.
        h = obj.get("height", obj.get("bottom", y + 40) - y)
        padding = 2 if obj["type"] == "text" else 8 if obj["type"] == "picture" else 14
        result[name] = (obj, [max(0, x - padding), max(0, y - padding),
                              min(form["width"], x + w + padding), min(form["height"], y + h + padding)])
        if obj["type"] == "groupBox":
            region = {"type": "groupBoxTitle", "left": x + 8, "top": y - 8,
                      "width": min(224, max(0, w - 16)), "height": 32, "parentObject": name}
            result[name + ".title"] = (region, [
                max(0, region["left"]), max(0, region["top"]),
                min(form["width"], region["left"] + region["width"]),
                min(form["height"], region["top"] + region["height"])])
        if obj["type"] == "listbox":
            offset = 0
            for index, column in enumerate(obj.get("columns", [])):
                column_width = min(column.get("width", 100), max(0, w - offset))
                for part, enabled, default_height in [
                    ("header", obj.get("showHeaders", True), 24),
                    ("footer", obj.get("showFooters", False), 24),
                ]:
                    if not enabled or not column_width:
                        continue
                    spec = column.get(part, {})
                    region_height = int(str(obj.get(part + "Height", default_height)).removesuffix("px"))
                    region_y = y if part == "header" else y + h - region_height
                    region_name = name + "." + spec.get("name", f"{column.get('name', index)}.{part}")
                    region = {"type": "listbox" + part.title(), "left": x + offset, "top": region_y,
                              "width": column_width, "height": region_height, "parentObject": name}
                    result[region_name] = (region, [
                        max(0, region["left"] - 2), max(0, region_y - 2),
                        min(form["width"], region["left"] + column_width + 2),
                        min(form["height"], region_y + region_height + 2)])
                offset += column_width
    return result


def compare_case(case, directory, form, form_dir, manifest):
    expected = (form["width"], form["height"])
    native_rgba, native_info = verified_image(directory / "native-raw.png", expected)
    preview_rgba, preview_info = verified_image(directory / "preview-raw.png", expected)
    native_bg, preview_bg = background_color(native_rgba), background_color(preview_rgba)
    native, preview = opaque(native_rgba, native_bg), opaque(preview_rgba, preview_bg)
    native.save(directory / "native.png")
    preview.save(directory / "preview.png")
    values, difference = measure(native, preview, native_bg, preview_bg)
    difference_image = heatmap(difference)
    overlay = Image.blend(native, preview, 0.5)
    overlay.save(directory / "overlay.png")
    difference_image.save(directory / "difference.png")
    excluded = manifest["noncomparableObjects"].get(case["form"], {})
    objects = []
    for name, (obj, box) in crop_objects(form, form_dir, case["page"]).items():
        n, p = native.crop(box), preview.crop(box)
        # Text on a colored panel needs its local background, not the canvas
        # background; otherwise the panel is mistaken for the label's ink bounds.
        ink_region = obj["type"] in ("text", "listboxHeader", "listboxFooter", "groupBoxTitle")
        local_nbg = background_color(n.convert("RGBA")) if ink_region else native_bg
        local_pbg = background_color(p.convert("RGBA")) if ink_region else preview_bg
        if obj["type"] == "picture":
            # Picture crop corners are outside the declared image, including
            # pictures on colored panels; a modal color may belong to the image.
            local_nbg, local_pbg = n.getpixel((0, 0)), p.getpixel((0, 0))
        metrics, _ = measure(n, p, local_nbg, local_pbg, (box[0], box[1]))
        folder = directory / "objects" / name
        folder.mkdir(parents=True, exist_ok=True)
        for filename, image in [("native", n), ("preview", p), ("overlay", overlay.crop(box)),
                                ("difference", difference_image.crop(box))]:
            image.save(folder / f"{filename}.png")
        objects.append({"name": name, "type": obj["type"], "declaredBounds": [
            obj["left"], obj["top"], obj.get("width"), obj.get("height")],
            "parentObject": obj.get("parentObject"),
            "cropBounds": box, "comparable": name not in excluded,
            "noncomparableReason": excluded.get(name),
            "foregroundBackgroundNativeRGB": local_nbg, "foregroundBackgroundPreviewRGB": local_pbg,
            "crop": str(folder.relative_to(directory.parent.parent)), **metrics})
    return {**case, "status": "verified", "captureMode": "named-static",
            "nativeImage": native_info, "previewImage": preview_info,
            "nativeBackgroundRGB": native_bg, "previewBackgroundRGB": preview_bg,
            "canvas": values, "objects": objects,
            "hasNoncomparableObjects": any(not obj["comparable"] for obj in objects),
            "directory": str(directory.relative_to(directory.parent.parent))}


def gallery(output, results, manifest):
    esc = html.escape
    pieces = ['<!doctype html><html lang="en"><meta charset="utf-8"><title>4D form benchmark</title>',
              '<style>body{font:14px system-ui;margin:24px;background:#eee;color:#222} '
              'section{background:white;padding:16px;margin:24px 0} .images{display:flex;gap:12px;overflow:auto}'
              'figure{margin:0} figcaption{padding:5px} img{max-width:none} details{margin:12px 0} '
              'code{white-space:pre-wrap} .excluded{color:#9a4800}</style>',
              '<h1>Self-authored native vs preview .4DForm benchmark</h1>',
              f'<p>Status: <strong>{esc(results["status"])}</strong>. '
              'Capture coverage is not a visual pass. No pass thresholds are asserted.</p>',
              '<p><a href="metrics.json">metrics.json</a> · <a href="native-cache.json">native provenance</a></p>',
              '<ul>' + ''.join(f'<li>{esc(x)}</li>' for x in manifest["context"]) + '</ul>',
              '<p>All images are logical points at 1×. Heatmap intensity is maximum absolute RGB channel error; '
              'overlay is 50% alpha. Foreground is distance &gt;12/255 from each canvas modal background. '
              'Text, group-title and listbox header/footer foreground uses the crop modal background to avoid mistaking a panel for ink. '
              'Pictures use an outside-image crop corner. Bounds describe visible foreground inside declared bounds '
              '+14 pt crops (+8 pt for pictures, +2 pt for text and listbox header/footer regions), not native widget API coordinates. '
              'The group-title region is a 224×32 pt legend/top-border crop; its foreground bounds can include the border. '
              'Canvas averages include known context differences and must not be interpreted as a pass score.</p>']
    for case in results["cases"]:
        pieces.append(f'<section><h2>{esc(case["form"])} · page {case["page"]} · {esc(case["theme"])}</h2>')
        if case["status"] != "verified":
            pieces.append(f'<p>{esc(case.get("error", "Incomplete"))}</p></section>')
            continue
        directory = case["directory"]
        pieces.append('<div class="images">')
        for name in ["native", "preview", "overlay", "difference"]:
            pieces.append(f'<figure><figcaption>{name}</figcaption><img src="{directory}/{name}.png" '
                          f'width="{case["nativeImage"]["logicalSize"][0]}" height="{case["nativeImage"]["logicalSize"][1]}"></figure>')
        pieces.append('</div><h3>Object evidence (largest foreground errors first)</h3>')
        objects = sorted(case["objects"], key=lambda o: o["foregroundMeanAbsoluteRGBError"] or 0, reverse=True)
        for obj in objects:
            reason = f' — NONCOMPARABLE: {obj["noncomparableReason"]}' if not obj["comparable"] else ""
            summary = (f'{obj["name"]} ({obj["type"]}) · foreground error {obj["foregroundMeanAbsoluteRGBError"]} '
                       f'· mask IoU {obj["foregroundMaskIoU"]} · bounds Δ {obj["boundsDeltaPreviewMinusNative"]}{reason}')
            pieces.append(f'<details class="{"excluded" if reason else ""}"><summary>{esc(summary)}</summary><div class="images">')
            for name in ["native", "preview", "overlay", "difference"]:
                pieces.append(f'<figure><figcaption>{name}</figcaption><img src="{obj["crop"]}/{name}.png"></figure>')
            pieces.append('</div></details>')
        pieces.append('</section>')
    pieces.append('</html>')
    (output / "gallery.html").write_text("\n".join(pieces))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--fourdql", type=Path, default=ROOT / "build/fourdql")
    parser.add_argument("--schema", type=Path, default=DEFAULT_SCHEMA)
    parser.add_argument("--validator", type=Path, default=ROOT / "tools/4dform/boon")
    parser.add_argument("--classic-engine", type=Path, default=Path(ENGINES["classic"]))
    parser.add_argument("--glass-engine", type=Path, default=Path(ENGINES["glass"]))
    parser.add_argument("--compare-only", action="store_true")
    parser.add_argument("--validate-only", action="store_true")
    parser.add_argument("--native-project-version", type=int, choices=[2000, 2100], default=2100,
                        help="Metadata in writable engine copies only (default 2100 avoids 4D 21's migration prompt; fixtures stay 2000)")
    parser.add_argument("--forms", nargs="+", help="Subset of manifest form names")
    parser.add_argument("--themes", nargs="+", help="Subset of manifest theme names")
    args = parser.parse_args()
    manifest = read_json(CORPUS / "benchmark.json")
    forms = validate(args, manifest)
    if args.validate_only:
        return 0
    if not args.output:
        parser.error("--output is required; use a session artifact directory, not the fixture corpus")
    output = args.output.expanduser().resolve()
    if output == CORPUS or CORPUS in output.parents or any(part in ("tmp", "var/tmp") for part in output.parts):
        parser.error("Output must be outside the immutable fixture corpus and forbidden temporary directories")
    output.mkdir(parents=True, exist_ok=True)
    selected_forms = args.forms or manifest["forms"]
    themes = args.themes or manifest["themes"]
    if set(selected_forms) - set(manifest["forms"]) or set(themes) - set(manifest["themes"]):
        parser.error("Unknown form or theme")
    corpus_hash = digest_files(CORPUS)
    cases = [{"form": name, "page": page, "theme": theme} for theme in themes for name in selected_forms
             for page in range(1, len(forms[name][1]["pages"]))]
    cache_path = output / "native-cache.json"
    cache = read_json(cache_path) if cache_path.exists() else {"corpusSHA256": corpus_hash, "captures": {}}
    if cache["corpusSHA256"] != corpus_hash:
        if args.compare_only:
            raise RuntimeError("Native cache corpus hash differs; recapture without --compare-only")
        cache = {"corpusSHA256": corpus_hash, "captures": {}}
    if cache.get("nativeProjectCompatibilityVersion") != args.native_project_version:
        if args.compare_only:
            raise RuntimeError("Native cache project version differs; recapture without --compare-only")
        cache = {"corpusSHA256": corpus_hash, "captures": {}}
    cache["nativeProjectCompatibilityVersion"] = args.native_project_version
    snapshot = output / "form-benchmark-snapshot"
    run(["swiftc", ROOT / "scripts/form-benchmark-snapshot.swift", "-o", snapshot,
         "-framework", "AppKit", "-framework", "WebKit"], output / "logs/snapshot-compile.log", 120)
    engine_projects, engine_versions = {}, {}
    # The parent may rebuild fourdql while a long native run is in progress.
    # Freeze one executable per run so every preview has identical provenance.
    renderer = output / "fourdql-benchmark"
    shutil.copy2(args.fourdql.resolve(), renderer)
    results = {"status": "incomplete", "corpusSHA256": corpus_hash,
               "rendererSHA256": hashlib.sha256(renderer.read_bytes()).hexdigest(),
               "rendererSource": str(args.fourdql.resolve()),
               "nativeProjectCompatibilityVersion": args.native_project_version,
               "command": [sys.executable, *sys.argv], "mode": "named-static",
               "context": manifest["context"], "cases": []}
    for case in cases:
        key = f'{case["theme"]}/{case["form"]}-page{case["page"]}'
        directory = output / key
        directory.mkdir(parents=True, exist_ok=True)
        path, form = forms[case["form"]]
        try:
            if not args.compare_only:
                family = "glass" if case["theme"].startswith("glass") else "classic"
                if family not in engine_projects:
                    engine = args.glass_engine if family == "glass" else args.classic_engine
                    version_log = output / f"logs/{family}-version.log"
                    run([engine, "--version"], version_log)
                    engine_versions[family] = version_log.read_text().strip()
                    project = output / f"engine-projects/{family}"
                    if project.exists():
                        shutil.rmtree(project)
                    shutil.copytree(CORPUS, project)
                    # This preflight occurs before the first engine --project invocation.
                    assert read_json(project / "Project/Sources/dependencies.json") == {"dependencies": {}}
                    project_file = project / "Project/FormBenchmark.4DProject"
                    project_metadata = read_json(project_file)
                    project_metadata["compatibilityVersion"] = args.native_project_version
                    write_json(project_file, project_metadata)
                    engine_projects[family] = project
                project = engine_projects[family]
                for original in CORPUS.rglob("*"):
                    if original.is_file() and original.relative_to(CORPUS).as_posix() != "Project/FormBenchmark.4DProject":
                        if original.read_bytes() != (project / original.relative_to(CORPUS)).read_bytes():
                            raise RuntimeError(f"Native input changed from authored corpus: {original}")
                scheme = "dark" if case["theme"].endswith("Dark") else "light"
                resource_path = f'/RESOURCES/benchmark/{case["form"]}-page{case["page"]}-{scheme}.png'
                native_path = project / resource_path.replace("/RESOURCES/", "Resources/")
                native_path.unlink(missing_ok=True)
                engine = args.glass_engine if family == "glass" else args.classic_engine
                invocation = run([engine, f'--project={project / "Project/FormBenchmark.4DProject"}',
                                  "--dataless", "--skip-onstartup", "--startup-method=benchmark_capture",
                                  f'--user-param={scheme}:{case["form"]}:{case["page"]}:{resource_path}'],
                                 output / f"logs/{case['theme']}-{case['form']}-page{case['page']}.log")
                context = read_json(native_path.with_suffix(".png.json"))
                expected_theme = "LiquidGlass" if family == "glass" else "MacClassic"
                if (context["applicationScheme"] != scheme or context["loadedScheme"] != scheme or
                    context["form"] != case["form"] or context["page"] != case["page"] or
                    context["width"] != form["width"] or context["height"] != form["height"]):
                    raise RuntimeError(f"Native context does not match requested theme/scheme: {context}")
                reported_theme = context.get("loadedTheme")
                if reported_theme is not None and reported_theme != expected_theme:
                    raise RuntimeError(f"Native FORM theme differs: {context}")
                if reported_theme is None and family == "glass":
                    raise RuntimeError(f"Glass theme was not reported by the native engine: {context}")
                context["themeVerification"] = (
                    "FORM theme on loaded form (named-static command uses the same engine)"
                    if reported_theme is not None else
                    "Classic engine version provenance; FORM theme is unavailable in 21.2 LTS")
                context["requestedTheme"] = case["theme"]
                context["corpusProjectCompatibilityVersion"] = 2000
                context["nativeProjectCompatibilityVersion"] = args.native_project_version
                context["formSHA256"] = hashlib.sha256(path.read_bytes()).hexdigest()
                _, info = verified_image(native_path, (form["width"], form["height"]))
                shutil.copyfile(native_path, directory / "native-raw.png")
                cache["captures"][key] = {"context": context, "engine": str(engine),
                                          "version": engine_versions[family], "invocation": invocation, "image": info}
                write_json(cache_path, cache)
            else:
                if key not in cache["captures"]:
                    raise RuntimeError(f"Missing native cache entry: {key}")
                if hashlib.sha256((directory / "native-raw.png").read_bytes()).hexdigest() != cache["captures"][key]["image"]["sha256"]:
                    raise RuntimeError(f"Native cache image hash mismatch: {key}")
            generated = subprocess.run([str(renderer), "--html", str(path)], capture_output=True, timeout=60)
            (directory / "renderer.log").write_bytes(generated.stderr)
            if generated.returncode:
                raise RuntimeError(f"fourdql failed: {directory / 'renderer.log'}")
            if b"<script" in generated.stdout.lower():
                raise RuntimeError("Generated preview unexpectedly contains a script element")
            html_path = directory / "preview.html"
            html_path.write_bytes(generated.stdout)
            run([snapshot, html_path, directory / "preview-raw.png", case["theme"], case["page"],
                 form["width"], form["height"]], directory / "snapshot.log", 35)
            measured = compare_case(case, directory, form, path.parent, manifest)
            measured["nativeContext"] = cache["captures"][key]["context"]
            results["cases"].append(measured)
            print(f"Verified {key}", flush=True)
        except (RuntimeError, OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
            results["cases"].append({**case, "status": "incomplete", "error": str(error)})
            print(f"INCOMPLETE {key}: {error}", file=sys.stderr, flush=True)
        write_json(output / "metrics.json", results)
    complete = all(case["status"] == "verified" for case in results["cases"])
    results["status"] = "complete" if complete else "incomplete"
    results["coverage"] = {"requestedCases": len(cases),
                           "verifiedCases": sum(c["status"] == "verified" for c in results["cases"]),
                           "forms": selected_forms, "themes": themes, "pages": [1, 2]}
    ranking = [{**{k: c[k] for k in ("form", "page", "theme")}, **o}
               for c in results["cases"] if c["status"] == "verified" for o in c["objects"]
               if o["comparable"] and o["type"] not in ("rectangle", "line", "groupBox")]
    results["largestComparableDiscrepancies"] = sorted(
        ranking, key=lambda o: o["foregroundMeanAbsoluteRGBError"] or 0, reverse=True)[:40]
    write_json(output / "metrics.json", results)
    gallery(output, results, manifest)
    print(f'{results["status"]}: {results["coverage"]["verifiedCases"]}/{len(cases)} cases. '
          f'Gallery: {output / "gallery.html"}')
    return 0 if complete else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, OSError, AssertionError) as error:
        print(f"Benchmark failed: {error}", file=sys.stderr)
        sys.exit(1)
