#!/usr/bin/env python3
"""Bundle a release CLI and its runtime closure, not the Linux C/C++ runtime.

Invocation: package-cli-linux.sh VERSION [OUTPUT_DIRECTORY].
License texts are fetched from the matching official Swift release tag; Debian
runtime dependencies retain their installed package copyright files.
"""

import argparse
import filecmp
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tarfile
import urllib.request


ROOT = Path(__file__).resolve().parent.parent
SYSTEM_LIBRARIES = {
    "libc.so.6", "libm.so.6", "libdl.so.2", "libpthread.so.0",
    "librt.so.1", "libresolv.so.2", "libutil.so.1", "libanl.so.1",
    "libgcc_s.so.1", "libstdc++.so.6", "ld-linux-x86-64.so.2",
}
LAUNCHER = """#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LD_LIBRARY_PATH="$root/lib" exec "$root/libexec/fourdql" "$@"
"""


def clean_environment():
    env = os.environ.copy()
    for key in ("LD_LIBRARY_PATH", "LD_PRELOAD", "SWIFT_LIBRARY_PATH",
                "DYLD_LIBRARY_PATH", "DYLD_FALLBACK_LIBRARY_PATH"):
        env.pop(key, None)
    env["LC_ALL"] = "C"
    return env


def check_host():
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        raise RuntimeError("Linux packages must be built on Linux x86_64")
    release = dict(line.split("=", 1) for line in
                   Path("/etc/os-release").read_text().splitlines() if "=" in line)
    if release.get("ID", "").strip('"') != "ubuntu" or release.get("VERSION_ID", "").strip('"') != "24.04":
        raise RuntimeError("Build on Ubuntu 24.04 (glibc 2.39), not a different ABI baseline")


def parse_ldd(output):
    dependencies = []
    for line in output.splitlines():
        line = line.strip()
        if not line or line.startswith("linux-vdso.so."):
            continue
        if "=> not found" in line:
            raise RuntimeError("Unresolved runtime library: " + line)
        match = re.fullmatch(r"(\S+) => (/.+?) \(0x[0-9a-fA-F]+\)", line)
        if match:
            name, path = match.groups()
            if "/" in name:
                raise RuntimeError("Non-relocatable dependency: " + line)
            dependencies.append((name, Path(path)))
            continue
        match = re.fullmatch(r"(/.+?) \(0x[0-9a-fA-F]+\)", line)
        if match and Path(match[1]).name == "ld-linux-x86-64.so.2":
            dependencies.append(("ld-linux-x86-64.so.2", Path(match[1])))
            continue
        raise RuntimeError("Unrecognized ldd output: " + line)
    if not dependencies:
        raise RuntimeError("ldd reported no dynamic dependencies")
    return dependencies


