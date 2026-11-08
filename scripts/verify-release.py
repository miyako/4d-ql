#!/usr/bin/env python3
"""Verify the signed release before notarization/packaging (no credentials needed).

Usage: scripts/verify-release.py --app "build/4D Quick Look.app" \
    --version 1.2.3 --build 123 --identity <certificate SHA-1>
"""

import argparse
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys


def require(condition, message):
    if not condition:
        raise ValueError(message)


def run(*args):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE)


def verify(app, version, build, identity, bundle_id, project_group=None):
    require(re.fullmatch(r"[0-9A-Fa-f]{40}", identity), "Expected certificate SHA-1")
    appex = app / "Contents/PlugIns/4D Preview.appex"
    service_path = "Contents/XPCServices/4D Project Preview.xpc"
    bundles = [
        (app, bundle_id, "FourDQuickLookHost", "APPL", False),
        (appex, bundle_id + ".Preview", "FourDQuickLookExtension", "XPC!", False),
        (app / service_path, bundle_id + ".ProjectPreviewService",
         "FourDProjectPreviewService", "XPC!", True),
        (appex / service_path, bundle_id + ".ProjectPreviewService",
         "FourDProjectPreviewService", "XPC!", True),
    ]
    # Pin every signature to the identity selected by the build step, not just
    # an arbitrary Developer ID certificate belonging to the same team.
    requirement = f'=anchor apple generic and certificate leaf = H"{identity}"'
    team = None
    group = None
    plists = []
    for bundle, identifier, executable, package_type, is_service in bundles:
        label = str(bundle)
        info_path = bundle / "Contents/Info.plist"
        run("plutil", "-lint", "-s", str(info_path))
        with info_path.open("rb") as stream:
            info = plistlib.load(stream)
        plists.append(info)
        for key, expected in [
            ("CFBundleIdentifier", identifier), ("CFBundleExecutable", executable),
            ("CFBundlePackageType", package_type),
            ("CFBundleShortVersionString", version), ("CFBundleVersion", build),
        ]:
            require(info.get(key) == expected, f"{label}: {key} must be {expected!r}")
        if is_service:
            require(info.get("XPCService") == {
                "ServiceType": "Application", "RunLoopType": "NSRunLoop",
            }, f"{label}: invalid XPC service configuration")
        binary = bundle / "Contents/MacOS" / executable
        archs = run("lipo", "-archs", str(binary)).stdout.decode().split()
        require(set(archs) == {"arm64", "x86_64"}, f"{label}: expected both architectures")
        run("codesign", "--verify", "--strict", "--all-architectures",
            "-R", requirement, str(bundle))
        for arch in ("arm64", "x86_64"):
            output = run("codesign", "-d", "--arch", arch, "--verbose=4", str(bundle))
            signature = output.stderr.decode()
            fields = dict(line.split("=", 1) for line in signature.splitlines() if "=" in line)
            require(fields.get("Identifier") == identifier,
                    f"{label} ({arch}): signing identifier mismatch")
            require(any(line.startswith("Authority=Developer ID Application:")
                        for line in signature.splitlines()),
                    f"{label} ({arch}): not Developer ID Application signed")
            require(re.search(r"^CodeDirectory .*flags=.*\bruntime\b", signature, re.M),
                    f"{label} ({arch}): hardened runtime missing")
            require(bool(fields.get("Timestamp")),
                    f"{label} ({arch}): secure timestamp missing")
            signed_team = fields.get("TeamIdentifier", "")
            require(re.fullmatch(r"[A-Z0-9]{10}", signed_team),
                    f"{label} ({arch}): invalid signing team")
            if team is None:
                team = signed_team
                group = project_group or f"{team}.{bundle_id}.ProjectContext"
                require(group.startswith(team + "."),
                        "Project app group must belong to the signing team")
            require(signed_team == team, f"{label} ({arch}): signing team mismatch")
            require(info.get("FourDProjectGroupIdentifier") == group,
                    f"{label}: project group metadata mismatch")
            entitlements = plistlib.loads(run(
                "codesign", "-d", "--arch", arch, "--entitlements", "-", "--xml",
                str(bundle)).stdout)
            expected_entitlements = {
                "com.apple.security.app-sandbox": True,
                "com.apple.security.files.user-selected.read-only": True,
                "com.apple.security.application-groups": [group],
            }
            if is_service:
                expected_entitlements["com.apple.security.files.bookmarks.app-scope"] = True
            # An exact policy also rejects sandbox inheritance, broad filesystem
            # grants and hardened-runtime exceptions that these bundles do not need.
            require(entitlements == expected_entitlements and
                    all(entitlements.get(key) is True for key, value
                        in expected_entitlements.items() if value is True),
                    f"{label} ({arch}): entitlements differ from sandbox policy")
        print(f"Verified universal Developer ID bundle: {bundle}")

    host_info, extension_info = plists[:2]
    extension = extension_info.get("NSExtension", {})
    require(extension.get("NSExtensionPointIdentifier") == "com.apple.quicklook.preview"
            and extension.get("NSExtensionPrincipalClass") == "FourDPreviewProvider",
            "Quick Look extension registration mismatch")
    attributes = extension.get("NSExtensionAttributes", {})
    require(attributes.get("QLIsDataBasedPreview") is True and
            "com.4d.4d.form" in attributes.get("QLSupportedContentTypes", []),
            "Quick Look must register data-based 4D Form previews")
    forms = [item for item in host_info.get("UTImportedTypeDeclarations", [])
             if item.get("UTTypeIdentifier") == "com.4d.4d.form"]
    require(len(forms) == 1, "Host must import the 4D Form UTI exactly once")
    require("public.json" in forms[0].get("UTTypeConformsTo", []) and
            set(forms[0].get("UTTypeTagSpecification", {}).get(
                "public.filename-extension", [])) == {"4DForm", "4dform"},
            "4D Form UTI must register JSON conformance and both filename cases")
    run("codesign", "--verify", "--deep", "--strict", "--all-architectures", str(app))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=Path("build/4D Quick Look.app"))
    parser.add_argument("--version", default=os.environ.get("VERSION"), required="VERSION" not in os.environ)
    parser.add_argument("--build", default=os.environ.get("BUILD"), required="BUILD" not in os.environ)
    parser.add_argument("--identity", default=os.environ.get("SIGN_IDENTITY"),
                        required="SIGN_IDENTITY" not in os.environ)
    parser.add_argument("--bundle-id", default=os.environ.get(
        "BUNDLE_ID", "com.github.miyako.FourDQuickLook"))
    parser.add_argument("--project-group", default=os.environ.get("PROJECT_GROUP") or None)
    args = parser.parse_args()
    try:
        verify(args.app, args.version, args.build, args.identity, args.bundle_id, args.project_group)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"::error::Release verification failed: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError):
            print(error.stderr.decode(errors="replace"), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
