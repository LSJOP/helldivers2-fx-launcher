#!/usr/bin/env python3
"""Documentation consistency checks for the bilingual changelog system.

Checks (HD2_README_CHANGELOG_POLICY_V1):
  1. CHANGELOG.md and CHANGELOG.zh-CN.md exist.
  2. README.md links CHANGELOG.md and README.zh-CN.md links CHANGELOG.zh-CN.md.
  3. Both changelogs have a matching Unreleased section.
  4. Released version numbers and dates match between English and Chinese.
  5. Every released version (with a date) has a matching Git tag (no fabricated releases).
  6. Referenced local changelog paths exist.

Exit 0 when all checks pass, 1 otherwise. Semantic consistency still needs human review.
"""
from html.parser import HTMLParser
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit

from sync_stable_release import BASE, updated_readme

ROOT = Path(__file__).resolve().parent.parent

CHANGELOG_EN = ROOT / "CHANGELOG.md"
CHANGELOG_ZH = ROOT / "CHANGELOG.zh-CN.md"
README_EN = ROOT / "README.md"
README_ZH = ROOT / "README.zh-CN.md"

UNRELEASED_RE = re.compile(r"^##\s+(?:Unreleased|未发布)", re.IGNORECASE)
# Released version header: "### v1.2.0 — 2026-11-03" (version and date are language-neutral).
RELEASED_RE = re.compile(r"^###\s+v?(\d+\.\d+\.\d+)\s*—\s*(\d{4}-\d{2}-\d{2})")


def git_tags():
    try:
        out = subprocess.run(
            ["git", "-C", str(ROOT), "tag", "-l"],
            capture_output=True, text=True, timeout=10,
        )
        if out.returncode != 0:
            return None
        return {line.strip() for line in out.stdout.splitlines() if line.strip()}
    except (OSError, subprocess.SubprocessError):
        return None


def released_entries(path):
    entries = []
    try:
        for line in path.read_text(encoding="utf-8").splitlines():
            m = RELEASED_RE.match(line.strip())
            if m:
                entries.append((m.group(1), m.group(2)))
    except OSError:
        return None
    return entries


def has_unreleased(path):
    try:
        return any(UNRELEASED_RE.match(line.strip()) for line in path.read_text(encoding="utf-8").splitlines())
    except OSError:
        return False


def has_link(readme, target):
    try:
        return target.name in readme.read_text(encoding="utf-8")
    except OSError:
        return False


class BrandHTML(HTMLParser):
    def __init__(self):
        super().__init__()
        self.stack = []
        self.roots = []
        self.links = []
        self.images = []
        self.errors = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if not self.stack:
            self.roots.append(tag)
            if attrs.get("align") != "center":
                self.errors.append("top-level brand elements must be centered")
        if tag == "img":
            self.images.append(attrs.get("src", ""))
        elif tag in {"p", "h1", "a"}:
            self.stack.append(tag)
            if tag == "a":
                self.links.append(attrs.get("href", ""))
        else:
            self.errors.append(f"unexpected brand HTML tag {tag}")

    def handle_endtag(self, tag):
        if self.stack and tag == self.stack[-1]:
            self.stack.pop()
        else:
            self.errors.append(f"unmatched closing tag {tag}")

    def handle_data(self, data):
        if data.strip() and not self.stack:
            self.errors.append("unwrapped brand text")


def headings(source):
    return {
        re.sub(r"[^\w-]", "", value.lower().replace(" ", "-"))
        for value in re.findall(r"(?m)^#{1,6} (.+)$", source)
    }


def check_readme(path):
    source = path.read_text()
    parts = re.split(r"(?m)(?=^## )", source, maxsplit=1)
    if len(parts) != 2:
        return ["README has no language section"]
    header, body = parts
    parser = BrandHTML()
    parser.feed(header)
    parser.close()
    errors = parser.errors
    if parser.stack or parser.roots != ["p", "h1", "p", "p", "p", "p", "p"]:
        errors.append("expected seven separate, closed brand blocks")
    language = ["#简体中文", "#english" if path == README_EN else "README.md#english"]
    if parser.links[:2] != language:
        errors.append("language navigation differs from the required anchors")
    if len(parser.images) != 2 or parser.images[0] != "docs/assets/app-icon.png":
        errors.append("expected an independent app icon and download image")
    for value in parser.images + parser.links + re.findall(r"\]\(([^\s)]+)\)", body):
        url = urlsplit(value)
        if url.scheme or url.netloc:
            continue
        target = ROOT / unquote(url.path) if url.path else path
        if not target.is_file():
            errors.append(f"missing local path {value}")
        elif url.fragment and target.suffix == ".md":
            if unquote(url.fragment) not in headings(target.read_text()):
                errors.append(f"missing anchor {value}")
    try:
        version = re.search(r"Stable Release · v([0-9.]+)", header)[1]
        build, commit = re.search(r"`([0-9]+)` · .*?/commit/([a-f0-9]{40})", body).groups()
        dmg = f"HD2FXNative-v{version}-macOS-arm64.dmg"
        if updated_readme(source, version, build, dmg, commit) != source:
            errors.append("stable version fields disagree")
        if source.count(f"{BASE}/download/v{version}/{dmg}") != 1:
            errors.append("expected a single direct DMG link")
    except (AttributeError, TypeError, ValueError) as error:
        errors.append(f"invalid stable field structure: {error}")
    return errors


