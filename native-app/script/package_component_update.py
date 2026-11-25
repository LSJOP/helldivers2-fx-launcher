#!/usr/bin/env python3
"""Create schema-3 artifacts from an already signed target App in private staging."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import stat
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BUNDLE_ID = "com.lsjop.helldivers2fx.native.phase1"
REPOSITORY = "https://github.com/LSJOP/helldivers2-fx-launcher/releases/download/"
MAX_BYTES = 2_147_483_648
DESTINATIONS = {
    "rf-fex": "Contents/Resources/Deployment/RF-FEX",
    "proton-je": "Contents/Resources/Deployment/Proton-JE",
    "runtime4": "Contents/Resources/Deployment/SteamLinuxRuntime_4",
}


def digest(path):
    with path.open("rb") as source:
        sha = hashlib.sha256()
        for chunk in iter(lambda: source.read(1_048_576), b""):
            sha.update(chunk)
        return sha.hexdigest()


def inventory(directory):
    records = []
    size = 0
    for path in directory.rglob("*"):
        name = path.relative_to(directory).as_posix()
        info = path.lstat()
        if stat.S_ISLNK(info.st_mode):
            target = os.readlink(path)
            size += len(target.encode())
            payload = "l\0" + target
        elif stat.S_ISDIR(info.st_mode):
            payload = "d"
        elif stat.S_ISREG(info.st_mode):
            size += info.st_size
            payload = f"f\0{info.st_size}\0{digest(path)}"
        else:
            raise ValueError("Unexpected file type in target")
        if size > MAX_BYTES or info.st_mode & 0o7000:
            raise ValueError("Invalid target inventory")
        records.append((name.encode(), f"{name}\0{info.st_mode & 0o777}\0{payload}\0".encode()))
    if not records or len(records) >= 19_999:
        raise ValueError("Invalid target entry count")
    sha = hashlib.sha256()
    for _, record in sorted(records):
        sha.update(record)
    return sha.hexdigest(), size


def zip_app(app, destination):
    subprocess.run(["/usr/bin/ditto", "-c", "-k", "--norsrc", "--keepParent", str(app), str(destination)], check=True)
    if not 0 < destination.stat().st_size <= MAX_BYTES:
        raise ValueError("Archive length exceeds protocol limit")
    with zipfile.ZipFile(destination) as packed:
        if sum(item.file_size for item in packed.infolist()) > MAX_BYTES:
            raise ValueError("Expanded archive exceeds protocol limit")


def asset(path, tag):
    with zipfile.ZipFile(path) as packed:
        expanded = sum(item.file_size for item in packed.infolist())
    return dict(url=f"{REPOSITORY}{tag}/{path.name}", length=path.stat().st_size,
                sha256=digest(path), expandedBytes=expanded)


def reusable_assets(previous, info):
    if previous is None:
        return {}
    manifest_path = previous / "update-manifest.json"
    if manifest_path.stat().st_size > 65_536:
        raise ValueError("Previous manifest exceeds the protocol limit")
    old = json.loads(manifest_path.read_bytes())
    subprocess.run(["/usr/bin/swift", str(ROOT.parent / "script/verify_stable_signatures.swift"),
                    str(previous), info["SUPublicEDKey"], old["archive"]], check=True)
    if old["schema"] != 3 or old["bundleID"] != info["CFBundleIdentifier"]:
        raise ValueError("Incompatible previous component catalogue")
    return {item["id"]: item for item in old["components"]["modules"]}


def published_asset(item, expected_name):
    source = item["url"]
    match = re.fullmatch(re.escape(REPOSITORY) +
                         r"(v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?)/" + re.escape(expected_name), source)
    if not match or not 0 < item["length"] <= MAX_BYTES:
        raise ValueError("Invalid previous component URL or length")
    release = json.loads(subprocess.check_output(["gh", "api",
        "repos/LSJOP/helldivers2-fx-launcher/releases/tags/" + match[1]], text=True))
    matches = [entry for entry in release["assets"] if entry["name"] == expected_name]
    if (release["tag_name"] != match[1] or release["draft"] or len(matches) != 1
            or matches[0]["browser_download_url"] != source or matches[0]["size"] != item["length"]
            or matches[0]["state"] != "uploaded" or matches[0].get("digest") != "sha256:" + item["sha256"]):
        raise ValueError("Referenced previous component bytes are unavailable")
    return item


def run(app, output, minimum, local_test, previous=None, dmg=False, signing_key=None):
    if app.name != "HD2FXNative.app" or app.resolve() != app or output.exists():
        raise ValueError("An absolute signed App path and a new output directory are required")
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    resources = app / "Contents/Resources"
    if local_test:
        if (info.get("CFBundleIdentifier") != BUNDLE_ID + ".update-test"
            or not re.fullmatch(r"\d+\.\d+\.\d+-update-test\.[1-9]\d*", info["CFBundleShortVersionString"])
            or not output.resolve().is_relative_to(ROOT / "build")
            or any(os.environ.get(name) for name in ("CI", "GITHUB_ACTIONS"))):
            raise ValueError("Private fixtures require the isolated local test identity and ignored build directory")
    else:
        # The current deployment catalogue rejects every historical unapproved asset.
        subprocess.run(["/usr/bin/python3", "-I", "-B", str(ROOT / "script/deployment_archives.py"),
                        "reject", "--catalogue", str(ROOT / "Resources/deployment-components-v1.json"),
                        "--destination", str(resources)], check=True)
        if (resources / "Deployment/RF-FEX").exists() or (resources / "Deployment/RF-FEX.manifest.json").exists():
            raise ValueError("RF redistribution is unapproved")
        if info.get("CFBundleIdentifier") != BUNDLE_ID:
            raise ValueError("Wrong application identifier")
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    arch = subprocess.check_output(["/usr/bin/lipo", "-archs", str(app / "Contents/MacOS/HD2FXNative")], text=True).strip()
    if arch != "arm64":
        raise ValueError("Expected an arm64 target")
    version = info["CFBundleShortVersionString"]
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", version):
        raise ValueError("Malformed target version")
    build = int(info["CFBundleVersion"])
    if not 0 < minimum < build:
        raise ValueError("Invalid minimum base build")
    tag = "v" + version
    target_hash, target_size = inventory(app)
    catalogue = json.loads((resources / "deployment-components-v1.json").read_text())
    versions = {item["name"]: item["version"] for item in catalogue["bundleArchives"]}
    versions["rf-fex"] = json.loads((resources / "Deployment/RF-FEX.manifest.json").read_text())["version"]
    versions["proton-je"], versions["runtime4"] = versions["Proton-JE"], versions["SteamLinuxRuntime_4"]

    if local_test and previous:
        raise ValueError("Local fixtures cannot reference public assets")
    previous_modules = reusable_assets(previous, info)
    output.mkdir(mode=0o700)
    try:
        full = output / f"HD2FXNative-{tag}-arm64.zip"
        zip_app(app, full)
        full_asset = asset(full, tag)
        if full_asset["expandedBytes"] != target_size:
            raise ValueError("Full ZIP inventory does not match the signed target")
        with tempfile.TemporaryDirectory(dir=output) as temporary:
            work = Path(temporary)
            core = work / "core" / app.name
            shutil.copytree(app, core, symlinks=True)
            modules = []
            for identifier, relative in DESTINATIONS.items():
                component = app / relative
                tree, unpacked = inventory(component)
                part = work / identifier / app.name
                (part / relative).parent.mkdir(parents=True)
                shutil.move(core / relative, part / relative)
                filename = output / f"{identifier}-{tree}.zip"
                previous_item = previous_modules.get(identifier)
                if previous_item and previous_item["treeSHA256"] == tree:
                    packed = published_asset(previous_item["artifact"], filename.name)
                else:
                    zip_app(part, filename)
                    packed = asset(filename, tag)
                if packed["expandedBytes"] != unpacked:
                    raise ValueError("Component ZIP inventory does not match the signed target")
                modules.append(dict(id=identifier, version=versions[identifier], path=relative,
                                    treeSHA256=tree, artifact=packed))
            core_zip = output / f"HD2FXNative-{tag}-core-arm64.zip"
            zip_app(core, core_zip)
        core_asset = asset(core_zip, tag)
        if core_asset["expandedBytes"] + sum(item["artifact"]["expandedBytes"] for item in modules) != target_size:
            raise ValueError("Core ZIP inventory does not match the signed target")
        with tempfile.TemporaryDirectory(dir=output) as temporary:
            work = Path(temporary)
            assembled = work / app.name
            subprocess.run(["/usr/bin/ditto", "-x", "-k", str(core_zip), str(work)], check=True)
            for item in modules:
                relative = item["path"]
                archive = output / item["artifact"]["url"].rsplit("/", 1)[-1]
                if archive.is_file():
                    stage = work / item["id"]
                    stage.mkdir()
                    subprocess.run(["/usr/bin/ditto", "-x", "-k", str(archive), str(stage)], check=True)
                    installed_part = stage / app.name / relative
                    if inventory(installed_part)[0] != item["treeSHA256"]:
                        raise ValueError("Round-trip component inventory mismatch")
                    shutil.move(installed_part, assembled / relative)
                else:
                    shutil.copytree(app / relative, assembled / relative, symlinks=True)
            if inventory(assembled) != (target_hash, target_size):
                raise ValueError("Round-trip target inventory mismatch")
            subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(assembled)], check=True)
        commit = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
        manifest = dict(schema=3, bundleID=info["CFBundleIdentifier"], version=version, build=build,
                        channel="preview" if "-" in version else "stable", platform="macOS", architecture=arch,
                        minimumSystemVersion=info["LSMinimumSystemVersion"], archive=full.name,
                        length=full_asset["length"], sha256=full_asset["sha256"], sourceCommit=commit,
                        components=dict(protocolVersion=1, minimumBaseBuild=minimum, targetTreeSHA256=target_hash,
                                        targetBytes=target_size, core=core_asset, modules=modules))
        (output / "update-manifest.json").write_text(json.dumps(manifest, sort_keys=True, separators=(",", ":")) + "\n")
        if signing_key:
            operator = ROOT / "script/update_signing.swift"
            public_key = subprocess.check_output(["/usr/bin/swift", str(operator), "public", str(signing_key)], text=True).strip()
            if public_key != info.get("SUPublicEDKey"):
                raise ValueError("Signing key does not match the App trust root")
            signature = subprocess.check_output(["/usr/bin/swift", str(operator), "sign", str(signing_key),
                                                 str(output / "update-manifest.json")], text=True)
            (output / "update-manifest.sig").write_text(signature)
            subprocess.run(["/usr/bin/swift", str(ROOT.parent / "script/verify_stable_signatures.swift"),
                            str(output), public_key, full.name], check=True)
        print(f"App {target_size} bytes, Full ZIP {full.stat().st_size} bytes, Core ZIP {core_zip.stat().st_size} bytes")
        if dmg:
            image = output / f"HD2FXNative-{tag}-macOS-arm64.dmg"
            subprocess.run(["/usr/bin/hdiutil", "create", "-srcfolder", str(app), "-format", "UDZO",
                            "-volname", "HELLDIVERS 2 FX Launcher", str(image)], check=True)
            print(f"DMG {image.stat().st_size} bytes")
        artifacts = sorted(path for path in output.iterdir() if path.is_file())
        (output / "SHA256SUMS.txt").write_text("".join(f"{digest(path)}  {path.name}\n" for path in artifacts))
    except BaseException:
        shutil.rmtree(output)
        raise


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--minimum-base-build", type=int, required=True)
    parser.add_argument("--local-test", action="store_true")
    parser.add_argument("--previous", type=Path, help="Previously signed manifest and signature directory")
    parser.add_argument("--dmg", action="store_true")
    parser.add_argument("--signing-key", type=Path, help="Reviewed existing operator key matching the App trust root")
    args = parser.parse_args()
    run(args.app.absolute(), args.output.absolute(), args.minimum_base_build, args.local_test,
        args.previous, args.dmg, args.signing_key)
