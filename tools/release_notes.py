"""Write a release's notes from CHANGELOG.md.

    python tools/release_notes.py check VERSION        # e.g. 1.1.0
    python tools/release_notes.py notes TAG SHA256     # e.g. v1.1.0 and the exe's SHA-256

Each version has a "## 1.2.3" heading in CHANGELOG.md, with a few bullets
under it saying what changed. "check" exits with 1, and a message for the
build log, when VERSION has no such part or the part is empty. "notes"
prints the whole release text for TAG: that part under "What's new", how to
get started (with a link to the README at that tag) and the exe's SHA-256.
Links in CHANGELOG.md to the repository's own files, like
[Terms of Service](TERMS.md), are pointed at the tag's copy so they work on
the release page too. HTML comments (notes for whoever edits the file) are
left out.

The repository is GITHUB_REPOSITORY when that's set (it is in GitHub
Actions), else waterjugs/SYN-Seeder. Uses only the standard library.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

CHANGELOG = Path(__file__).resolve().parent.parent / "CHANGELOG.md"
DEFAULT_REPO = "waterjugs/SYN-Seeder"

VERSION = re.compile(r"\d+\.\d+\.\d+")
TAG = re.compile(r"v\d+\.\d+\.\d+")
SHA256 = re.compile(r"[0-9a-f]{64}")
REPO = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")
COMMENT = re.compile(r"<!--.*?-->", re.DOTALL)
VERSION_HEADING = re.compile(r"##[ \t]+v?(\d+\.\d+\.\d+)(?:[ \t].*)?")
TOP_HEADING = re.compile(r"#{1,2}(?:[ \t]|$)")  # a "#" or "##" heading ends a version's part
FENCE = re.compile(r"[ ]{0,3}(```|~~~)")
# [text](TERMS.md): a link with no scheme (https:, mailto:), not to an anchor
# on the same page (#...), not protocol-relative (//...) and not in <...>.
RELATIVE_LINK = re.compile(r"(\]\()(?![A-Za-z][A-Za-z0-9+.-]*:|#|//|<)(?:\./|/)?([^)\s]+)\)")


class ChangelogError(Exception):
    """CHANGELOG.md has no usable part for a version."""


def section(text: str, version: str) -> str:
    """The part of a changelog under "## VERSION", without blank lines around it."""
    text = COMMENT.sub("", text.replace("\r\n", "\n").replace("\r", "\n"))
    parts: dict[str, list[str]] = {}
    current = None
    in_fence = False
    for line in text.split("\n"):
        if FENCE.match(line):
            in_fence = not in_fence
        elif not in_fence:
            heading = VERSION_HEADING.fullmatch(line.rstrip())
            if heading:
                current = heading.group(1)
                if current in parts:
                    raise ChangelogError(f'CHANGELOG.md has "## {current}" more than once')
                parts[current] = []
                continue
            if TOP_HEADING.match(line):
                current = None
                continue
        if current is not None:
            parts[current].append(line.rstrip())
    if version not in parts:
        raise ChangelogError(
            f'CHANGELOG.md has no "## {version}" part. Add one at the top with a few short '
            f"bullets saying what changed in {version}: its release shows them as its notes.")
    body = "\n".join(parts[version]).strip("\n")
    if not body.strip():
        raise ChangelogError(f'The "## {version}" part of CHANGELOG.md is empty. Say what changed in {version}.')
    return body


def absolute_links(text: str, repo: str, tag: str) -> str:
    """Points links to the repository's own files at the tag's copy of them."""
    return RELATIVE_LINK.sub(lambda m: f"{m.group(1)}https://github.com/{repo}/blob/{tag}/{m.group(2)})", text)


def notes(text: str, tag: str, sha256: str, repo: str = DEFAULT_REPO) -> str:
    """The whole release text for TAG, from the changelog TEXT."""
    if not TAG.fullmatch(tag):
        raise ValueError(f"{tag!r} isn't a release tag like v1.2.3")
    if not SHA256.fullmatch(sha256):
        raise ValueError(f"{sha256!r} isn't a SHA-256 in lowercase hex")
    if not REPO.fullmatch(repo):
        raise ValueError(f"{repo!r} isn't a repository like owner/name")
    docs = f"https://github.com/{repo}/blob/{tag}"
    whats_new = absolute_links(section(text, tag[1:]), repo, tag)
    return (
        f"## What's new\n\n{whats_new}\n\n"
        f"Download SynSeeder.exe below and double-click it. The [README]({docs}/README.md) says how to set it up.\n\n"
        f"SHA-256 of SynSeeder.exe: `{sha256}`\n"
    )


def _fail(message: str) -> int:
    prefix = "::error::" if os.environ.get("GITHUB_ACTIONS") == "true" else ""
    sys.stdout.write(f"{prefix}{message}\n")
    return 1


def main(argv: list[str]) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    usage = "usage: release_notes.py check VERSION | notes TAG SHA256\n"
    if len(argv) == 2 and argv[0] == "check":
        version = argv[1]
        if not VERSION.fullmatch(version):
            sys.stderr.write(f"{version!r} isn't a version like 1.2.3\n")
            return 2
        try:
            section(CHANGELOG.read_text(encoding="utf-8"), version)
        except ChangelogError as error:
            return _fail(str(error))
        sys.stdout.write(f"CHANGELOG.md says what changed in {version}\n")
        return 0
    if len(argv) == 3 and argv[0] == "notes":
        repo = os.environ.get("GITHUB_REPOSITORY") or DEFAULT_REPO
        try:
            sys.stdout.write(notes(CHANGELOG.read_text(encoding="utf-8"), argv[1], argv[2], repo))
        except ChangelogError as error:
            return _fail(str(error))
        except ValueError as error:
            sys.stderr.write(f"{error}\n")
            return 2
        return 0
    sys.stderr.write(usage)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
