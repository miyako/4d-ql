#!/usr/bin/env python3
"""Credential-free regression tests for the release gate."""

import contextlib
import copy
import importlib.util
import io
from pathlib import Path
import plistlib
import shutil
import subprocess
import unittest
from unittest.mock import patch
import uuid


ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("verify_release", ROOT / "scripts/verify-release.py")
verifier = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verifier)
BUNDLE_ID = "com.github.miyako.FourDQuickLook"
TEAM = "ABCDE12345"
GROUP = TEAM + "." + BUNDLE_ID + ".ProjectContext"
IDENTITY = "A" * 40


class ReleaseVerificationTests(unittest.TestCase):
    def setUp(self):
        self.root = ROOT / (".release-verification-tests-" + str(uuid.uuid4()))
        self.app = self.root / "4D Quick Look.app"
        appex = self.app / "Contents/PlugIns/4D Preview.appex"
        service_path = "Contents/XPCServices/4D Project Preview.xpc"
        self.bundles = [self.app, appex, self.app / service_path, appex / service_path]
        self.info = {}
        self.entitlements = {}
        for bundle, template in zip(self.bundles, ["Host", "Extension", "ProjectService", "ProjectService"]):
            text = (ROOT / f"Support/{template}-Info.plist").read_text()
            for token, value in [
                ("__BUNDLE_ID__", BUNDLE_ID), ("__VERSION__", "1.2.3"),
                ("__BUILD__", "123"), ("__PROJECT_GROUP__", GROUP),
                ("__CONTENT_TYPES__", "<string>com.4d.4d.form</string>"),
            ]:
                text = text.replace(token, value)
            info = plistlib.loads(text.encode())
            self.info[bundle] = info
            executable = bundle / "Contents/MacOS" / info["CFBundleExecutable"]
            executable.parent.mkdir(parents=True)
            executable.touch()
            entitlements = (ROOT / f"Support/{template}.entitlements").read_text()
            self.entitlements[bundle] = plistlib.loads(
                entitlements.replace("__PROJECT_GROUP__", GROUP).encode())
        self.calls = []
        self.architecture = ("arm64", "x86_64")
        self.bad_signature = None
        self.signature_change = lambda text: text
        self.bad_entitlements = None
        self.entitlement_change = lambda entitlements: entitlements
        self.failed_verification = None

    def tearDown(self):
        shutil.rmtree(self.root)

    def command(self, *args):
        self.calls.append(args)
        bundle = Path(args[-1])
        if args[0] == "plutil":
            return verifier.subprocess.run(args, check=True, stdout=subprocess.PIPE,
                                           stderr=subprocess.PIPE)
        if args[0] == "lipo":
            return subprocess.CompletedProcess(args, 0, " ".join(self.architecture).encode(), b"")
        if "--verify" in args:
            if bundle == self.failed_verification:
                raise subprocess.CalledProcessError(1, args, stderr=b"signature invalid")
            return subprocess.CompletedProcess(args, 0, b"", b"")
        arch = args[args.index("--arch") + 1]
        if "--entitlements" in args:
            entitlements = copy.deepcopy(self.entitlements[bundle])
            if (bundle, arch) == self.bad_entitlements:
                entitlements = self.entitlement_change(entitlements)
            return subprocess.CompletedProcess(args, 0, plistlib.dumps(entitlements), b"")
        signature = (
            f'Identifier={self.info[bundle]["CFBundleIdentifier"]}\n'
            "Authority=Developer ID Application: Test Developer (ABCDE12345)\n"
            f"TeamIdentifier={TEAM}\nTimestamp=Nov 8, 2026\n"
            "CodeDirectory v=20500 size=123 flags=0x10000(runtime) hashes=1+1\n"
        )
        if (bundle, arch) == self.bad_signature:
            signature = self.signature_change(signature)
        return subprocess.CompletedProcess(args, 0, b"", signature.encode())

    def verify(self, group=None):
        for bundle, info in self.info.items():
            with (bundle / "Contents/Info.plist").open("wb") as stream:
                plistlib.dump(info, stream)
        with patch.object(verifier, "run", self.command), contextlib.redirect_stdout(io.StringIO()):
            verifier.verify(self.app, "1.2.3", "123", IDENTITY, BUNDLE_ID, group)

    def test_verifies_all_four_bundles_and_eight_signature_slices(self):
        self.verify()
        checks = [args for args in self.calls if "--verify" in args and "-R" in args]
        self.assertEqual({Path(args[-1]) for args in checks}, set(self.bundles))
        for args in checks:
            self.assertIn("--all-architectures", args)
            self.assertEqual(args[args.index("-R") + 1],
                             f'=anchor apple generic and certificate leaf = H"{IDENTITY}"')
        for flag in ("--verbose=4", "--entitlements"):
            slices = [(Path(args[-1]), args[args.index("--arch") + 1])
                      for args in self.calls if flag in args]
            self.assertEqual(set(slices), {(bundle, arch) for bundle in self.bundles
                                          for arch in ("arm64", "x86_64")})
        self.assertIn("--deep", self.calls[-1])

    def test_codesign_accepts_inline_certificate_pin_requirement(self):
        self.verify()
        check = next(args for args in self.calls if "-R" in args)
        result = subprocess.run(
            [*check[:-1], "/usr/bin/true"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"code failed to satisfy specified code requirement", result.stderr)

    def test_versions_and_bundle_identity_checked_for_every_bundle(self):
        for bundle in self.bundles:
            for key in ("CFBundleVersion", "CFBundleShortVersionString",
                        "CFBundleIdentifier", "CFBundleExecutable", "CFBundlePackageType",
                        "FourDProjectGroupIdentifier"):
                with self.subTest(bundle=bundle, key=key):
                    original = self.info[bundle][key]
                    self.info[bundle][key] = "incorrect"
                    with self.assertRaises(ValueError):
                        self.verify()
                    self.info[bundle][key] = original

    def test_missing_service_rejected(self):
        del self.info[self.bundles[3]]
        with self.assertRaises(subprocess.CalledProcessError):
            self.verify()

    def test_both_architectures_required(self):
        for archs in (("arm64",), ("x86_64",)):
            with self.subTest(archs=archs):
                self.architecture = archs
                with self.assertRaisesRegex(ValueError, "both architectures"):
                    self.verify()

    def test_invalid_signature_on_each_bundle_fails(self):
        for bundle in self.bundles:
            with self.subTest(bundle=bundle):
                self.failed_verification = bundle
                with self.assertRaises(subprocess.CalledProcessError):
                    self.verify()

    def test_each_signature_slice_requires_identity_team_runtime_and_timestamp(self):
        mutations = [
            ("Developer ID Application:", "Apple Development:"),
            ("ABCDE12345", "OTHER12345"),
            ("flags=0x10000(runtime)", "flags=0x0(none)"),
            ("Timestamp=Nov 8, 2026", ""),
            ("Identifier=" + BUNDLE_ID, "Identifier=com.example.wrong"),
        ]
        for bundle in self.bundles:
            for arch in ("arm64", "x86_64"):
                for old, new in mutations:
                    with self.subTest(bundle=bundle, arch=arch, mutation=old):
                        self.bad_signature = (bundle, arch)
                        self.signature_change = lambda text: text.replace(old, new)
                        with self.assertRaises(ValueError):
                            self.verify()

    def test_each_slice_requires_exact_sandbox_and_app_group_policy(self):
        mutations = [
            ("com.apple.security.app-sandbox", False),
            ("com.apple.security.app-sandbox", 1),
            ("com.apple.security.application-groups", []),
            ("com.apple.security.application-groups", ["OTHER12345.foreign"]),
            ("com.apple.security.application-groups", [GROUP, TEAM + ".extra"]),
            ("com.apple.security.inherit", True),
            ("com.apple.security.files.all", True),
            ("com.apple.security.cs.disable-library-validation", True),
        ]
        for bundle in self.bundles:
            for arch in ("arm64", "x86_64"):
                for key, value in mutations:
                    with self.subTest(bundle=bundle, arch=arch, key=key, value=value):
                        self.bad_entitlements = (bundle, arch)
                        self.entitlement_change = lambda entitlements: {**entitlements, key: value}
                        with self.assertRaisesRegex(ValueError, "sandbox policy"):
                            self.verify()

    def test_service_bookmark_entitlement_and_xpc_configuration(self):
        for bundle in self.bundles[2:]:
            for arch in ("arm64", "x86_64"):
                self.bad_entitlements = (bundle, arch)
                self.entitlement_change = lambda entitlements: {
                    key: value for key, value in entitlements.items()
                    if key != "com.apple.security.files.bookmarks.app-scope"}
                with self.assertRaisesRegex(ValueError, "sandbox policy"):
                    self.verify()
            self.bad_entitlements = None
            original = self.info[bundle]["XPCService"]
            self.info[bundle]["XPCService"] = {"ServiceType": "System"}
            with self.assertRaisesRegex(ValueError, "XPC service configuration"):
                self.verify()
            self.info[bundle]["XPCService"] = original

    def test_custom_team_prefixed_group(self):
        custom = TEAM + ".custom.ProjectContext"
        for bundle in self.bundles:
            self.info[bundle]["FourDProjectGroupIdentifier"] = custom
            self.entitlements[bundle]["com.apple.security.application-groups"] = [custom]
        self.verify(custom)
        with self.assertRaisesRegex(ValueError, "belong to the signing team"):
            self.verify("OTHER12345.custom.ProjectContext")

    def test_form_registration_is_required(self):
        host = self.info[self.app]
        appex = self.info[self.bundles[1]]
        attributes = appex["NSExtension"]["NSExtensionAttributes"]
        attributes["QLSupportedContentTypes"] = []
        with self.assertRaisesRegex(ValueError, "4D Form previews"):
            self.verify()
        attributes["QLSupportedContentTypes"] = ["com.4d.4d.form"]
        attributes["QLIsDataBasedPreview"] = True
        with self.assertRaises(ValueError):
            self.verify()
        attributes["QLIsDataBasedPreview"] = False
        form = host["UTImportedTypeDeclarations"][0]
        form["UTTypeTagSpecification"]["public.filename-extension"] = ["4dform"]
        with self.assertRaisesRegex(ValueError, "both filename cases"):
            self.verify()
        form["UTTypeTagSpecification"]["public.filename-extension"] = ["4DForm", "4dform"]
        form["UTTypeConformsTo"] = ["public.data"]
        with self.assertRaisesRegex(ValueError, "JSON conformance"):
            self.verify()
        host["UTImportedTypeDeclarations"] = []
        with self.assertRaisesRegex(ValueError, "exactly once"):
            self.verify()

    def test_non_hash_identity_rejected(self):
        with self.assertRaisesRegex(ValueError, "certificate SHA-1"):
            verifier.verify(self.app, "1.2.3", "123", "-", BUNDLE_ID)


if __name__ == "__main__":
    unittest.main()
