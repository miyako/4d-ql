#!/usr/bin/env python3
"""Standalone CLI contract checks; never starts 4D or Quick Look."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--renderer", type=Path, default=Path(".build/debug/fourdform"))
    args = parser.parse_args()
    repository = Path(__file__).resolve().parent.parent
    renderer = args.renderer.resolve()
    fixtures = repository / "Tests/FourDFileKitTests/Fixtures"
    controls = fixtures / "FormProject/Project/Sources/Forms/Controls/form.4DForm"
    static = fixtures / "FormStaticProject/Project/Sources/Forms/Root/form.4DForm"
    references = fixtures / "FormBenchmarkProject/Project/Sources/Forms/References/form.4DForm"

    with tempfile.TemporaryDirectory(prefix="fourdform-") as temporary:
        directory = Path(temporary)
        executable = directory / renderer.name
        shutil.copy2(renderer, executable)
        environment = dict(os.environ, PATH="")

        def run(*arguments, code=0):
            result = subprocess.run([str(executable), *map(str, arguments)], cwd=directory,
                                    env=environment, capture_output=True, timeout=15)
            assert result.returncode == code, (arguments, result.returncode, result.stderr.decode())
            return result

        run("--help")
        document = json.loads(run("--json", "--language", "en", controls).stdout)
        assert document["schemaVersion"] == 1 and document["referencePlatform"] == "macOS"
        assert len(document["form"]["images"]) == 1
        assert document["notices"] == []
        page = document["form"]["appearances"][0]["pages"][1]
        name = next(obj for obj in page["objects"] if obj["name"] == "name")
        assert name["properties"]["width"] == 430
        assert name["properties"]["stroke"] == "#286092"

        result = run("--json", "--language", "fr", static)
        document = json.loads(result.stdout)
        assert document["form"]["localizationLanguage"] == "fr"
        assert document["form"]["properties"]["windowTitle"] == "Formulaires statiques"
        common, page = document["form"]["appearances"][0]["pages"][:2]
        assert [obj["name"] for obj in common["objects"]] == [
            "grandBackground", "grandMain", "shared", "basePageOne", "shared"]
        panel = next(obj for obj in page["objects"] if obj["name"] == "panel")
        assert [obj["name"] for obj in panel["children"]] == ["panelBackground", "picture", "nested"]
        assert any("schema" in notice or "noncanonical" in notice for notice in document["notices"])
        assert b"warning:" in result.stderr

        for form in (controls, static, references):
            html = run("--html", "--language", "en", form).stdout.decode()
            assert html.count("<!doctype html>") + html.count("<!DOCTYPE html>") == 1
            assert "Content-Security-Policy" in html and "<script" not in html
            assert "data:image/" in html

        html = run("--theme", "classic-dark", "--page", "2", controls).stdout.decode()
        assert 'id="theme-classicDark" checked>' in html
        assert 'id="page-classicDark-2" checked>' in html
        output = directory / "render.html"
        assert run("--output", output, controls).stdout == b""
        assert output.read_text().startswith("<!doctype html>") or output.read_text().startswith("<!DOCTYPE html>")
        run("--theme", "windows-light", controls, code=2)
        run("--page", "-1", controls, code=2)
        run("--page", "99", controls, code=1)
        before = hashlib.sha256(controls.read_bytes()).digest()
        run("--output", controls, controls, code=1)
        assert hashlib.sha256(controls.read_bytes()).digest() == before
        run(directory / "missing.4DForm", code=1)
        malformed = directory / "malformed.4DForm"
        malformed.write_text("{invalid")
        failure = run(malformed, code=1)
        assert failure.stdout == b""
        assert b"error:" in failure.stderr and b"JSON" in failure.stderr
        run("--language", "", controls, code=2)
        run("--output", code=2)
        run(code=2)
        run("--output", directory / "missing" / "render.html", controls, code=1)
        dash_input = directory / "-form.4DForm"
        dash_input.write_text('{"pages":[{"objects":{}},{"objects":{}}]}')
        run("--", "-form.4DForm")
        run(controls, static, code=2)
    print("Standalone CLI verified: isolated binary, static resources/localization, HTML/JSON, options and failures.")


if __name__ == "__main__":
    main()
