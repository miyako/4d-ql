#!/usr/bin/env python3
"""Unit checks for the distribution smoke-test harness."""

import importlib.util
import io
import os
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zipfile


SPEC = importlib.util.spec_from_file_location(
    "cli_smoke", Path(__file__).with_name("test-cli-package.py")
)
SMOKE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SMOKE)


class PackageSmokeTests(unittest.TestCase):
    def test_environment_removes_development_paths(self):
        variables = {
            "PATH": "/swift/bin", "SDKROOT": "/swift/sdk",
            "SWIFT_RESOURCE_DIR": "/swift/lib", "LD_LIBRARY_PATH": "/swift/lib",
            "DYLD_LIBRARY_PATH": "/swift/lib", "LIB": "/swift/lib",
            "SystemRoot": os.environ.get("SystemRoot", "C:\\Windows"),
        }
        with patch.dict(os.environ, variables, clear=True):
            environment = SMOKE.runtime_environment()
        self.assertNotIn("/swift", environment["PATH"])
        for key in ("SDKROOT", "SWIFT_RESOURCE_DIR", "LD_LIBRARY_PATH", "DYLD_LIBRARY_PATH", "LIB"):
            self.assertNotIn(key, environment)

    def test_extracts_distribution_and_keeps_executable_mode(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            archive = root / "fourdql-test.tar.gz"
            with tarfile.open(archive, "w:gz") as package:
                for name in ("fourdql", "LICENSE", "Selawik-OFL.txt"):
                    entry = tarfile.TarInfo(f"fourdql-test/{name}")
                    entry.size = 1
                    entry.mode = 0o755 if name == "fourdql" else 0o644
                    package.addfile(entry, io.BytesIO(b"x"))
            command = SMOKE.extract_package(archive, root / "extracted with spaces")
            expected = "fourdql.exe" if os.name == "nt" else "fourdql"
            self.assertEqual(command.name, expected)
            self.assertTrue((command.parent / "LICENSE").is_file())
            if os.name != "nt":
                self.assertEqual(command.stat().st_mode & 0o777, 0o755)

    def test_rejects_archive_escape_and_links(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            for index, name in enumerate(("../escaped", "/absolute")):
                archive = root / f"bad-{index}.zip"
                with zipfile.ZipFile(archive, "w") as package:
                    package.writestr(name, "x")
                with self.subTest(name=name), self.assertRaises(ValueError):
                    SMOKE.extract_package(archive, root / f"zip-{index}")
            archive = root / "bad.tar.gz"
            with tarfile.open(archive, "w:gz") as package:
                entry = tarfile.TarInfo("link")
                entry.type = tarfile.SYMTYPE
                entry.linkname = "/outside"
                package.addfile(entry)
            with self.assertRaises(ValueError):
                SMOKE.extract_package(archive, root / "tar")

    def test_rejects_missing_licenses(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            archive = root / "fourdql-test.zip"
            with zipfile.ZipFile(archive, "w") as package:
                package.writestr("fourdql-test/fourdql.exe", "x")
            with self.assertRaisesRegex(ValueError, "missing LICENSE"):
                SMOKE.extract_package(archive, root / "extracted")


if __name__ == "__main__":
    unittest.main()
