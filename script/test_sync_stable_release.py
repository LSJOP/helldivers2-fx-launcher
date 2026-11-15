#!/usr/bin/env python3
import hashlib
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
import sys
from unittest.mock import patch
import zipfile
import sync_stable_release as sync

class StableReleaseChecks(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.tag = "v9.1.0"
        self.commit = "a" * 40
        self.archive = f"HD2FXNative-{self.tag}-arm64.zip"
        self.dmg = f"HD2FXNative-{self.tag}-macOS-arm64.dmg"
        plist = dict(CFBundleShortVersionString="9.1.0", CFBundleVersion="123",
                     CFBundleIdentifier="com.lsjop.helldivers2fx.native.phase1", SUPublicEDKey="public-key")
        with zipfile.ZipFile(self.root / self.archive, "w") as archive:
            archive.writestr("HD2FXNative.app/Contents/Info.plist", plistlib.dumps(plist))
        (self.root / self.dmg).write_bytes(b"test dmg")
        manifest = dict(schema=2, platform="macOS", architecture="arm64", version="9.1.0", build=123, sourceCommit=self.commit, channel="stable",
                        bundleID=plist["CFBundleIdentifier"], archive=self.archive,
                        length=(self.root / self.archive).stat().st_size,
                        sha256=hashlib.sha256((self.root / self.archive).read_bytes()).hexdigest(),
                        archiveEdSignature="AA==")
        (self.root / "update-manifest.json").write_text(json.dumps(manifest))
        (self.root / "update-manifest.sig").write_text("AA==")
        (self.root / "SHA256SUMS.txt").write_text("".join(
            hashlib.sha256((self.root / name).read_bytes()).hexdigest() + "  " + name + "\n"
            for name in (self.archive, self.dmg)))
        names = [self.archive, self.dmg, "SHA256SUMS.txt", "update-manifest.json", "update-manifest.sig"]
        self.release = dict(tag_name=self.tag, prerelease=False, assets=[
            dict(name=n, state="uploaded", size=(self.root/n).stat().st_size,
                 digest="sha256:" + hashlib.sha256((self.root/n).read_bytes()).hexdigest(),
                 browser_download_url=f"{sync.BASE}/download/{self.tag}/{n}") for n in names])
        for name in ("CHANGELOG.md", "CHANGELOG.zh-CN.md"):
            (self.root / name).write_text("### v9.1.0 — 2026-11-15\n")
        self.root_patch = patch.object(sync, "ROOT", self.root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)
        self.run_patch = patch.object(sync, "run", side_effect=self.command)
        self.run_patch.start()
        self.addCleanup(self.run_patch.stop)

    def command(self, *args):
        if args[0:2] == ("git", "rev-parse"):
            return self.commit
        if args[0:2] == ("git", "show"):
            return ('MARKETING_VERSION = "9.1.0"; CURRENT_PROJECT_VERSION = "123";'
                    if args[2].endswith(".pbxproj") else "HD2_UPDATE_PUBLIC_KEY = public-key")
        if args[0] == "swift":
            return ""
        raise AssertionError(args)

    def test_valid_release(self):
        self.assertEqual(sync.validate_release(self.release, self.root), ("9.1.0", "123", self.dmg))

    def test_prerelease_cannot_sync_stable(self):
        self.release["prerelease"] = True
        with self.assertRaises(ValueError):
            sync.validate_release(self.release, self.root)

    def test_missing_asset_is_rejected(self):
        self.release["assets"].pop()
        with self.assertRaises(ValueError):
            sync.validate_release(self.release, self.root)

    def test_tampered_asset_is_rejected(self):
        (self.root/self.dmg).write_bytes(b"modified")
        with self.assertRaises(ValueError):
            sync.validate_release(self.release, self.root)

    def test_draft_gate_keeps_current_readme_unchanged(self):
        source = Path(__file__).resolve().parents[1]
        originals = {}
        for name in ("README.md", "README.zh-CN.md"):
            originals[name] = (source / name).read_text()
            (self.root / name).write_text(originals[name])
        draft = dict(self.release, draft=True, published_at=None)
        with patch.object(sys, "argv", ["sync", "--tag", self.tag, "--assets-dir", str(self.root)]), \
             patch.object(sync, "release_for", return_value=draft), \
             patch.object(sync, "validate_release", return_value=("9.1.0", "123", self.dmg)), \
             patch.object(sync.subprocess, "run"):
            sync.main()
        for name, content in originals.items():
            self.assertEqual((self.root / name).read_text(), content)

    def test_readme_sync_is_scoped_and_idempotent(self):
        doc = (sync.Path(__file__).resolve().parents[1] / "README.md").read_text()
        expected = sync.updated_readme(doc, "9.1.0", "123", self.dmg, "2026-11-15")
        self.assertIn("Stable Release · v9.1.0", expected)
        self.assertIn("releases/latest/download/" + self.dmg, expected)
        self.assertEqual(sync.updated_readme(expected, "9.1.0", "123", self.dmg, "2026-11-15"), expected)
        self.assertIn("v1.0.1 cannot install the published v1.0.2", expected)
        with self.assertRaises(ValueError):
            sync.updated_readme(doc.replace("<!-- stable-install:end -->", ""), "9.1.0", "123", self.dmg, "2026-11-15")

if __name__ == "__main__":
    unittest.main()
