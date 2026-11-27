#!/usr/bin/env python3
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    sha = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            sha.update(chunk)
    return sha.hexdigest()


def load_bundle_module():
    path = ROOT / "script/rf_fex_bundle.py"
    spec = importlib.util.spec_from_file_location("rf_fex_bundle", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class ReleaseApprovalChecks(unittest.TestCase):
    def setUp(self):
        self.approvals = json.loads((ROOT / "Resources/distribution-approvals-v1.json").read_text())
        self.by_id = {item["id"]: item for item in self.approvals["components"]}

    def test_rights_do_not_bypass_stable_acceptance(self):
        self.assertEqual(self.by_id["rf-fex"]["distributionRights"], "APPROVED_WITH_NOTICES")
        self.assertEqual(self.by_id["rf-fex"]["releaseApproval"], "RC_ONLY_PENDING_LIVE_ACCEPTANCE")
        self.assertEqual(self.by_id["proton-je"]["distributionRights"],
                         "APPROVED_WITH_NOTICES_AND_CORRESPONDING_SOURCE")
        self.assertEqual(self.by_id["proton-je"]["releaseApproval"],
                         "RC_ONLY_PENDING_SOURCE_PUBLICATION_AND_LIVE_ACCEPTANCE")

    def test_proton_binary_and_source_lock(self):
        proton = self.by_id["proton-je"]
        lock = ROOT / "Resources" / proton["sourceLock"]
        record = json.loads(lock.read_text())
        self.assertEqual(digest(lock), proton["sourceLockSHA256"])
        self.assertEqual(record["commit"], proton["sourceCommit"])
        self.assertEqual(len(record["submodules"]), proton["recursiveSubmodules"])
        archive = ROOT / "PrivateResources/Deployment/Proton-JE" / proton["archive"]
        if archive.is_file():
            self.assertEqual(archive.stat().st_size, proton["bytes"])
            self.assertEqual(digest(archive), proton["sha256"])

    def test_release_assembly_excludes_unlicensed_recovered_files(self):
        payload = ROOT / "PrivateResources/Deployment/RF-FEX"
        if not payload.is_dir():
            self.skipTest("private historical payload is not present")
        (ROOT / "build").mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=ROOT / "build", prefix="rf-release-check.") as temporary:
            work = Path(temporary)
            subprocess.run([
                "/usr/bin/python3", "-I", "-B", str(ROOT / "script/rf_fex_bundle.py"), "assemble-release",
                "--manifest", str(ROOT / "Resources/rf-fex-debug-manifest-v1.json"),
                "--approval", str(ROOT / "Resources/distribution-approvals-v1.json"),
                "--resources", str(ROOT / "Resources"), "--payload", str(payload),
                "--destination", str(work / "RF-FEX"),
                "--output-manifest", str(work / "RF-FEX.manifest.json"),
            ], check=True, capture_output=True, text=True)
            result = work / "RF-FEX"
            manifest = json.loads((work / "RF-FEX.manifest.json").read_text())
            self.assertEqual(manifest["payloadFingerprint"], self.by_id["rf-fex"]["releasePayloadFingerprint"])
            self.assertFalse((result / "unshare.py").exists())
            self.assertNotEqual(digest(result / "fex-compat-tool"),
                                "e65da61350150ca527da3da9da5e5ecc1bf97ac9807d2e6ac22a09ffcf6f2045")
            self.assertTrue((result / "LICENSE-FEX.txt").is_file())

    def test_project_wrapper_executes_without_unshare_helper(self):
        source = ROOT / "Resources/rf-fex-release/fex-compat-tool"
        text = source.read_text()
        self.assertNotIn("import unshare", text)
        self.assertNotIn("printenv", text)
        (ROOT / "build").mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=ROOT / "build", prefix="rf-wrapper-check.") as temporary:
            work = Path(temporary)
            tool = work / "tool"
            (tool / "usr/bin").mkdir(parents=True)
            shutil.copyfile(source, tool / "fex-compat-tool")
            (tool / "fex-compat-tool").chmod(0o755)
            shutil.copyfile(ROOT / "PrivateResources/Deployment/RF-FEX/ConfigTemplate.json",
                            tool / "ConfigTemplate.json")
            capture = work / "capture.json"
            fake = tool / "usr/bin/FEX"
            fake.write_text("#!/bin/sh\nprintf '%s\\n' \"$FEX_PORTABLE|$STEAM_COMPAT_MACHINE_ARCHITECTURE|$*\" > \"$HD2_TEST_CAPTURE\"\n")
            fake.chmod(0o755)
            provider = work / "rootfs/graphics_provider.json"
            provider.parent.mkdir()
            provider.write_text("{}\n")
            compat = work / "compat"
            environment = dict(os.environ, STEAM_COMPAT_DATA_PATH=str(compat),
                               STEAM_COMPAT_GRAPHICS_PROVIDER=str(provider), HD2_TEST_CAPTURE=str(capture))
            environment.pop("LD_PRELOAD", None)
            subprocess.run([str(tool / "fex-compat-tool"), "run", "--", "/bin/true", "argument"],
                           env=environment, check=True)
            self.assertEqual(capture.read_text().strip(), "1|aarch64-linux-gnu|/bin/true argument")
            config = (compat / "fex-emu/Config.json").read_text()
            self.assertIn(str(tool), config)
            self.assertIn(str(provider.parent), config)

    def test_unicode_path_is_not_mistaken_for_a_symlink(self):
        module = load_bundle_module()
        (ROOT / "build").mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=ROOT / "build", prefix="rf-资源-") as temporary:
            root = Path(temporary) / "组件"
            root.mkdir()
            self.assertFalse(module.has_symlink_component(root))
            linked = Path(temporary) / "linked"
            linked.symlink_to(root, target_is_directory=True)
            self.assertTrue(module.has_symlink_component(linked))


if __name__ == "__main__":
    unittest.main()
