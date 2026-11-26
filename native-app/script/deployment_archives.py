#!/usr/bin/env python3
"""Import and copy the pinned local-only deployment archives."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tempfile


def digest(path):
    sha = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            sha.update(chunk)
    return sha.hexdigest()


def verify(path, size, sha256):
    if path.resolve() != path.absolute() or not path.is_file() or path.stat().st_size != size or digest(path) != sha256:
        raise ValueError("Archive size, path or SHA-256 mismatch: " + path.name)


def publish(source, destination, entry):
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.parent.resolve() != destination.parent.absolute():
        raise ValueError("Unsafe destination: " + destination.name)
    if destination.is_file() and not destination.is_symlink():
        try:
            verify(destination, entry["bytes"], entry["sha256"])
            return
        except ValueError:
            pass
    with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as temporary:
        stage = Path(temporary.name)
    try:
        shutil.copyfile(source, stage)
        verify(stage, entry["bytes"], entry["sha256"])
        stage.replace(destination)
    finally:
        stage.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["import", "copy", "verify", "reject"])
    parser.add_argument("--catalogue", type=Path, required=True)
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--source", type=Path)
    parser.add_argument("--proton", type=Path)
    args = parser.parse_args()
    entries = json.loads(args.catalogue.read_text())["bundleArchives"]
    retired = args.destination / "Deployment/SteamLinuxRuntime_4"
    if args.action != "import" and (retired.exists() or retired.is_symlink()):
        raise ValueError("Steam-managed Runtime must be absent from App resources")
    for entry in entries:
        relative = Path(entry["bundlePath"])
        if relative.is_absolute() or ".." in relative.parts or relative.parts[0] != "Deployment":
            raise ValueError("Unsafe archive path")
        output = args.destination.absolute() / relative
        if args.action == "reject":
            parent = output.parent
            if parent.exists() or parent.is_symlink() or parent.parent.is_symlink():
                raise ValueError("Private archive present in public build resources")
            continue
        if args.action == "verify":
            verify(output, entry["bytes"], entry["sha256"])
            continue
        source = args.proton if args.action == "import" else (args.source / relative if args.source else None)
        if source is None:
            parser.error("missing archive source")
        verify(source.absolute(), entry["bytes"], entry["sha256"])
        publish(source, output, entry)
        print(f'{entry["name"]}: {entry["bytes"]} bytes, SHA-256 {entry["sha256"]}')


if __name__ == "__main__":
    main()