def chinese_body(source):
    _, marker, body = source.partition("\n## 简体中文\n")
    if not marker:
        return None
    body = re.sub(r"<!-- stable-build:start -->.*?<!-- stable-build:end -->", "", body, flags=re.S)
    body = body.replace("[查看正式构建号及发布提交](#changelog)", "")
    return body.replace("[独立中文版](README.zh-CN.md#简体中文) · ", "").strip()


def main():
    checks = []

    def check(name, ok, detail=""):
        checks.append((name, bool(ok), detail))

    # 1. Changelog files exist.
    check("CHANGELOG.md exists", CHANGELOG_EN.is_file())
    check("CHANGELOG.zh-CN.md exists", CHANGELOG_ZH.is_file())

    # 2. READMEs reference the changelog.
    check("README.md links CHANGELOG.md", has_link(README_EN, CHANGELOG_EN))
    check("README.zh-CN.md links CHANGELOG.zh-CN.md", has_link(README_ZH, CHANGELOG_ZH))

    # 3. Unreleased sections present and matching.
    en_unrel = has_unreleased(CHANGELOG_EN)
    zh_unrel = has_unreleased(CHANGELOG_ZH)
    check("English changelog has Unreleased section", en_unrel)
    check("Chinese changelog has Unreleased section", zh_unrel)
    check("Unreleased sections match across languages", en_unrel == zh_unrel)

    # 4. Released version numbers and dates match across languages.
    en_rel = released_entries(CHANGELOG_EN)
    zh_rel = released_entries(CHANGELOG_ZH)
    check("Released versions parse (English)", en_rel is not None)
    check("Released versions parse (Chinese)", zh_rel is not None)
    if en_rel is not None and zh_rel is not None:
        en_ver = [v for v, _ in en_rel]
        zh_ver = [v for v, _ in zh_rel]
        check("Released version numbers match", en_ver == zh_ver, f"en={en_ver} zh={zh_ver}")
        check("Released dates match", en_rel == zh_rel, f"en={en_rel} zh={zh_rel}")

    # 5. Released versions must have a matching Git tag (no fabricated releases).
    tags = git_tags()
    if tags is None:
        check("Git tags readable", False, "git tag -l failed")
    else:
        check("Git tags readable", True, f"{len(tags)} tags")
        missing = []
        if en_rel is not None:
            for version, _date in en_rel:
                # Accept a tag named exactly vX.Y.Z or X.Y.Z.
                if f"v{version}" not in tags and version not in tags:
                    missing.append(version)
        check("Every released version has a matching Git tag", not missing,
              "missing tags for: " + ", ".join(missing) if missing else "")

    # 6. Referenced local changelog paths exist (redundant with #1, kept explicit).
    check("CHANGELOG path valid", CHANGELOG_EN.is_file())
    check("CHANGELOG.zh-CN path valid", CHANGELOG_ZH.is_file())

    for path in (README_EN, README_ZH):
        errors = check_readme(path)
        check(f"{path.name} brand, anchors and local links", not errors, "; ".join(errors))
    homepage_chinese = chinese_body(README_EN.read_text())
    check("Simplified Chinese homepage copy matches standalone README",
          homepage_chinese is not None and homepage_chinese == chinese_body(README_ZH.read_text()))

    failed = 0
    for name, ok, detail in checks:
        status = "PASS" if ok else "FAIL"
        suffix = f" — {detail}" if detail else ""
        print(f"{status} {name}{suffix}")
        if not ok:
            failed += 1

    print(f"\n{len(checks) - failed}/{len(checks)} documentation checks PASS")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
