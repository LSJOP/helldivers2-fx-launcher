#!/usr/bin/env python3
"""Import, verify, and assemble the reviewed RF runtime payload.

The binary payload is deliberately ignored by Git.  This tool accepts an explicit
historical evidence directory once, validates every input against the reviewed
manifest, sanitizes the compatibility wrapper, and creates a self-contained local
Debug resource directory. The Debug importer never authorizes Release use.
The release assembler additionally requires the reviewed approval record, removes
the two recovered files whose rights were not established, and overlays the
project-owned wrapper plus the FEX MIT notice.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import sys
import uuid


MAX_FILE = 8 * 1024 * 1024
MAX_TOTAL = 48 * 1024 * 1024
WRAPPER_DEBUG_LINE = b"subprocess.call(['/usr/bin/printenv'])"


class BundleError(RuntimeError):
    pass


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def safe_relative(value: str) -> bool:
    path = PurePosixPath(value)
    return (
        bool(value)
        and not path.is_absolute()
        and "\\" not in value
        and "\n" not in value
        and all(part not in ("", ".", "..") for part in path.parts)
    )


def has_symlink_component(path: Path) -> bool:
    """Check existing path components without comparing Unicode spellings."""
    current = path.absolute()
    while True:
        if current.is_symlink():
            return True
        if current.parent == current:
            return False
        current = current.parent


def load_manifest(path: Path) -> dict:
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 1024 * 1024:
        raise BundleError("manifest is missing, linked, or too large")
    manifest = json.loads(path.read_text(encoding="utf-8"))
    files = manifest.get("files")
    if (
        manifest.get("schema") != 1
        or manifest.get("expectedFiles") != 41
        or manifest.get("debugOnly") is not True
        or manifest.get("distributionApproved") is not False
        or not isinstance(files, list)
        or len(files) != 41
    ):
        raise BundleError("manifest policy or file count is invalid")
    seen: set[str] = set()
    total = 0
    for item in files:
        relative = item.get("path")
        source = item.get("sourceRelativePath")
        size = item.get("bytes")
        mode = item.get("mode")
        if (
            not isinstance(relative, str)
            or not safe_relative(relative)
            or relative in seen
            or item.get("name") != PurePosixPath(relative).name
            or not isinstance(source, str)
            or not safe_relative(source)
            or not isinstance(size, int)
            or size < 0
            or size > MAX_FILE
            or mode not in (420, 493)
            or not isinstance(item.get("sha256"), str)
            or len(item["sha256"]) != 64
            or any(c not in "0123456789abcdef" for c in item["sha256"])
            or not isinstance(item.get("sourceSHA256"), str)
            or len(item["sourceSHA256"]) != 64
            or item.get("publicDistributionAllowed") is not False
            or item.get("controlledDebugOnly") is not True
        ):
            raise BundleError(f"invalid manifest entry: {relative!r}")
        seen.add(relative)
        total += size
    if total > MAX_TOTAL:
        raise BundleError("manifest payload is too large")
    return manifest


def load_release_manifest(path: Path, approval_path: Path) -> dict:
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 1024 * 1024:
        raise BundleError("release manifest is missing, linked, or too large")
    manifest = json.loads(path.read_text(encoding="utf-8"))
    approval_document = json.loads(approval_path.read_text(encoding="utf-8"))
    matches = [item for item in approval_document.get("components", []) if item.get("id") == "rf-fex"]
    if (
        len(matches) != 1
        or manifest.get("schema") != 1
        or manifest.get("packageID") != "rf-fex-reviewed-release-v1"
        or manifest.get("expectedFiles") != 41
        or manifest.get("debugOnly") is not False
        or manifest.get("distributionApproved") is not True
        or manifest.get("releaseStatus") != "RC_ONLY_PENDING_LIVE_ACCEPTANCE"
        or manifest.get("payloadFingerprint") != matches[0].get("releasePayloadFingerprint")
        or file_digest(path) != "f491ba43783d986a183592bb5fb7f3f0fc4b338e80c8b3f1089a764914135bca"
    ):
        raise BundleError("release manifest is not the compiled-in reviewed candidate")
    files = manifest.get("files")
    if not isinstance(files, list) or len(files) != 41:
        raise BundleError("release inventory is missing")
    for item in files:
        if item.get("publicDistributionAllowed") is not True or item.get("controlledDebugOnly") is not False:
            raise BundleError("release inventory contains a controlled-Debug entry")
    return manifest


def file_digest(path: Path) -> str:
    sha = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            sha.update(chunk)
    return sha.hexdigest()


def load_release_approval(path: Path, manifest_path: Path, manifest: dict) -> dict:
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 1024 * 1024:
        raise BundleError("distribution approval is missing, linked, or too large")
    approval_document = json.loads(path.read_text(encoding="utf-8"))
    matches = [item for item in approval_document.get("components", []) if item.get("id") == "rf-fex"]
    if len(matches) != 1:
        raise BundleError("RF distribution approval is missing or ambiguous")
    approval = matches[0]
    if (
        approval_document.get("schema") != 1
        or approval.get("distributionRights") != "APPROVED_WITH_NOTICES"
        or approval.get("releaseApproval") != "RC_ONLY_PENDING_LIVE_ACCEPTANCE"
        or approval.get("baseManifest") != manifest_path.name
        or approval.get("baseManifestSHA256") != file_digest(manifest_path)
        or approval.get("basePayloadFingerprint") != manifest.get("payloadFingerprint")
        or approval.get("excludedRecoveredFiles") != ["fex-compat-tool", "unshare.py"]
        or approval.get("releaseExpectedFiles") != 41
        or approval.get("releaseExpectedBytes") != 26_325_773
        or not isinstance(approval.get("releaseOverlay"), list)
        or len(approval["releaseOverlay"]) != 2
    ):
        raise BundleError("RF distribution approval does not bind the reviewed inputs")
    return approval


def source_bytes(root: Path, item: dict) -> bytes:
    source = root / item["sourceRelativePath"]
    try:
        metadata = source.lstat()
    except FileNotFoundError as error:
        raise BundleError(f"missing source: {item['sourceRelativePath']}") from error
    if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode) or metadata.st_nlink != 1:
        raise BundleError(f"unsafe source: {item['sourceRelativePath']}")
    if has_symlink_component(source):
        raise BundleError(f"linked source parent: {item['sourceRelativePath']}")
    data = source.read_bytes()
    if digest(data) != item["sourceSHA256"]:
        raise BundleError(f"source hash mismatch: {item['sourceRelativePath']}")
    transform = item.get("transform", "none")
    if transform == "remove-wrapper-printenv-v1":
        if data.count(WRAPPER_DEBUG_LINE) != 1:
            raise BundleError("wrapper debug statement is absent or ambiguous")
        data = data.replace(WRAPPER_DEBUG_LINE, b"")
    elif transform != "none":
        raise BundleError(f"unknown transform: {transform}")
    if len(data) != item["bytes"] or digest(data) != item["sha256"]:
        raise BundleError(f"transformed payload mismatch: {item['path']}")
    return data


def actual_files(root: Path) -> dict[str, Path]:
    if root.is_symlink() or not root.is_dir() or has_symlink_component(root):
        raise BundleError("payload root is missing or linked")
    actual: dict[str, Path] = {}
    for directory, directories, files in os.walk(root, followlinks=False):
        base = Path(directory)
        for name in directories:
            child = base / name
            if child.is_symlink():
                raise BundleError(f"linked directory: {child.relative_to(root)}")
        for name in files:
            child = base / name
            metadata = child.lstat()
            relative = child.relative_to(root).as_posix()
            if not safe_relative(relative) or not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
                raise BundleError(f"unsafe payload file: {relative}")
            actual[relative] = child
    return actual


def verify_payload(root: Path, manifest: dict) -> str:
    expected = {item["path"]: item for item in manifest["files"]}
    actual = actual_files(root)
    if set(actual) != set(expected):
        missing = sorted(set(expected) - set(actual))
        extra = sorted(set(actual) - set(expected))
        raise BundleError(f"payload inventory mismatch missing={missing} extra={extra}")
    tree = hashlib.sha256()
    for relative in sorted(expected):
        item = expected[relative]
        file = actual[relative]
        data = file.read_bytes()
        mode = stat.S_IMODE(file.stat().st_mode)
        if len(data) != item["bytes"] or digest(data) != item["sha256"] or mode != item["mode"]:
            raise BundleError(f"payload metadata mismatch: {relative}")
        tree.update(relative.encode("utf-8") + b"\0")
        tree.update(item["sha256"].encode("ascii") + b"\0")
        tree.update(str(mode).encode("ascii") + b"\n")
    fingerprint = tree.hexdigest()
    if fingerprint != manifest.get("payloadFingerprint"):
        raise BundleError("payload fingerprint does not match the manifest")
    return fingerprint


def release_manifest(debug_manifest: dict, approval: dict, resources: Path) -> tuple[dict, dict[str, bytes]]:
    excluded = set(approval["excludedRecoveredFiles"])
    if excluded != {"fex-compat-tool", "unshare.py"}:
        raise BundleError("unexpected recovered-file exclusion")
    files = []
    overlays: dict[str, bytes] = {}
    for item in debug_manifest["files"]:
        if item["path"] in excluded:
            continue
        reviewed = dict(item)
        reviewed["publicDistributionAllowed"] = True
        reviewed["controlledDebugOnly"] = False
        reviewed["license"] = "fex-mit-and-reviewed-dependencies"
        files.append(reviewed)
    for item in approval["releaseOverlay"]:
        source_name = item.get("source")
        relative = item.get("path")
        if not isinstance(source_name, str) or not safe_relative(source_name):
            raise BundleError("unsafe release overlay source")
        if not isinstance(relative, str) or not safe_relative(relative):
            raise BundleError("unsafe release overlay path")
        source = resources / source_name
        if source.is_symlink() or not source.is_file() or has_symlink_component(source):
            raise BundleError("release overlay is missing or linked")
        data = source.read_bytes()
        if len(data) != item.get("bytes") or digest(data) != item.get("sha256") or item.get("mode") not in (420, 493):
            raise BundleError("release overlay metadata mismatch")
        overlays[relative] = data
        files.append({
            "path": relative,
            "name": PurePosixPath(relative).name,
            "bytes": len(data),
            "sha256": digest(data),
            "mode": item["mode"],
            "source": "reviewed-release-overlay",
            "sourceRelativePath": source_name,
            "sourceSHA256": digest(data),
            "transform": "none",
            "version": debug_manifest["version"],
            "license": item["license"],
            "installTarget": debug_manifest["guestRoot"] + "/" + relative,
            "publicDistributionAllowed": True,
            "controlledDebugOnly": False,
        })
    if len(files) != approval["releaseExpectedFiles"] or len({item["path"] for item in files}) != len(files):
        raise BundleError("release inventory count or paths are invalid")
    result = dict(debug_manifest)
    result.update({
        "packageID": "rf-fex-reviewed-release-v1",
        "expectedFiles": len(files),
        "payloadFingerprint": approval["releasePayloadFingerprint"],
        "debugOnly": False,
        "distributionApproved": True,
        "releaseStatus": approval["releaseApproval"],
        "sourcePolicy": "reviewed historical FEX outputs plus project-owned wrapper and bundled notices",
        "files": files,
    })
    return result, overlays


def assemble_release(source: Path, destination: Path, output_manifest: Path,
                     debug_manifest: dict, approval: dict, resources: Path) -> str:
    verify_payload(source, debug_manifest)
    manifest, overlays = release_manifest(debug_manifest, approval, resources)
    destination = destination.absolute()
    if destination.exists() or destination.is_symlink() or output_manifest.exists() or output_manifest.is_symlink():
        raise BundleError("release destinations must not exist")
    destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    staging = destination.parent / (".RF-FEX-release-staging-" + str(uuid.uuid4()))
    staging.mkdir(mode=0o700)
    try:
        excluded = set(approval["excludedRecoveredFiles"])
        for item in debug_manifest["files"]:
            if item["path"] in excluded:
                continue
            source_file = source / item["path"]
            output = staging / item["path"]
            output.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
            shutil.copyfile(source_file, output)
            output.chmod(item["mode"])
        entries = {item["path"]: item for item in manifest["files"]}
        for relative, data in overlays.items():
            output = staging / relative
            output.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
            with output.open("xb") as stream:
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
            output.chmod(entries[relative]["mode"])
        fingerprint = verify_payload(staging, manifest)
        if sum(item["bytes"] for item in manifest["files"]) != approval["releaseExpectedBytes"]:
            raise BundleError("release payload size does not match approval")
        manifest_bytes = (json.dumps(manifest, indent=2, sort_keys=False) + "\n").encode("utf-8")
        temporary_manifest = output_manifest.parent / ("." + output_manifest.name + "." + str(uuid.uuid4()))
        with temporary_manifest.open("xb") as stream:
            stream.write(manifest_bytes)
            stream.flush()
            os.fsync(stream.fileno())
        staging.rename(destination)
        temporary_manifest.rename(output_manifest)
        return fingerprint
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        raise


def import_payload(source_root: Path, destination: Path, manifest: dict) -> str:
    source_root = source_root.expanduser().absolute()
    destination = destination.expanduser().absolute()
    if source_root.is_symlink() or not source_root.is_dir() or has_symlink_component(source_root):
        raise BundleError("source root is missing or linked")
    if destination.exists():
        return verify_payload(destination, manifest)
    destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    staging = destination.parent / (".RF-FEX-staging-" + str(uuid.uuid4()))
    staging.mkdir(mode=0o700)
    try:
        for item in manifest["files"]:
            output = staging / item["path"]
            output.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
            data = source_bytes(source_root, item)
            with output.open("xb") as stream:
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
            output.chmod(item["mode"])
        fingerprint = verify_payload(staging, manifest)
        staging.rename(destination)
        return fingerprint
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        raise


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("import", "verify", "verify-release", "verify-package", "assemble-release"))
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--payload", type=Path)
    parser.add_argument("--source-root", type=Path)
    parser.add_argument("--destination", type=Path)
    parser.add_argument("--approval", type=Path)
    parser.add_argument("--resources", type=Path)
    parser.add_argument("--output-manifest", type=Path)
    args = parser.parse_args()
    if args.command in ("verify", "verify-package") and args.payload is None:
        parser.error("verify requires --payload")
    if args.command == "verify-release" and (args.payload is None or args.approval is None):
        parser.error("verify-release requires --payload and --approval")
    if args.command == "import" and (args.source_root is None or args.destination is None):
        parser.error("import requires --source-root and --destination")
    if args.command == "assemble-release" and any(value is None for value in (
        args.payload, args.destination, args.approval, args.resources, args.output_manifest
    )):
        parser.error("assemble-release requires payload, destination, approval, resources and output-manifest")
    return args


def main() -> int:
    args = parse_args()
    try:
        if args.command == "verify-release":
            manifest = load_release_manifest(args.manifest.absolute(), args.approval.absolute())
            fingerprint = verify_payload(args.payload.absolute(), manifest)
        elif args.command == "verify-package":
            if (has_symlink_component(args.manifest)
                    or file_digest(args.manifest) != "8354dbaf034e5c96d3b5cee84354e5a9650aea2c04245c979ff42be4d44636d8"):
                raise BundleError("packaged integrity manifest differs from the reviewed package")
            fingerprint = verify_payload(args.payload.absolute(), json.loads(args.manifest.read_bytes()))
        else:
            manifest = load_manifest(args.manifest.absolute())
        if args.command == "verify":
            fingerprint = verify_payload(args.payload.absolute(), manifest)
        elif args.command == "import":
            fingerprint = import_payload(args.source_root, args.destination, manifest)
        elif args.command == "assemble-release":
            approval = load_release_approval(args.approval.absolute(), args.manifest.absolute(), manifest)
            fingerprint = assemble_release(
                args.payload.absolute(), args.destination, args.output_manifest.absolute(),
                manifest, approval, args.resources.absolute()
            )
    except (BundleError, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"RF bundle check failed: {error}", file=sys.stderr)
        return 1
    print(f"RF bundle verified: files=41 fingerprint={fingerprint}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
