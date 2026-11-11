#!/usr/bin/env python3
"""Exercise the built converter's file, pipe and error contracts."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
CLI = Path(os.environ.get(
    "FOURDQL", ROOT / ".build/debug" / ("fourdql.exe" if os.name == "nt" else "fourdql"),
)).resolve()
FIXTURES = ROOT / "Tests/FourDFileKitTests/Fixtures/QuickReport"


class QuickReportCLITests(unittest.TestCase):
    def run_cli(self, *arguments, data=None, code=0):
        result = subprocess.run(
            [str(CLI), *map(str, arguments)], input=data,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30,
        )
        self.assertEqual(result.returncode, code, result.stderr.decode(errors="replace"))
        if code == 0:
            self.assertEqual(result.stderr, b"")
        else:
            self.assertEqual(result.stdout, b"")
            self.assertIn(b"qr-convert:", result.stderr)
        return result

    def test_pipe_roundtrip_for_all_fixtures(self):
        for path in sorted(FIXTURES.glob("*.4qr")):
            with self.subTest(path=path.name):
                original = path.read_bytes()
                exported = self.run_cli("qr-convert", "--to-json", data=original).stdout
                self.assertEqual(json.loads(exported)["schemaVersion"], 1)
                self.assertEqual(
                    self.run_cli("qr-convert", "--to-4qr", "-", "-", data=exported).stdout,
                    original,
                )

    def test_file_paths_mixed_io_and_in_place_replacement(self):
        original = (FIXTURES / "unicode.4qr").read_bytes()
        with tempfile.TemporaryDirectory(prefix="quick report ") as directory:
            binary = Path(directory) / "report.4QR"
            definition = Path(directory) / "report.json"
            binary.write_bytes(original)
            self.assertEqual(self.run_cli("qr-convert", "--to-json", binary, definition).stdout, b"")
            exported = definition.read_bytes()
            self.assertEqual(
                self.run_cli("qr-convert", "--to-json", "-i", binary).stdout, exported,
            )
            self.assertEqual(
                self.run_cli("qr-convert", "--to-4qr", "--input", definition).stdout, original,
            )
            binary.write_bytes(b"old destination")
            self.assertEqual(
                self.run_cli("qr-convert", "--to-4qr", "-o", binary, data=exported).stdout, b"",
            )
            self.assertEqual(binary.read_bytes(), original)
            self.run_cli("qr-convert", "--to-json", binary, binary)
            self.assertEqual(binary.read_bytes(), exported)
            self.run_cli("qr-convert", "--to-4qr", binary, binary)
            self.assertEqual(binary.read_bytes(), original)
            self.run_cli("qr-convert", "--to-json", "--", binary, definition)

    def test_json_edits_reach_report_model(self):
        for name in ("sales.4qr", "sales-be.4qr", "sales-stream25.4qr", "crosstab.4qr"):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                exported = self.run_cli("qr-convert", "--to-json", FIXTURES / name).stdout
                document = json.loads(exported)
                forms = document["root"]["payload"]["form"]["chunks"]
                column = next(
                    chunk["payload"]["form"]["chunks"] for chunk in forms
                    if chunk["tag"] == "FORM" and chunk["payload"]["form"]["type"] == "Col "
                )
                info = next(chunk["payload"]["columnInfo"] for chunk in column if chunk["tag"] == "Info")
                info.update(title="Revenue 日本語 😀", width=257, hidden=1, displayFormat="###,##0.000")
                font = next(chunk["payload"]["style"] for chunk in column if chunk["tag"] == "Tfon")
                font.update(fontName="Courier New", fontSize=19, face=3, foreground=0x00563412)
                borders = next(chunk["payload"]["borders"]["values"] for chunk in column if chunk["tag"] == "TBrd")
                borders[5].update(thickness=4, color=0x00563412)
                field = next(chunk["payload"]["field"] for chunk in column if chunk["tag"] == "Fild")
                field.update(fieldNumber=42)
                cell = next(
                    chunk["payload"]["form"]["chunks"] for chunk in column
                    if chunk["tag"] == "FORM" and chunk["payload"]["form"]["type"] == "Brek"
                )
                cell_info = next(chunk["payload"]["cellInfo"] for chunk in cell if chunk["tag"] == "Info")
                cell_info.update(text="Updated total", operators=17, hidden=1)
                path = Path(directory) / "edited.4qr"
                self.run_cli("qr-convert", "--to-4qr", "-o", path, data=json.dumps(document).encode())
                model = json.loads(self.run_cli("--json", path).stdout)
                first = model["columns"][0]
                self.assertEqual(first["title"], info["title"])
                self.assertEqual(first["width"], 257)
                self.assertTrue(first["hidden"])
                self.assertEqual(first["displayFormat"], info["displayFormat"])
                self.assertEqual(first["titleStyle"]["fontName"], "Courier New")
                self.assertEqual(first["titleStyle"]["fontSize"], 19)
                self.assertEqual(first["titleStyle"]["face"], 3)
                self.assertEqual(first["titleStyle"]["foreground"], "#123456")
                self.assertEqual(first["titleBorders"][5], {"thickness": 4, "color": "#123456"})
                self.assertEqual(first["fieldNumber"], 42)
                self.assertEqual(first["cells"][0]["text"], "Updated total")
                self.assertEqual(first["cells"][0]["operators"], 17)
                self.assertTrue(first["cells"][0]["hidden"])

    def test_usage_errors(self):
        for arguments in (
            (), ("--to-json", "--to-4qr"), ("--unknown",), ("--to-json", "-i"),
            ("--to-json", "a", "b", "c"), ("--to-json", "-i", "a", "b"),
            ("--to-json", "-i", "a", "-i", "b"),
            ("--to-json", "-o", "a", "-o", "b"),
        ):
            with self.subTest(arguments=arguments):
                self.run_cli("qr-convert", *arguments, code=2)
        self.assertIn(b"qr-convert", self.run_cli("--help").stdout)
        self.assertIn(b"stdin/stdout", self.run_cli("qr-convert", "--help").stdout)

    def test_conversion_and_io_errors_do_not_replace_destination(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "existing.json"
            destination.write_bytes(b"keep me")
            for direction, data in (
                ("--to-json", b"invalid binary"), ("--to-4qr", b"not JSON"),
                ("--to-4qr", b"{}"),
                ("--to-json", bytes(32 * 1024 * 1024 + 1)),
            ):
                with self.subTest(direction=direction, size=len(data)):
                    self.run_cli("qr-convert", direction, "-o", destination, data=data, code=1)
                    self.assertEqual(destination.read_bytes(), b"keep me")
            self.run_cli("qr-convert", "--to-json", Path(directory) / "missing.4qr", code=1)
            self.run_cli(
                "qr-convert", "--to-json", FIXTURES / "sales.4qr",
                Path(directory) / "missing-directory" / "report.json", code=1,
            )

    def test_connected_process_pipeline(self):
        with subprocess.Popen(
            [str(CLI), "qr-convert", "--to-json", str(FIXTURES / "sales.4qr")],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        ) as producer:
            result = subprocess.run(
                [str(CLI), "qr-convert", "--to-4qr"], stdin=producer.stdout,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30,
            )
            producer.stdout.close()
            _, errors = producer.communicate(timeout=30)
            self.assertEqual(producer.returncode, 0, errors)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, (FIXTURES / "sales.4qr").read_bytes())


if __name__ == "__main__":
    unittest.main()
