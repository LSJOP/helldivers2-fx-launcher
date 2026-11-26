#!/usr/bin/env python3
"""Freeze and package the corresponding source for the approved Proton-JE archive."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tarfile


TAG = "proton-je-11.0-20261014-3"
COMMIT = "a69793ad2c48dbdf0299e5ef3264b99edb96eeda"
BINARY_SHA256 = "aa5430696ca39451299e2f007ef652bc030e6419242776343d48947e21827485"
MAX_SUBMODULES = 256


def run(checkout: Path, *arguments: str) -> str:
    return subprocess.check_output(["git", "-C", str(checkout), *arguments], text=True).strip()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def inventory(checkout: Path) -> dict:
    checkout = checkout.resolve()
    if not (checkout / ".git").exists() or run(checkout, "rev-parse", "HEAD") != COMMIT:
        raise ValueError("The source checkout is not the reviewed Proton-JE tag commit")
    if run(checkout, "status", "--porcelain", "--untracked-files=no"):
        raise ValueError("The source checkout or a registered submodule is modified")
    raw = subprocess.check_output(
        ["git", "-C", str(checkout), "submodule", "status", "--recursive"], text=True
    )
    modules = []
    for line in raw.splitlines():
        match = re.fullmatch(r" ([0-9a-f]{40}) (\S+)(?: \(.*\))?", line)
        if not match:
            raise ValueError("A recursive submodule is absent, modified, or unrecognized")
        commit, relative = match.groups()
        module = checkout / relative
        if module.resolve() != module.absolute() or run(module, "rev-parse", "HEAD") != commit:
            raise ValueError("Submodule identity mismatch: " + relative)
        modules.append({"path": relative, "commit": commit, "origin": run(module, "remote", "get-url", "origin")})
    if not modules or len(modules) > MAX_SUBMODULES:
        raise ValueError("Unexpected recursive submodule count")
    return {
        "schema": 1,
        "component": "Proton-JE",
        "version": "11.0-20261014-3",
        "build": "1792806463",
        "tag": TAG,
        "commit": COMMIT,
        "repository": "https://github.com/jegglest/proton-je",
        "binarySHA256": BINARY_SHA256,
        "submodules": modules,
    }


def write_lock(checkout: Path, output: Path) -> dict:
    record = inventory(checkout)
    output.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return record


def verify_lock(checkout: Path, lock: Path) -> dict:
    expected = inventory(checkout)
    actual = json.loads(lock.read_text(encoding="utf-8"))
    if actual != expected:
        raise ValueError("Corresponding-source lock does not match the checkout")
    return actual


def package(checkout: Path, lock: Path, output: Path) -> None:
    verify_lock(checkout, lock)
    if output.exists() or output.is_symlink() or output.suffixes[-2:] != [".tar", ".xz"]:
        raise ValueError("Source output must be a new .tar.xz file")
    root_name = f"proton-je-{TAG.removeprefix('proton-je-')}-corresponding-source"
    with tarfile.open(output, "w:xz", preset=6) as archive:
        archive.add(checkout, arcname=root_name, recursive=True,
                    filter=lambda info: None if "/.git/" in info.name or info.name.endswith("/.git") else info)
        archive.add(lock, arcname=root_name + "/CORRESPONDING_SOURCE_LOCK.json", recursive=False)
    if output.stat().st_size <= 0:
        raise ValueError("Corresponding-source archive is empty")
    print(f"{output.name}: {output.stat().st_size} bytes, SHA-256 {sha256(output)}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("lock", "verify", "package"))
    parser.add_argument("--checkout", type=Path, required=True)
    parser.add_argument("--lock", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.action == "lock":
        write_lock(args.checkout, args.lock)
    elif args.action == "verify":
        verify_lock(args.checkout, args.lock)
        print("Proton-JE corresponding-source lock: PASS")
    else:
        if args.output is None:
            parser.error("package requires --output")
        package(args.checkout, args.lock, args.output)


if __name__ == "__main__":
    main()
