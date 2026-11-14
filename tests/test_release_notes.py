"""Tests for tools/release_notes.py:  python tests/test_release_notes.py"""

from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import release_notes  # noqa: E402

SHA = "a57a5592452737d316ff1ae2c2d684817cf396b5b0b70da263d8c2bcf7e876a9"

CHANGELOG = """# What's new

Intro text that isn't part of any version.

<!--
## 9.9.9
A note for whoever edits the file.
-->

## 1.1.0

- New thing. See the [Terms of Service](TERMS.md) and [how](PRIVACY.md#sending).

### Fixes

- Fixed a thing.

```
## not a heading, it's in a code block
```

## 1.0.2 (8 November 2026)

- The seedling has its stem back.

## 1.0.1.5

- Not a version this tool knows.

## 1.0.0

- The first release.
"""


class SectionTests(unittest.TestCase):
    def test_takes_only_that_versions_part(self):
        self.assertEqual(release_notes.section(CHANGELOG, "1.0.0"), "- The first release.")

    def test_keeps_smaller_headings_and_code_blocks(self):
        part = release_notes.section(CHANGELOG, "1.1.0")
        self.assertTrue(part.startswith("- New thing."))
        self.assertIn("### Fixes\n\n- Fixed a thing.", part)
        self.assertTrue(part.endswith("## not a heading, it's in a code block\n```"))

    def test_heading_can_have_a_date_after_the_version(self):
        self.assertEqual(release_notes.section(CHANGELOG, "1.0.2"), "- The seedling has its stem back.")

    def test_a_longer_version_ends_the_part_before_it(self):
        self.assertNotIn("Not a version", release_notes.section(CHANGELOG, "1.0.2"))
        with self.assertRaises(release_notes.ChangelogError):
            release_notes.section(CHANGELOG, "1.0.1")

    def test_leaves_out_comments(self):
        with self.assertRaises(release_notes.ChangelogError):
            release_notes.section(CHANGELOG, "9.9.9")

    def test_windows_line_endings(self):
        self.assertEqual(release_notes.section(CHANGELOG.replace("\n", "\r\n"), "1.0.2"),
                         "- The seedling has its stem back.")

    def test_a_v_before_the_version_is_fine(self):
        self.assertEqual(release_notes.section("## v2.0.0\n\n- Big.\n", "2.0.0"), "- Big.")

    def test_missing_version(self):
        with self.assertRaisesRegex(release_notes.ChangelogError, r'no "## 3\.0\.0" part'):
            release_notes.section(CHANGELOG, "3.0.0")

    def test_empty_part(self):
        with self.assertRaisesRegex(release_notes.ChangelogError, "empty"):
            release_notes.section("## 2.0.0\n\n<!-- nothing yet -->\n\n## 1.0.0\n\n- First.\n", "2.0.0")

    def test_same_version_twice(self):
        with self.assertRaisesRegex(release_notes.ChangelogError, "more than once"):
            release_notes.section("## 1.0.0\n\n- A.\n\n## 1.0.0\n\n- B.\n", "1.0.0")


class LinkTests(unittest.TestCase):
    def fix(self, text):
        return release_notes.absolute_links(text, "waterjugs/SYN-Seeder", "v1.1.0")

    def test_points_repository_files_at_the_tag(self):
        base = "https://github.com/waterjugs/SYN-Seeder/blob/v1.1.0/"
        self.assertEqual(self.fix("[a](TERMS.md) [b](./PRIVACY.md#x) [c](/src/App.ahk)"),
                         f"[a]({base}TERMS.md) [b]({base}PRIVACY.md#x) [c]({base}src/App.ahk)")

    def test_leaves_other_links_alone(self):
        text = "[a](https://example.com/x) [b](#here) [c](mailto:x@example.com) [d](//example.com) [e](<x y.md>)"
        self.assertEqual(self.fix(text), text)


class NotesTests(unittest.TestCase):
    def test_whole_text(self):
        docs = "https://github.com/waterjugs/SYN-Seeder/blob/v1.0.2"
        self.assertEqual(release_notes.notes(CHANGELOG, "v1.0.2", SHA), (
            "## What's new\n\n- The seedling has its stem back.\n\n"
            f"Download SynSeeder.exe below and double-click it. The [README]({docs}/README.md) says how to set it up.\n\n"
            f"SHA-256 of SynSeeder.exe: `{SHA}`\n"))

    def test_adds_no_terms_agreement_or_virus_scan(self):
        # The owner's choice: no "you agree" line, no Terms or Privacy links
        # unless a version's own part has them, and no VirusTotal result.
        text = release_notes.notes(CHANGELOG, "v1.0.0", SHA).lower()
        for words in ("agree", "terms", "privacy", "virustotal", "virus"):
            self.assertNotIn(words, text)

    def test_refuses_bad_input(self):
        for tag, sha, repo in (("1.0.0", SHA, "a/b"), ("v1.0", SHA, "a/b"), ("v1.0.0", SHA.upper(), "a/b"),
                               ("v1.0.0", SHA[:-1], "a/b"), ("v1.0.0", SHA, "a b/c"), ("v1.0.0\n", SHA, "a/b")):
            with self.assertRaises(ValueError, msg=(tag, sha, repo)):
                release_notes.notes(CHANGELOG, tag, sha, repo)


class RealChangelogTests(unittest.TestCase):
    def test_every_tagged_version_and_the_current_one_have_a_part(self):
        text = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
        app = (ROOT / "src" / "App.ahk").read_text(encoding="utf-8")
        current = re.search(r'static VERSION := "([^"]+)"', app).group(1)
        for version in ("1.0.0", "1.0.2", current):
            self.assertTrue(release_notes.section(text, version).startswith("- "), version)

    def test_one_line_per_bullet(self):
        # The release page shows every line break, so a bullet mustn't be wrapped.
        text = release_notes.COMMENT.sub("", (ROOT / "CHANGELOG.md").read_text(encoding="utf-8"))
        for version in re.findall(r"^## (\d+\.\d+\.\d+)", text, re.MULTILINE):
            for line in release_notes.section(text, version).split("\n"):
                self.assertTrue(line == "" or line.startswith(("- ", "#")), f"{version}: {line!r}")


if __name__ == "__main__":
    unittest.main()
