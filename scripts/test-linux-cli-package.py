#!/usr/bin/env python3
"""Portable unit tests plus a real ELF relocation test when run on Linux."""

import importlib.util
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tarfile
import unittest
import uuid


SPEC = importlib.util.spec_from_file_location(
    "linux_package", Path(__file__).with_name("package-cli-linux.py"))
PACKAGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACKAGE)


class LinuxPackageTests(unittest.TestCase):
    def setUp(self):
        self.root = (PACKAGE.ROOT / ".build/linux-package-tests" / str(uuid.uuid4())).resolve()
        self.root.mkdir(parents=True)
        self.addCleanup(shutil.rmtree, self.root)
        self.libs = self.root / "package/lib"
        self.libs.mkdir(parents=True)
        self.binary = self.root / "binary"
        self.binary.write_bytes(b"binary")

    def test_ldd_parses_sonames_spaces_vdso_and_loader(self):
        result = PACKAGE.parse_ldd("""
 linux-vdso.so.1 (0x00007f000000)
 libswiftCore.so => /tool chain/libswiftCore.so (0x00007f000001)
 libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007f000002)
 /lib64/ld-linux-x86-64.so.2 (0x00007f000003)
""")
        self.assertEqual(result[0], ("libswiftCore.so", Path("/tool chain/libswiftCore.so")))
        self.assertEqual(result[-1][0], "ld-linux-x86-64.so.2")

    def test_ldd_fails_closed(self):
        for output in ("libswiftCore.so => not found", "statically linked", "",
                       "/host/libfoo.so (0x01)", "/host/libfoo.so => /host/libfoo.so (0x01)"):
            with self.subTest(output=output), self.assertRaises(RuntimeError):
                PACKAGE.parse_ldd(output)

    def test_dependency_free_dynamic_library_is_a_valid_leaf(self):
        from unittest.mock import patch
        result = subprocess.CompletedProcess([], 0, "\tstatically linked\n", "")
        dynamic = "Dynamic section at offset 0x2000 contains 3 entries:\n (SONAME) libempty.so\n"
        with patch.object(PACKAGE.subprocess, "run", return_value=result):
            with patch.object(PACKAGE.subprocess, "check_output", return_value=dynamic):
                self.assertEqual(PACKAGE.dependencies(self.binary, {}), [])
            for invalid in ("There is no dynamic section in this file.",
                            dynamic + " (NEEDED) Shared library: [libmissing.so]\n"):
                with patch.object(PACKAGE.subprocess, "check_output", return_value=invalid):
                    with self.assertRaises(RuntimeError):
                        PACKAGE.dependencies(self.binary, {})

    def test_system_allowlist_does_not_exclude_icu_or_other_runtime_libraries(self):
        for name in ("libswiftCore.so", "libicui18n.so.74", "libxml2.so.2",
                     "libcurl.so.4", "libz.so.1", "lib_FoundationICU.so"):
            self.assertNotIn(name, PACKAGE.SYSTEM_LIBRARIES)
        self.assertIn("ld-linux-x86-64.so.2", PACKAGE.SYSTEM_LIBRARIES)
        self.assertIn("libc.so.6", PACKAGE.SYSTEM_LIBRARIES)

    def test_recursive_walk_dereferences_and_preserves_aliases(self):
        source = self.root / "source"
        source.mkdir()
        real = source / "libswiftExample.so.1.2"
        real.write_bytes(b"swift")
        alias = source / "libswiftExample.so.1"
        alias.symlink_to(real.name)
        icu = source / "libicu.so.74.2"
        icu.write_bytes(b"icu")
        calls = []

        def inspect(path, env):
            calls.append(path)
            if path == self.binary:
                return [(alias.name, alias), ("libc.so.6", Path("/system/libc.so.6"))]
            if path == alias:
                return [("libicu.so.74", icu)]
            return [(alias.name, alias)]

        records = PACKAGE.bundle_dependencies(self.binary, self.libs, {}, inspect)
        self.assertEqual(len(calls), 3)
        self.assertEqual(len(records), 2)
        self.assertEqual((self.libs / alias.name).readlink(), Path(real.name))
        self.assertEqual((self.libs / alias.name).read_bytes(), b"swift")
        self.assertEqual((self.libs / "libicu.so.74").read_bytes(), b"icu")
        self.assertFalse((self.libs / "libc.so.6").exists())

    def test_conflicting_library_names_are_rejected(self):
        first = self.root / "a/libsame.so"
        second = self.root / "b/libsame.so"
        for path, content in ((first, b"one"), (second, b"two")):
            path.parent.mkdir()
            path.write_bytes(content)
        PACKAGE.copy_library(first, first.name, self.libs)
        with self.assertRaisesRegex(RuntimeError, "Conflicting"):
            PACKAGE.copy_library(second, second.name, self.libs)

    def test_broken_symlink_is_rejected(self):
        alias = self.root / "libmissing.so"
        alias.symlink_to("missing")
        with self.assertRaises(FileNotFoundError):
            PACKAGE.copy_library(alias, alias.name, self.libs)

    def test_relocation_rejects_build_machine_runtime(self):
        def inspect(path, env):
            return [("libswiftCore.so", self.root / "build/libswiftCore.so")]
        with self.assertRaisesRegex(RuntimeError, "external runtime"):
            PACKAGE.validate_relocation(self.binary, self.libs, {}, inspect)

    def test_clean_environment_removes_loader_overrides(self):
        from unittest.mock import patch
        with patch.dict(os.environ, {"LD_LIBRARY_PATH": "/swift", "LD_PRELOAD": "/inject",
                                     "SWIFT_LIBRARY_PATH": "/swift"}):
            env = PACKAGE.clean_environment()
        self.assertNotIn("LD_LIBRARY_PATH", env)
        self.assertNotIn("LD_PRELOAD", env)
        self.assertNotIn("SWIFT_LIBRARY_PATH", env)

    def test_copyright_owner_handles_usrmerged_paths(self):
        from unittest.mock import patch
        missing = subprocess.CompletedProcess([], 1, "", "")
        found = subprocess.CompletedProcess([], 0, "zlib1g:amd64: /lib/libz.so.1.3\n", "")
        with patch.object(PACKAGE.subprocess, "run", side_effect=[missing, found]) as run:
            self.assertEqual(PACKAGE.runtime_packages(Path("/usr/lib/libz.so.1.3")), {"zlib1g"})
        self.assertEqual(run.call_args_list[1].args[0][-1], "/lib/libz.so.1.3")

    def test_launcher_sets_only_local_library_path_and_preserves_arguments(self):
        stage = self.root / "package with spaces"
        (stage / "libexec").mkdir(parents=True)
        launcher = stage / "fourdql"
        launcher.write_text(PACKAGE.LAUNCHER)
        launcher.chmod(0o755)
        binary = stage / "libexec/fourdql"
        binary.write_text('#!/bin/sh\nprintf "%s\\n" "$LD_LIBRARY_PATH" "$@"\n')
        binary.chmod(0o755)
        env = dict(os.environ, LD_LIBRARY_PATH="/external/swift")
        result = subprocess.check_output([str(launcher), "one two", "*"], cwd=self.root,
                                         env=env, text=True)
        self.assertEqual(result.splitlines(), [str(stage / "lib"), "one two", "*"])

    def test_archive_has_one_root_regular_aliases_and_executable_launcher(self):
        stage = self.root / "fourdql-0.0.0-ci.1-linux-x86_64"
        stage.mkdir()
        launcher = stage / "fourdql"
        launcher.write_text(PACKAGE.LAUNCHER)
        launcher.chmod(0o755)
        (stage / "LICENSE").write_text("Project license")
        (stage / "Selawik-OFL.txt").write_text("Font license")
        library = stage / "libexample.so.1.2"
        library.write_bytes(b"runtime")
        (stage / "libexample.so.1").symlink_to(library.name)
        os.link(library, stage / "hardlink.so")
        archive = self.root / (stage.name + ".tar.gz")
        PACKAGE.create_archive(stage, archive)
        with tarfile.open(archive, "r:gz") as tar:
            members = tar.getmembers()
            self.assertTrue(all(entry.isfile() or entry.isdir() for entry in members))
            self.assertEqual({entry.name.split("/")[0] for entry in members}, {stage.name})
            self.assertEqual(tar.extractfile(stage.name + "/libexample.so.1").read(), b"runtime")
            self.assertTrue(tar.getmember(stage.name + "/fourdql").mode & 0o111)
            for name in ("LICENSE", "Selawik-OFL.txt"):
                self.assertTrue(tar.getmember(stage.name + "/" + name).isfile())

    @unittest.skipUnless(platform.system() == "Linux" and shutil.which("cc"),
                         "requires Linux ELF and a C compiler")
    def test_real_elf_runtime_survives_removal_of_build_directory(self):
        source = self.root / "source"
        source.mkdir()
        (source / "library.c").write_text("int answer(void) { return 42; }\n")
        (source / "main.c").write_text(
            "extern int answer(void); int main(void) { return answer() != 42; }\n")
        library = source / "libpackageprobe.so.1.2"
        subprocess.run(["cc", "-shared", "-fPIC", "-Wl,-soname,libpackageprobe.so.1",
                        str(source / "library.c"), "-o", str(library)], check=True)
        (source / "libpackageprobe.so.1").symlink_to(library.name)
        (source / "libpackageprobe.so").symlink_to(library.name)
        subprocess.run(["cc", str(source / "main.c"), "-L" + str(source),
                        "-lpackageprobe", "-Wl,-rpath," + str(source),
                        "-o", str(self.binary)], check=True)
        PACKAGE.bundle_dependencies(self.binary, self.libs, PACKAGE.clean_environment())
        shutil.rmtree(source)
        PACKAGE.validate_relocation(self.binary, self.libs, PACKAGE.clean_environment())
        subprocess.run([str(self.binary)], cwd=self.root,
                       env=dict(PACKAGE.clean_environment(), LD_LIBRARY_PATH=str(self.libs)),
                       check=True)


if __name__ == "__main__":
    unittest.main()
