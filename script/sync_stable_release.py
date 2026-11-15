#!/usr/bin/env python3
"""Verify a GitHub release and synchronize the stable blocks in both READMEs."""
import argparse
import base64
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import zipfile
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
REPO = "LSJOP/helldivers2-fx-launcher"
BASE = f"https://github.com/{REPO}/releases"
TAG = re.compile(r"v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)")

def run(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()

def release_for(tag):
    if tag:
        return json.loads(run("gh", "api", f"repos/{REPO}/releases/tags/{tag}"))
    return json.loads(run("gh", "api", f"repos/{REPO}/releases/latest"))

def validate_release(release, assets_dir):
    tag = release["tag_name"]
    if not TAG.fullmatch(tag) or release["prerelease"]:
        raise ValueError("A stable vMAJOR.MINOR.PATCH release is required")
    version = tag[1:]
    dmg = f"HD2FXNative-{tag}-macOS-arm64.dmg"
    archive = f"HD2FXNative-{tag}-arm64.zip"
    names = [dmg, archive, "SHA256SUMS.txt", "update-manifest.json", "update-manifest.sig"]
    assets = release["assets"]
    for name in names:
        matches = [item for item in assets if item["name"] == name]
        if len(matches) != 1 or matches[0]["state"] != "uploaded" or matches[0]["size"] <= 0 or matches[0]["browser_download_url"] != f"{BASE}/download/{tag}/{name}":
            raise ValueError(f"Missing, duplicate or invalid release asset: {name}")
        file = assets_dir / name
        digest = hashlib.sha256(file.read_bytes()).hexdigest()
        if file.stat().st_size != matches[0]["size"] or matches[0].get("digest") != "sha256:" + digest:
            raise ValueError(f"Release asset checksum mismatch: {name}")
    sums = (assets_dir / "SHA256SUMS.txt").read_text()
    for name in (dmg, archive):
        expected = hashlib.sha256((assets_dir / name).read_bytes()).hexdigest()
        if not re.search(r"(?m)^" + expected + r"\s+\*?(?:\./)?" + re.escape(name) + r"$", sums):
            raise ValueError(f"Checksum file does not match {name}")
    manifest = json.loads((assets_dir / "update-manifest.json").read_bytes())
    commit = run("git", "rev-parse", f"{tag}^{{commit}}")
    source = run("git", "show", f"{commit}:native-app/HD2FXNative.xcodeproj/project.pbxproj")
    versions = re.findall(r'MARKETING_VERSION = "([^"]+)"', source)
    builds = re.findall(r'CURRENT_PROJECT_VERSION = "([^"]+)"', source)
    if not versions or set(versions) != {version} or not builds or set(builds) != {str(manifest["build"])}:
        raise ValueError("Tagged App project version or build does not match release")
    if (manifest.get("schema") != 2 or manifest.get("platform") != "macOS"
            or manifest.get("architecture") != "arm64"
            or manifest.get("version") != version or manifest.get("sourceCommit") != commit
            or manifest.get("channel") != "stable" or manifest.get("archive") != archive
            or manifest.get("bundleID") != "com.lsjop.helldivers2fx.native.phase1"
            or manifest.get("length") != (assets_dir / archive).stat().st_size
            or manifest.get("sha256") != hashlib.sha256((assets_dir / archive).read_bytes()).hexdigest()):
        raise ValueError("Update manifest does not match the tag and archive")
    with zipfile.ZipFile(assets_dir / archive) as zipped:
        plist = plistlib.loads(zipped.read("HD2FXNative.app/Contents/Info.plist"))
    if (plist.get("CFBundleShortVersionString") != version
            or plist.get("CFBundleVersion") != str(manifest["build"])
            or plist.get("CFBundleIdentifier") != manifest["bundleID"]):
        raise ValueError("Packaged App identity does not match release")
    config = run("git", "show", f"{commit}:native-app/Config/Updates.xcconfig")
    key_match = re.search(r"(?m)^HD2_UPDATE_PUBLIC_KEY\s*=\s*(\S+)\s*$", config)
    if not key_match or plist.get("SUPublicEDKey") != key_match.group(1):
        raise ValueError("App update key does not match the tagged source")
    base64.b64decode((assets_dir / "update-manifest.sig").read_text().strip(), validate=True)
    base64.b64decode(manifest["archiveEdSignature"], validate=True)
    run("swift", str(ROOT / "script/verify_stable_signatures.swift"), str(assets_dir), key_match.group(1), archive)
    for name in ("CHANGELOG.md", "CHANGELOG.zh-CN.md"):
        if not re.search(r"(?m)^### " + re.escape(tag) + r"\s+[—-]\s+\d{4}-\d{2}-\d{2}\s*$", (ROOT / name).read_text()):
            raise ValueError(f"{name} is missing the released version and date")
    return version, str(manifest["build"]), dmg

def replace_block(text, name, transform):
    pattern = r"(<!-- stable-" + name + r":start -->\n)(.*?)(\n<!-- stable-" + name + r":end -->)"
    if len(re.findall(pattern, text, flags=re.S)) != 1:
        raise ValueError(f"Expected one {name} block")
    return re.sub(pattern, lambda match: match[1] + transform(match[2]) + match[3], text, flags=re.S)

def updated_readme(text, version, build, dmg, date):
    def substitute(pattern, replacement, block, expected):
        updated, count = re.subn(pattern, replacement, block)
        if count != expected:
            raise ValueError(f"Expected {expected} occurrences for {pattern}, found {count}")
        return updated
    def download(block):
        block = substitute(r"Stable Release · v\d+\.\d+\.\d+", f"Stable Release · v{version}", block, 1)
        return substitute(r"releases/latest/download/HD2FXNative-v\d+\.\d+\.\d+-macOS-arm64\.dmg",
                          f"releases/latest/download/{dmg}", block, 2)
    def install(block):
        block = substitute(r"(`)[0-9]+\.[0-9]+\.[0-9]+(`)", rf"\g<1>{version}\2", block, 1)
        return substitute(r"(build `|构建 `)[0-9]+(`)", rf"\g<1>{build}\2", block, 1)
    def history(block):
        block = substitute(r"\[v\d+\.\d+\.\d+ — \d{4}-\d{2}-\d{2}\]", f"[v{version} — {date}]", block, 1)
        return substitute(r"(build `|构建 `)[0-9]+(`)", rf"\g<1>{build}\2", block, 1)
    for name, transform in (("download", download), ("install", install), ("version", history)):
        text = replace_block(text, name, transform)
    return text

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", help="Stable release tag, including an unpublished draft")
    parser.add_argument("--assets-dir", type=Path, help="Directory containing downloaded release assets")
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    release = release_for(args.tag)
    if not TAG.fullmatch(release["tag_name"]) or release["prerelease"] or (args.tag and release["tag_name"] != args.tag):
        raise ValueError("Requested release is not the specified stable tag")
    if release["draft"] and not args.tag:
        raise ValueError("Latest release is a draft")
    with tempfile.TemporaryDirectory(prefix="hd2-stable-release-") as temp:
        directory = args.assets_dir or Path(temp)
        if not args.assets_dir:
            run("gh", "release", "download", release["tag_name"], "--repo", REPO, "--dir", str(directory))
        version, build, dmg = validate_release(release, directory)
    if not release["draft"]:
        request = urllib.request.Request(f"{BASE}/download/{release['tag_name']}/{dmg}",
                                         headers={"Range": "bytes=0-0", "User-Agent": "HD2FXNative-release-check"})
        with urllib.request.urlopen(request, timeout=30) as response:
            destination = urllib.parse.urlparse(response.geturl())
            if response.status not in (200, 206) or destination.scheme != "https" or destination.hostname not in ("github.com", "release-assets.githubusercontent.com"):
                raise ValueError("Public DMG download URL is unavailable")
            response.read(1)
    subprocess.run(["python3", "native-app/script/check_localization.py"], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    when = release.get("published_at")
    date = datetime.datetime.fromisoformat(when.replace("Z", "+00:00")).astimezone(datetime.timezone(datetime.timedelta(hours=8))).date().isoformat() if when else datetime.date.today().isoformat()
    changed = []
    for name in ("README.md", "README.zh-CN.md"):
        path = ROOT / name
        original = path.read_text()
        updated = updated_readme(original, version, build, dmg, date)
        if updated != original:
            changed.append(name)
            if args.write:
                path.write_text(updated)
                if updated_readme(path.read_text(), version, build, dmg, date) != updated:
                    raise ValueError(f"README synchronization failed: {name}")
    if changed and not args.write:
        if not release["draft"]:
            raise ValueError("Stable README blocks are out of date: " + ", ".join(changed))
        print(f"Verified draft {release['tag_name']} build {build}; both README blocks can be synchronized after publication")
        return
    print(f"Verified {release['tag_name']} build {build}; README " + (", ".join(changed) if changed else "already synchronized"))

if __name__ == "__main__":
    main()
