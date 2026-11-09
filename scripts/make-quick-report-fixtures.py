#!/usr/bin/env python3
"""Generate self-authored .4qr evidence with full 4D (not tool4d)."""
import argparse
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "Tests/Fixtures/qrfixture/Project"
OUT = ROOT / "Tests/FourDFileKitTests/Fixtures/QuickReport"


def chunks(data, start=4, end=None):
    end = len(data) if end is None else end
    while start < end:
        tag = data[start:start + 4][::-1]
        size = struct.unpack_from("<I", data, start + 4)[0]
        finish = start + 8 + size
        if finish > end:
            raise ValueError("truncated chunk")
        yield tag, data[start + 8:finish]
        start = finish + size % 2
    if start != end:
        raise ValueError("invalid chunk padding")


def pack_chunk(tag, payload, endian="<"):
    return (tag[::-1] if endian == "<" else tag) + struct.pack(endian + "I", len(payload)) + payload + b"\0" * (len(payload) % 2)


def without_printers(data):
    # Do not publish machine-specific printer names, tickets or settings.
    root = list(chunks(data))
    if len(root) != 1 or root[0][0] != b"FORM":
        raise ValueError("expected one report container")
    payload = root[0][1]
    body = payload[:4] + b"".join(pack_chunk(tag, value) for tag, value in chunks(payload, 4)
                                   if tag not in (b"PRPS", b"PRPF", b"PRNT"))
    return data[:4] + pack_chunk(b"FORM", body)


def big_endian(data):
    """Transcode the understood field-only fixture; native getters verify it."""
    def numbers(value, fmt):
        return struct.pack(">" + fmt, *struct.unpack("<" + fmt, value))

    def string(value, pos):
        size = struct.unpack_from("<I", value, pos)[0]
        end = pos + 8 + size
        return (numbers(value[pos:pos + 8], "II") +
                b"".join(value[i:i + 2][::-1] for i in range(pos + 8, end, 2))), end

    def convert(tag, value, parent):
        if tag == b"FORM":
            kind = value[:4][::-1]
            return kind + b"".join(pack_chunk(t, convert(t, v, kind), ">") for t, v in chunks(value, 4))
        if tag in (b"Vers", b"StVr", b"Outp"):
            return numbers(value, "I")
        if tag == b"Mrgn":
            return numbers(value, "IIII")
        if tag == b"Heit":
            return numbers(value, "H")
        if tag == b"Sort":
            return numbers(value, "h" * (len(value) // 2))
        if tag == b"Fild":
            return numbers(value, "III")
        if tag in (b"Tfon", b"Lfon", b"Font"):
            text, pos = string(value, 12)
            return numbers(value[:4], "I") + numbers(value[4:12], "HHHH") + text + numbers(value[pos:], "II")
        if tag in (b"Brdr", b"TBrd"):
            return b"".join(value[i:i + 1] + numbers(value[i + 1:i + 5], "I") for i in range(0, 30, 5))
        if tag == b"Strs":
            result, pos = b"", 0
            for _ in range(3):
                part, pos = string(value, pos)
                result += part
            return result
        if tag == b"Info":
            if parent == b"REPT":
                return numbers(value[:12], "III") + value[12:]
            if parent == b"Col ":
                first, pos = string(value, 6)
                second, pos = string(value, pos)
                return numbers(value[:4], "hH") + value[4:6] + first + second + value[pos:]
            if parent == b"Brek":
                text, pos = string(value, 0)
                return text + numbers(value[pos:pos + 4], "HH") + value[pos + 4:]
        if tag in (b"PRPS", b"PRPF", b"PRNT"):
            return value  # Opaque native data, not a stream of report integers.
        raise ValueError(f"cannot transcode {parent!r}/{tag!r}")

    return data[:4] + b"".join(pack_chunk(t, convert(t, v, b""), ">") for t, v in chunks(data))


def run(app, project, work, method=None, param=None):
    args = [str(app), "--headless", f"--project={project}", f"--data={work / 'data.4DD'}",
            "--create-data", f"--user-param={param or work}"]
    if method:
        args += ["--skip-onstartup", f"--startup-method={method}"]
    result = subprocess.run(args, capture_output=True, text=True, timeout=90)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--four-d", type=Path, required=True, help="Full 4D 21 executable")
    parser.add_argument("--compat-four-d", type=Path, action="append", default=[],
                        help="Optional older full 4D executable (18+); repeat for each version")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="4qr-fixtures-") as directory:
        work = Path(directory)
        shutil.copytree(PROJECT, work / "Project")
        project = work / "Project/qrfixture.4DProject"
        run(args.four_d, project, work, "probe")
        run(args.four_d, project, work, "advanced")
        if not (work / "border.4qr").is_file() or not (work / "crosstab.4qr").is_file():
            raise RuntimeError("4D did not finish generating the probe reports")
        (work / "sales-be.4qr").write_bytes(big_endian((work / "sales.4qr").read_bytes()))
        for name in ("sales", "sales-be"):
            run(args.four_d, project, work, "readback", work / name)
        oracle = json.loads((work / "sales.json").read_text(encoding="utf-8-sig"))
        if oracle != json.loads((work / "sales-be.json").read_text(encoding="utf-8-sig")):
            raise RuntimeError("native LE/BE getters disagree")
        for path in work.glob("*.4qr"):
            if path.stem not in ("centimeters", "inches", "sales-be"):
                (OUT / path.name).write_bytes(without_printers(path.read_bytes()))
        # Sanitize before transcoding so printer payloads are absent in both byte orders.
        (OUT / "sales-be.4qr").write_bytes(big_endian(without_printers((work / "sales.4qr").read_bytes())))
        (OUT / "sales-native.json").write_text(json.dumps(oracle, ensure_ascii=False, indent=2) + "\n")
        for index, app in enumerate(args.compat_four_d):
            compat = work / f"compat-{index}"
            shutil.copytree(PROJECT, compat / "Project")
            run(app, compat / "Project/qrfixture.4DProject", compat)
            raw = (compat / "sales.4qr").read_bytes()
            version = struct.unpack_from("<I", raw, 36)[0]
            for name in ("sales", "crosstab"):
                (OUT / f"{name}-stream{version}.4qr").write_bytes(without_printers((compat / f"{name}.4qr").read_bytes()))
    print(f"Generated Quick Report fixtures in {OUT}")


if __name__ == "__main__":
    main()
