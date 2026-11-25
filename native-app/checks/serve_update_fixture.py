#!/usr/bin/env python3
"""Serve local, signed update-test releases from an ignored build directory."""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import re
import shutil
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
REPO = "LSJOP/helldivers2-fx-launcher"


def serve(fixture, port):
    fixture = fixture.resolve()
    if not fixture.is_relative_to(ROOT / "build") or not (1024 <= port <= 65535):
        raise ValueError("Use an ignored build workspace and a non-privileged port")

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            path = urlsplit(self.path).path
            revision = (fixture / "current").read_text().strip()
            if not re.fullmatch(r"[1-9][0-9]*", revision):
                self.send_error(503)
                return
            assets = fixture / ("assets" + revision)
            manifest = json.loads((assets / "update-manifest.json").read_text())
            tag = "v" + manifest["version"]
            if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+-update-test\.[1-9][0-9]*", tag):
                self.send_error(503)
                return
            prefix = f"/{REPO}/releases/download/{tag}/"
            files = {item.name: item for item in assets.iterdir() if item.is_file() and not item.is_symlink()}
            if path == f"/repos/{REPO}/releases":
                body = json.dumps([dict(tag_name=tag, draft=False, prerelease=True,
                                        html_url=f"https://github.com/{REPO}/releases/tag/{tag}",
                                        body="Local signed component update fixture",
                                        assets=[dict(name=name, browser_download_url="https://github.com" + prefix + name,
                                                     size=file.stat().st_size) for name, file in files.items()])]).encode()
                self.send_response(200); self.send_header("Content-Length", str(len(body))); self.end_headers()
                self.wfile.write(body)
                return
            file = files.get(path[len(prefix):]) if path.startswith(prefix) else None
            if file is None:
                self.send_error(404)
                return
            size = file.stat().st_size
            self.send_response(200); self.send_header("Content-Length", str(size)); self.end_headers()
            with file.open("rb") as archive:
                shutil.copyfileobj(archive, self.wfile, 1_048_576)
            print(f"DELIVERED {tag} {file.name} {size}", flush=True)

    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture", type=Path)
    parser.add_argument("--port", type=int, required=True)
    args = parser.parse_args()
    serve(args.fixture, args.port)