def dependencies(path, env):
    result = subprocess.run(["ldd", str(path)], env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    if result.stdout.strip() == "statically linked":
        # ldd uses this wording for dynamic shared-library leaves with no NEEDED tags.
        dynamic = subprocess.check_output(["readelf", "-d", str(path)], env=env, text=True)
        if "Dynamic section at offset" in dynamic and "(NEEDED)" not in dynamic:
            return []
        raise RuntimeError("Expected a dynamic ELF runtime library: " + str(path))
    return parse_ldd(result.stdout)


def copy_library(source, alias, destination):
    resolved = source.resolve(strict=True)
    target = destination / resolved.name
    if target.exists():
        if not filecmp.cmp(resolved, target, shallow=False):
            raise RuntimeError("Conflicting runtime library: " + resolved.name)
    else:
        shutil.copy2(resolved, target)
    for name in {alias, source.name} - {resolved.name}:
        link = destination / name
        if link.is_symlink() and link.readlink() == Path(resolved.name):
            continue
        if link.exists() or link.is_symlink():
            raise RuntimeError("Conflicting runtime alias: " + name)
        link.symlink_to(resolved.name)
    return resolved


def bundle_dependencies(binary, destination, env, inspect=dependencies):
    pending = [binary]
    visited = set()
    records = {}
    while pending:
        current = pending.pop()
        resolved = current.resolve(strict=True)
        if resolved in visited:
            continue
        visited.add(resolved)
        for name, source in inspect(current, env):
            if name in SYSTEM_LIBRARIES:
                continue
            copied = copy_library(source, name, destination)
            if name in records and records[name] != str(copied):
                raise RuntimeError("Conflicting dependency resolution: " + name)
            records[name] = str(copied)
            pending.append(source)
    return records


def validate_relocation(binary, libraries, env, inspect=dependencies):
    relocated = dict(env, LD_LIBRARY_PATH=str(libraries))
    for path in [binary, *sorted(libraries.glob("*.so*"))]:
        for name, source in inspect(path, relocated):
            if name not in SYSTEM_LIBRARIES and source.resolve().parent != libraries.resolve():
                raise RuntimeError(f"Package depends on an external runtime: {name} => {source}")


def download_notice(url, target):
    with urllib.request.urlopen(url, timeout=60) as response:
        data = response.read()
    if len(data) < 100 or b"<html" in data.lower():
        raise RuntimeError("Invalid license text from " + url)
    target.write_bytes(data)


def runtime_packages(path):
    candidates = [str(path)]
    if str(path).startswith("/usr/lib/"):
        candidates.append(str(path)[4:])
    elif str(path).startswith("/lib/"):
        candidates.append("/usr" + str(path))
    for candidate in candidates:
        result = subprocess.run(["dpkg-query", "-S", candidate], text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.returncode == 0:
            return {line.split(": ", 1)[0].split(":")[0]
                    for line in result.stdout.splitlines()}
    raise RuntimeError("Cannot identify runtime license owner: " + str(path))


def copy_notices(destination, records, swift_version):
    shutil.copy2(ROOT / "LICENSE", destination / "PROJECT-LICENSE")
    shutil.copy2(ROOT / "ThirdParty/Selawik/OFL.txt", destination / "Selawik-OFL.txt")
    tag = "swift-" + swift_version + "-RELEASE"
    sources = {
        "Swift-LICENSE.txt": ("swift", "LICENSE.txt"),
        "Foundation-LICENSE.txt": ("swift-corelibs-foundation", "LICENSE"),
        "Dispatch-LICENSE.txt": ("swift-corelibs-libdispatch", "LICENSE"),
        "Swift-Foundation-LICENSE.txt": ("swift-foundation", "LICENSE.md"),
        "Swift-Foundation-NOTICE.txt": ("swift-foundation", "NOTICE.txt"),
        "Swift-Foundation-ICU-LICENSE.txt": ("swift-foundation-icu", "LICENSE.md"),
        "LLVM-LICENSE.txt": ("llvm-project", "llvm/LICENSE.TXT"),
    }
    for filename, (repo, path) in sources.items():
        download_notice(f"https://raw.githubusercontent.com/swiftlang/{repo}/{tag}/{path}",
                        destination / filename)
    # ICU is also embedded in the Foundation runtime, independently of libicu.so.
    icu_header = destination / "Swift-Foundation-ICU-version.h"
    download_notice(
        f"https://raw.githubusercontent.com/swiftlang/swift-foundation-icu/{tag}/"
        "icuSources/include/_foundation_unicode/uvernum.h", icu_header)
    header = icu_header.read_text()
    major = re.search(r"#define U_ICU_VERSION_MAJOR_NUM (\d+)", header)
    minor = re.search(r"#define U_ICU_VERSION_MINOR_NUM (\d+)", header)
    if not major or not minor:
        raise RuntimeError("Cannot identify the embedded Foundation ICU version")
    download_notice(
        "https://raw.githubusercontent.com/unicode-org/icu/"
        f"release-{major[1]}-{minor[1]}/LICENSE", destination / "ICU-LICENSE.txt")
    for source in sorted(set(records.values())):
        path = Path(source)
        if "/swift/" in str(path):
            continue
        for package in runtime_packages(path):
            copyright_file = Path("/usr/share/doc") / package / "copyright"
            if not copyright_file.is_file():
                raise RuntimeError("Missing runtime copyright file: " + str(copyright_file))
            shutil.copy2(copyright_file, destination / (package + "-copyright"))


def create_archive(stage, archive):
    # Keep SONAME aliases in staging, but ship regular files for safe extractors.
    with tarfile.open(archive, "w:gz", dereference=True) as tar:
        tar.add(stage, arcname=stage.name)


def package(binary, version, output):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+-]*", version):
        raise RuntimeError("VERSION must be a nonempty filename-safe release identifier")
    binary = binary.resolve(strict=True)
    env = clean_environment()
    swift = subprocess.check_output(["swift", "--version"], env=env, text=True)
    match = re.search(r"Swift version (\d+\.\d+\.\d+)", swift)
    if not match:
        raise RuntimeError("Cannot identify a stable Swift release for runtime notices")
    swift_version = match[1]
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    name = f"fourdql-{version}-linux-x86_64"
    stage = output / name
    if stage.exists():
        raise RuntimeError("Remove existing package staging directory before rebuilding: " + str(stage))
    for directory in ("lib", "libexec", "licenses"):
        (stage / directory).mkdir(parents=True)
    shutil.copy2(binary, stage / "libexec/fourdql")
    (stage / "fourdql").write_text(LAUNCHER)
    (stage / "fourdql").chmod(0o755)
    records = bundle_dependencies(binary, stage / "lib", env)
    copy_notices(stage / "licenses", records, swift_version)
    shutil.copy2(stage / "licenses/PROJECT-LICENSE", stage / "LICENSE")
    shutil.copy2(stage / "licenses/Selawik-OFL.txt", stage / "Selawik-OFL.txt")
    (stage / "runtime-libraries.json").write_text(json.dumps({
        "swift_version": swift_version, "bundled": records,
        "system_libraries": sorted(SYSTEM_LIBRARIES),
    }, indent=2) + "\n")
    (stage / "README.txt").write_text(
        "fourdql command-line previewer\n\n"
        "Target: Ubuntu 24.04 x86_64, glibc 2.39 or later; requires the OS C/C++ "
        "runtime (libc6, libgcc-s1, libstdc++6), /bin/sh and normal system data "
        "(timezone/locale data and CA certificates where applicable).\n"
        "Other distributions are not validated. No Swift installation required.\n"
        "Keep fourdql, libexec, lib and licenses together. Run ./fourdql --help.\n"
        "Only the launcher sets LD_LIBRARY_PATH; do not invoke libexec/fourdql directly.\n\n"
        "Linux rendering is experimental: text metrics use an approximate fallback; "
        "raster form/label pictures are unsupported and produce notices. SVG pictures "
        "and document analysis remain available. No macOS/Windows rendering parity "
        "is claimed.\n\n"
        f"Built with Swift {swift_version}. Runtime and embedded Selawik font notices "
        "are in licenses/. runtime-libraries.json records the dependency closure.\n")
    validate_relocation(stage / "libexec/fourdql", stage / "lib", env)
    subprocess.run([str(stage / "fourdql"), "--help"], cwd=output, env=env,
                   check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    archive = output / (name + ".tar.gz")
    create_archive(stage, archive)
    print(archive)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-host", action="store_true")
    parser.add_argument("--version")
    parser.add_argument("--binary", type=Path)
    parser.add_argument("--output-dir", type=Path, default=Path("dist"))
    args = parser.parse_args()
    check_host()
    if args.check_host:
        return
    if not args.version or not args.binary:
        parser.error("--version and --binary are required")
    package(args.binary, args.version, args.output_dir)


if __name__ == "__main__":
    main()
