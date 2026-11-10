#!/usr/bin/env python3
"""Capture genuine fourdql --html pages using macOS WebKit.

Run from the repository root:
  python3 scripts/make-cli-screenshots.py --scratch SESSION_FILES/cli-gallery
Add --only form (or another manifest stem) to reproduce an individual image.
Only PNGs are generated in docs/images/cli, alongside its source manifest.json;
HTML, executables and per-run validation metadata stay in scratch.
No browser CSS, page content, controls, or source output is modified.
"""
import argparse
import json
from pathlib import Path
import struct
import subprocess
import sys
import zlib

ROOT = Path(__file__).resolve().parent.parent


def verify_png(path, width, height):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"Not PNG: {path}")
    dimensions = struct.unpack(">II", data[16:24])
    if dimensions != (width, height):
        raise ValueError(f"Unexpected dimensions: {path}: {dimensions}")
    compressed = bytearray()
    offset = 8
    while offset < len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        kind = data[offset + 4:offset + 8]
        payload = data[offset + 8:offset + 8 + length]
        crc = struct.unpack(">I", data[offset + 8 + length:offset + 12 + length])[0]
        if zlib.crc32(kind + payload) & 0xFFFFFFFF != crc:
            raise ValueError(f"PNG checksum mismatch: {path}")
        if kind == b"IDAT":
            compressed.extend(payload)
        offset += length + 12
    pixels = zlib.decompress(compressed)
    if len(set(pixels)) < 32 or len(compressed) < 4000:
        raise ValueError(f"Apparently blank PNG: {path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scratch", type=Path, required=True, help="Persistent session files directory, not /tmp")
    parser.add_argument("--cli", type=Path, default=ROOT / ".build/debug/fourdql")
    parser.add_argument("--only", help="One screenshot stem from the manifest")
    args = parser.parse_args()
    scratch = args.scratch.resolve()
    if str(scratch).startswith(("/tmp/", "/private/tmp/", "/var/tmp/", "/private/var/tmp/")):
        parser.error("Use a persistent session files directory")
    scratch.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((ROOT / "docs/images/cli/manifest.json").read_text())
    captures = manifest["captures"]
    if len(captures) != 16 or len({c["stem"] for c in captures}) != 16:
        raise ValueError("Expected exactly 16 unique registered types")
    if args.only:
        captures = [c for c in captures if c["stem"] == args.only]
        if not captures:
            parser.error("Unknown --only stem")
    subprocess.run([sys.executable, str(ROOT / "scripts/make-cli-structure.py"),
                    str(ROOT / "docs/examples/cli/synthetic-structure.4DB")], check=True)
    helper = scratch / "cli-snapshot"
    subprocess.run(["swiftc", str(ROOT / "scripts/cli-snapshot.swift"), "-o", str(helper)], check=True)
    output = ROOT / "docs/images/cli"
    output.mkdir(parents=True, exist_ok=True)
    results = []
    for capture in captures:
        source = ROOT / capture["input"]
        html = subprocess.check_output([str(args.cli.resolve()), "--html", str(source)])
        if b"No preview available" in html or b"Problem report" in html:
            raise ValueError(f"Failure report for {source}")
        page = scratch / (capture["stem"] + ".html")
        page.write_bytes(html)
        png = ROOT / capture["screenshot"]
        if png.parent != output or png.name != capture["stem"] + ".png":
            raise ValueError(f"Unexpected screenshot path: {png}")
        result = subprocess.check_output([str(helper), str(page), str(png),
                                          str(capture["width"]), str(capture["height"])], text=True)
        verify_png(png, capture["width"], capture["height"])
        results.append({**capture, "screenshot": str(png.relative_to(ROOT)), "webkit": json.loads(result)})
        print(f'{capture["stem"]}: {capture["width"]}x{capture["height"]} OK', flush=True)
    (scratch / "results.json").write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    main()
