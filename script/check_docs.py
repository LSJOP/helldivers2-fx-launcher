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
import re
import subprocess
import sys
from pathlib import Path

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
