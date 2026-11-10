#!/usr/bin/env python3
"""Generate authored XML labels and capture them using full GUI 4D (never tool4d).

  python3 scripts/label-native-probe.py --generate-only
  python3 scripts/label-native-probe.py --output build/label-native-probe

The writable project/data/logs stay in --output. Native PDF output is produced
by PRINT LABEL, not by an SVG, browser, or Quick Look rendering approximation.
"""

import argparse
import base64
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import time
import xml.etree.ElementTree as ET
import zlib

ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "Tests/FourDFileKitTests/Fixtures/LabelProject"
ENGINE = Path("/Applications/4D 21 R5/4D.app/Contents/MacOS/4D")
PDF_CAPTURE = r"""
import AppKit
import PDFKit
let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let document = PDFDocument(url: url), let page = document.page(at: 0) else {
    fatalError("Native PDF is unreadable")
}
let text = page.string ?? ""
let expected = CommandLine.arguments[4] == "form" ? ["HOST FORM REFERENCE", "ShippingLabel"] :
    ["Parcel & Co.", "Café", "東京", "Ada Example", "Code: 7", "Original embedded PNG"]
guard document.pageCount == 1, expected.allSatisfy({ text.contains($0) }) else {
    fatalError("Native PDF is blank or missing expected literal/field/formula output")
}
let image = page.thumbnail(of: NSSize(width: 1190, height: 1684), for: .mediaBox)
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(
    to: URL(fileURLWithPath: CommandLine.arguments[2]))
let result: [String: Any] = ["pages": document.pageCount, "text": text,
    "mediaBox": [page.bounds(for: .mediaBox).width, page.bounds(for: .mediaBox).height],
    "capturePixels": [bitmap.pixelsWide, bitmap.pixelsHigh],
    "captureEngine": "macOS PDFKit thumbnail, white paper, approximately 144 dpi"]
let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
"""


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def png():
    """Original 24-pixel blue/yellow checker artwork, encoded without libraries."""
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(
            ">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    pixels = b"".join(b"\0" + b"".join(
        bytes((30, 95, 180) if (x // 6 + y // 6) % 2 else (255, 195, 40))
        for x in range(24)) for y in range(24))
    return (b"\x89PNG\r\n\x1a\n" +
            chunk(b"IHDR", struct.pack(">IIBBBBB", 24, 24, 8, 2, 0, 0, 0)) +
            chunk(b"IDAT", zlib.compress(pixels)) + chunk(b"IEND", b""))


def generate():
    labels = CORPUS / "Resources/Labels"
    labels.mkdir(parents=True, exist_ok=True)
    root = ET.Element("label", {
        "columns": "2", "rows": "3", "labels-per-record": "1", "start": "1",
        "document-name": "Authored native label probe", "standard-code": "",
        "version": "2"})
    for tag, attrs in [
        ("setting", {"auto-width": "false", "landscape": "false", "vertical": "false"}),
        ("size", {"unit": "pt", "height": "179", "width": "252"}),
        ("margin", {"left": "36", "top": "36", "right": "36", "bottom": "36"}),
        ("gap", {"horizontal": "12", "vertical": "12"}),
        ("form", {"name": "", "number": "-1"}),
        ("method", {"name": "", "evaluate-per-label": "false"}),
        ("selects", {})]:
        ET.SubElement(root, tag, {"id": tag, **attrs})
    objects = ET.SubElement(root, "objects", {"id": "objects"})

    def obj(kind, ident, box, **attrs):
        # Native files store editor-matrix positions, NOT label-local positions.
        # 21R5 matrix: (237,55), 348x191; center the 252x179 label within it.
        box = [value + (285 if index % 2 == 0 else 61)
               for index, value in enumerate(box)]
        ET.SubElement(objects, "object", {
            "type": kind, "id": ident,
            **dict(zip(("left", "top", "right", "bottom"), map(str, box))),
            "field-type": "0", "font-name": "Helvetica", "font-size": "12",
            "font-color": "#163459", "style": "plain", "alignment": "left",
            "direction": "down", "preserve-aspect-ratio": "true",
            "fill-color": "none", "fill-opacity": "1",
            "stroke-color": "#163459", "stroke-opacity": "1", "stroke-width": "1",
            **{key.replace("_", "-"): str(value) for key, value in attrs.items()}})

    obj("rect", "probe-frame", (4, 4, 248, 176), fill_color="#F3F7FC")
    obj("round-rect", "probe-round", (12, 12, 168, 42),
        fill_color="#D9E7F5", rx=8, ry=8, stroke_width=2)
    obj("text", "probe-heading", (20, 17, 162, 38), value="Parcel & Co.",
        font_size=16, style="bold", stroke_width=0)
    obj("oval", "probe-oval", (182, 12, 218, 42), fill_color="#FFD36A")
    obj("line", "probe-rule", (12, 52, 240, 52), direction="down", stroke_width=2)
    obj("text", "probe-unicode", (12, 59, 234, 81),
        value="Café — 東京", stroke_width=0)
    obj("variable", "probe-field", (12, 88, 232, 108),
        value="[Parcels]Recipient", table=1, field=2, field_type=0,
        pairs=1, tableList="[1]", fieldList="[2]", stroke_width=0)
    obj("variable", "probe-formula", (12, 114, 232, 134),
        value='"Code: "+String(7)', stroke_width=0)
    image = png()
    obj("image", "probe-image", (12, 142, 36, 166),
        image_data=base64.b64encode(image).decode(),
        image_hash=hashlib.sha1(image).hexdigest(),
        image_name="authored-checker.png", image_codec=".png", stroke_width=0)
    obj("text", "probe-caption", (45, 144, 234, 166),
        value="Original embedded PNG", font_size=10, stroke_width=0)
    ET.indent(root, space="  ")
    ET.ElementTree(root).write(labels / "representative.4lbp",
                               encoding="UTF-8", xml_declaration=True)
    root.find("form").set("name", "ShippingLabel")
    root.find("form").set("number", "999")
    root.set("document-name", "Saved form reference (ShippingLabel in host project)")
    root.remove(objects)
    ET.ElementTree(root).write(labels / "saved-form-reference.4lbp",
                               encoding="UTF-8", xml_declaration=True)


def run(command, log, timeout):
    started = time.monotonic()
    with log.open("wb") as stream:
        child = subprocess.Popen([str(x) for x in command],
                                 stdout=stream, stderr=subprocess.STDOUT)
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
    return {"command": list(map(str, command)), "exitCode": code,
            "timedOut": timed_out, "seconds": round(time.monotonic() - started, 3)}


def validate_fixture():
    """Never let an automatic launch enter legacy conversion/PK Manager UI."""
    project = json.loads((CORPUS / "Project/LabelProbe.4DProject").read_text())
    if project.get("compatibilityVersion", 0) < 2100 or project.get("tokenizedText") is not False:
        raise ValueError("Only the authored modern 21+ project is permitted")
    forbidden = {".4db", ".4dc", ".4dz", ".4dd", ".4dindx", ".match"}
    for path in CORPUS.rglob("*"):
        if "References" in path.relative_to(CORPUS).parts:
            continue
        if path.is_symlink() or path.suffix.lower() in forbidden:
            raise ValueError(f"Existing binary structure/data or symlink is forbidden: {path}")
    catalog = ET.fromstring((CORPUS / "Project/Sources/catalog.4DCatalog").read_text())
    tables = catalog.findall("table")
    if catalog.tag != "base" or not tables:
        raise ValueError("The authored modern catalog must define its tables")
    for table in tables:
        key = table.find("primary_key")
        field = next((field for field in table.findall("field")
                      if key is not None and field.get("uuid") == key.get("field_uuid")), None)
        if (field is None or field.get("unique") != "true"
                or field.get("not_null") != "true"):
            raise ValueError(f"Table {table.get('name')} needs a defined unique, non-null primary key")
    return {"compatibilityVersion": project["compatibilityVersion"],
            "tablesWithPrimaryKeys": len(tables), "existingStructureOrData": False}


def validate_output(output):
    if output == CORPUS or CORPUS in output.parents or output == ROOT:
        raise ValueError("--output must not overwrite the authored corpus")
    if "tmp" in output.parts:
        raise ValueError("Temporary directories are not supported")
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise ValueError("Use a new or empty output directory; existing data must never be opened")


def validate_engine(engine):
    if (engine.name != "4D" or engine.parent.name != "MacOS"
            or engine.parent.parent.name != "Contents"
            or not engine.parent.parent.parent.name.endswith(".app")):
        raise ValueError("--engine must be the full 4D.app executable, never tool4d")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generate-only", action="store_true")
    parser.add_argument("--validate-only", action="store_true",
                        help="Check modern project, primary keys and fresh output without launching 4D")
    parser.add_argument("--output", type=Path, default=ROOT / "build/label-native-probe")
    parser.add_argument("--engine", type=Path, default=ENGINE)
    parser.add_argument("--editor", action="store_true",
                        help="Open the native wizard instead of printing; requires GUI interaction")
    parser.add_argument("--timeout", type=int, default=90)
    args = parser.parse_args()
    if args.generate_only:
        generate()
        return
    output = args.output.resolve()
    try:
        preflight = validate_fixture()
        validate_output(output)
        validate_engine(args.engine)
    except (ValueError, OSError, ET.ParseError) as error:
        parser.error(str(error))
    if args.validate_only:
        print(json.dumps(preflight, indent=2))
        return
    output.mkdir(parents=True, exist_ok=True)
    project = output / "project"
    if project.exists():
        parser.error("Use a fresh output directory to preserve evidence")
    shutil.copytree(CORPUS, project, ignore=shutil.ignore_patterns("References"))
    version = subprocess.check_output([str(args.engine), "--version"], text=True).strip()
    command = [args.engine, f"--project={project / 'Project/LabelProbe.4DProject'}",
               f"--data={output / 'LabelProbe.4DD'}", "--create-data", "--skip-onstartup",
               "--startup-method=label_probe", f"--user-param={'editor' if args.editor else 'print'}"]
    result = run(command, output / "native.log", args.timeout)
    result["preflight"] = preflight
    result["engineVersion"] = version
    result["mode"] = "editor" if args.editor else "print"
    result["inputs"] = {
        str(p.relative_to(CORPUS)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted(CORPUS.rglob("*"))
        if p.is_file() and "References" not in p.relative_to(CORPUS).parts}
    native = project / "Resources/native"
    pdf = native / "representative.pdf"
    result["verifiedPDF"] = pdf.exists() and pdf.read_bytes().startswith(b"%PDF-")
    if result["verifiedPDF"]:
        result["captures"] = {}
        for stem in ("representative", "display-unit-mm", "saved-form"):
            capture = run(["swift", "-e", PDF_CAPTURE, native / f"{stem}.pdf",
                           native / f"{stem}.png", native / f"{stem}-content.json",
                           "form" if stem == "saved-form" else "label"],
                          output / f"capture-{stem}.log", 90)
            result["captures"][stem] = capture
            if capture["exitCode"] or capture["timedOut"]:
                result["verifiedPDF"] = False
            else:
                capture["content"] = json.loads((native / f"{stem}-content.json").read_text())
        if result["verifiedPDF"]:
            result["pdfContent"] = result["captures"]["representative"]["content"]
            result["displayUnitSameRaster"] = (
                (native / "representative.png").read_bytes() ==
                (native / "display-unit-mm.png").read_bytes())
    original = ET.parse(project / "Resources/Labels/representative.4lbp").getroot()
    roundtrip = native / "representative-roundtrip.4lbp"
    result["verifiedXMLRoundtrip"] = roundtrip.exists() and (
        [(e.tag, e.attrib) for e in original.iter()] ==
        [(e.tag, e.attrib) for e in ET.parse(roundtrip).getroot().iter()])
    result["outputs"] = {
        str(p.relative_to(native)): {"bytes": p.stat().st_size,
                                     "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
        for p in sorted(native.rglob("*")) if p.is_file()}
    write_json(output / "evidence.json", result)
    print(json.dumps(result, indent=2))
    context = native / "context.json"
    complete = context.exists() and json.loads(context.read_text()).get("stage") == "complete"
    if (result["exitCode"] or result["timedOut"] or not complete
            or not result["verifiedXMLRoundtrip"]
            or (not args.editor and (not result["verifiedPDF"]
                                     or not result.get("displayUnitSameRaster")))):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
