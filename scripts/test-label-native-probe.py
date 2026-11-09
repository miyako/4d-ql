#!/usr/bin/env python3
"""Verify native label probe safety guards without launching 4D."""

import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("label_probe", ROOT / "scripts/label-native-probe.py")
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


class NativeLabelGuardTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix=".label-probe-tests-", dir=ROOT)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.corpus = self.root / "corpus"
        shutil.copytree(probe.CORPUS, self.corpus, ignore=shutil.ignore_patterns("References"))
        patcher = patch.object(probe, "CORPUS", self.corpus)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_authored_modern_project_passes(self):
        result = probe.validate_fixture()
        self.assertEqual(result["compatibilityVersion"], 2100)
        self.assertEqual(result["tablesWithPrimaryKeys"], 1)
        self.assertFalse(result["existingStructureOrData"])

    def test_legacy_project_is_rejected(self):
        path = self.corpus / "Project/LabelProbe.4DProject"
        project = json.loads(path.read_text())
        project["compatibilityVersion"] = 1300
        path.write_text(json.dumps(project))
        with self.assertRaisesRegex(ValueError, "modern"):
            probe.validate_fixture()

    def test_missing_nullable_or_nonunique_keys_are_rejected(self):
        path = self.corpus / "Project/Sources/catalog.4DCatalog"
        original = path.read_text()
        for mutation in ("missing", "nullable", "nonunique"):
            with self.subTest(mutation=mutation):
                catalog = ET.fromstring(original)
                table = catalog.find("table")
                if mutation == "missing":
                    table.remove(table.find("primary_key"))
                else:
                    table.find("field").set("not_null" if mutation == "nullable" else "unique", "false")
                ET.ElementTree(catalog).write(path)
                with self.assertRaisesRegex(ValueError, "primary key"):
                    probe.validate_fixture()

    def test_existing_binary_files_and_symlinks_are_rejected(self):
        for extension in (".4DB", ".4DC", ".4DZ", ".4DD", ".4DIndx", ".Match"):
            with self.subTest(extension=extension):
                path = self.corpus / ("legacy" + extension)
                path.touch()
                with self.assertRaisesRegex(ValueError, "binary structure/data"):
                    probe.validate_fixture()
                path.unlink()
        link = self.corpus / "outside"
        link.symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlink"):
            probe.validate_fixture()

    def test_fresh_output_required(self):
        output = self.root / "output"
        probe.validate_output(output)
        output.mkdir()
        probe.validate_output(output)
        (output / "old.4DD").touch()
        with self.assertRaisesRegex(ValueError, "new or empty"):
            probe.validate_output(output)
        with self.assertRaisesRegex(ValueError, "authored corpus"):
            probe.validate_output(self.corpus)

    def test_tool4d_is_not_an_allowed_engine(self):
        probe.validate_engine(Path("/Applications/4D 21 R5/4D.app/Contents/MacOS/4D"))
        for engine in ("tool4d", "/Applications/tool4d.app/Contents/MacOS/tool4d", "/tmp/4D"):
            with self.assertRaisesRegex(ValueError, "full 4D.app"):
                probe.validate_engine(Path(engine))


if __name__ == "__main__":
    unittest.main()
