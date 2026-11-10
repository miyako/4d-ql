#!/usr/bin/env python3
"""Smoke-test an extracted CLI distribution without a Swift development environment."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parent.parent
EXPECTED_KINDS = {
    "data-file": "db4d.data",
    "structure-file": "db4d.structure",
    "catalog": "catalog.structure",
    "import-export-settings": "4d.import-export-settings",
    "settings": "4d.text",
    "project": "4d.text",
    "link": "4d.text",
    "preferences": "4d.text",
    "query": "4d.query",
    "set": "4d.set",
    "label": "4d.label",
    "write-pro": "4d.writepro",
    "view-pro": "4d.viewpro",
    "method": "4dm.source",
    "form": "4d.form",
}


def runtime_environment():
    environment = {
        key: value for key, value in os.environ.items()
        if not key.upper().startswith(("SWIFT", "DYLD_", "LD_"))
        and key.upper() not in {
            "SDKROOT", "TOOLCHAINS", "DEVELOPER_DIR",
            "LIBRARY_PATH", "LIB", "LIBPATH", "INCLUDE",
        }
    }
    if os.name == "nt":
        windows = Path(os.environ["SystemRoot"])
        environment["PATH"] = os.pathsep.join(map(str, [windows / "System32", windows]))
    else:
        environment["PATH"] = "/usr/bin:/bin"
    return environment


def extract_package(archive, destination):
    destination.mkdir()
    if archive.name.endswith(".zip"):
        with zipfile.ZipFile(archive) as package:
            for entry in package.infolist():
                target = (destination / entry.filename).resolve()
                if not target.is_relative_to(destination):
                    raise ValueError(f"Archive entry escapes its directory: {entry.filename}")
                if (entry.external_attr >> 16) & 0o170000 == 0o120000:
                    raise ValueError(f"Unexpected ZIP symlink: {entry.filename}")
            package.extractall(destination)
        name = archive.name[:-4]
    elif archive.name.endswith(".tar.gz"):
        with tarfile.open(archive, "r:gz") as package:
            for entry in package.getmembers():
                target = (destination / entry.name).resolve()
                if not target.is_relative_to(destination) or not (entry.isfile() or entry.isdir()):
                    raise ValueError(f"Unsafe archive entry: {entry.name}")
            options = {"filter": "data"} if hasattr(tarfile, "data_filter") else {}
            package.extractall(destination, **options)
        name = archive.name[:-7]
    else:
        raise ValueError(f"Unsupported package: {archive}")
    folder = destination / name
    if not folder.is_dir() or sorted(destination.iterdir()) != [folder]:
        raise ValueError(f"Expected a single {name} package directory")
    for required in ("LICENSE", "Selawik-OFL.txt"):
        if not (folder / required).is_file():
            raise ValueError(f"Package is missing {required}")
    return folder / ("fourdql.exe" if os.name == "nt" else "fourdql")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--archive", type=Path, help="ZIP or tar.gz to extract and test")
    source.add_argument("--cli", type=Path, help="Already extracted executable or launcher")
    parser.add_argument("--scratch", type=Path, required=True)
    parser.add_argument("--container", help="Run the packaged command in a Swift-free Docker image")
    args = parser.parse_args()
    if args.container and (not args.archive or os.name == "nt"):
        parser.error("--container requires --archive on a Unix host")
    scratch = args.scratch.resolve()
    scratch.mkdir(parents=True, exist_ok=True)
    environment = runtime_environment()
    captures = json.loads((ROOT / "docs/images/cli/manifest.json").read_text())["captures"]
    expected_stems = set(EXPECTED_KINDS) | {"quick-report"}
    if len(captures) != 16 or {item["stem"] for item in captures} != expected_stems:
        raise ValueError("Expected the gallery's 16 distinct supported document families")

    with tempfile.TemporaryDirectory(prefix="cli package with spaces ", dir=scratch) as temporary:
        work = Path(temporary).resolve()
        cli = extract_package(args.archive.resolve(), work / "distribution") if args.archive else args.cli.resolve()
        if not cli.is_file():
            raise ValueError(f"Missing packaged command: {cli}")
        command = [str(cli)]
        if args.container:
            docker = shutil.which("docker")
            if not docker:
                raise ValueError("Docker is required for --container")
            command = [docker, "run", "--rm", "--pull", "never", "--network", "none", "--workdir", str(work)]
            for directory in (work, ROOT / "Tests", ROOT / "docs/examples"):
                command += [
                    "--mount", f"type=bind,source={directory},target={directory},readonly",
                ]
            command += [args.container, str(cli)]

        def run(*arguments, status=0):
            result = subprocess.run(
                [*command, *arguments], cwd=work, env=environment,
                capture_output=True, encoding="utf-8", timeout=120,
            )
            if result.returncode != status:
                raise ValueError(
                    f"{arguments}: exit {result.returncode}, expected {status}\n"
                    f"{result.stdout}\n{result.stderr}"
                )
            return result.stdout

        if "fourdql" not in run("--help").lower():
            raise ValueError("Missing CLI help")
        if "com.4d.4d.ViewProDocument" not in run("--content-types"):
            raise ValueError("Missing View Pro content type")
        run(status=2)
        for item in captures:
            stem = item["stem"]
            path = str(ROOT / item["input"])
            model = json.loads(run("--json", path))
            if not isinstance(model, dict) or not model.get("fileName"):
                raise ValueError(f"{stem}: missing typed analysis")
            if stem == "quick-report":
                if "columns" not in model or "formatVersion" not in model:
                    raise ValueError("Missing quick-report columns/version")
            elif model.get("kind") != EXPECTED_KINDS[stem]:
                raise ValueError(f"{stem}: unexpected JSON kind {model.get('kind')}")
            for mode in ((), ("--html",)):
                output = run(*mode, path)
                if not output.strip() or any(
                    failure in output for failure in ("No preview available", "Problem report")
                ):
                    raise ValueError(f"{stem}: {mode or 'text'} returned an error report")
                if mode and ("<!doctype html>" not in output.lower() or "</html>" not in output.lower()):
                    raise ValueError(f"{stem}: incomplete HTML")
            print(f"{stem}: text / JSON / HTML OK", flush=True)

        alias = work / "data alias.data"
        shutil.copyfile(ROOT / "Tests/FourDFileKitTests/Fixtures/plain.4DD", alias)
        if json.loads(run("--json", str(alias))).get("kind") != "db4d.data":
            raise ValueError("The .data alias did not select the data-file analyzer")
        workbook = str(ROOT / "Tests/FourDFileKitTests/Fixtures/ViewPro/enriched.4vp")
        if json.loads(run("--thorough", "--html", "--json", workbook)).get("kind") != "4d.viewpro":
            raise ValueError("Thorough analysis or last-output-option selection failed")
        if "<!doctype html>" not in run("--json", "--html", workbook).lower():
            raise ValueError("The last HTML output option did not take precedence")

        missing = str(work / "missing.4vp")
        malformed = work / "malformed.4vp"
        malformed.write_text("{", encoding="utf-8")
        for invalid in (missing, str(malformed)):
            run("--json", invalid, status=1)
            for mode in ((), ("--html",)):
                failure = run(*mode, invalid)
                if "No preview available" not in failure and "Problem report" not in failure:
                    raise ValueError("Invalid input did not produce the documented error report")
        print("Packaged CLI: 16 document families and documented exit statuses OK")


if __name__ == "__main__":
    main()
