#!/usr/bin/env python3
"""Import and verify the private, controlled-Debug RF runtime payload.

The binary payload is deliberately ignored by Git.  This tool accepts an explicit
historical evidence directory once, validates every input against the reviewed
manifest, sanitizes the compatibility wrapper, and creates a self-contained local
Debug resource directory.  It never compiles FEX and never authorizes Release use.
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


def source_bytes(root: Path, item: dict) -> bytes:
    source = root / item["sourceRelativePath"]
    try:
        metadata = source.lstat()
    except FileNotFoundError as error:
        raise BundleError(f"missing source: {item['sourceRelativePath']}") from error
    if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode) or metadata.st_nlink != 1:
        raise BundleError(f"unsafe source: {item['sourceRelativePath']}")
    if source.resolve() != source.absolute():
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
    if root.is_symlink() or not root.is_dir() or root.resolve() != root.absolute():
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


def import_payload(source_root: Path, destination: Path, manifest: dict) -> str:
    source_root = source_root.expanduser().absolute()
    destination = destination.expanduser().absolute()
    if source_root.is_symlink() or not source_root.is_dir() or source_root.resolve() != source_root:
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
    parser.add_argument("command", choices=("import", "verify"))
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--payload", type=Path)
    parser.add_argument("--source-root", type=Path)
    parser.add_argument("--destination", type=Path)
    args = parser.parse_args()
    if args.command == "verify" and args.payload is None:
        parser.error("verify requires --payload")
    if args.command == "import" and (args.source_root is None or args.destination is None):
        parser.error("import requires --source-root and --destination")
    return args


def main() -> int:
    args = parse_args()
    try:
        manifest = load_manifest(args.manifest.absolute())
        if args.command == "verify":
            fingerprint = verify_payload(args.payload.absolute(), manifest)
        else:
            fingerprint = import_payload(args.source_root, args.destination, manifest)
    except (BundleError, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"RF bundle check failed: {error}", file=sys.stderr)
        return 1
    print(f"RF bundle verified: files=41 fingerprint={fingerprint}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
