"""Scan files on VirusTotal from CI and report each engine's verdict.

    python tools/vt_scan.py FILE [FILE ...]

Needs a VirusTotal API key in the VT_API_KEY environment variable (a free
account's key works). Without one it says so and exits 0, so builds still
pass on forks and before the key is added.

It uploads every file first (files over 32 MB through a one-time upload URL),
then waits until every engine has reported on each, and prints the ratio and
every engine that flagged it. In GitHub Actions each result also becomes an
annotation on the run and a row in the job summary. The full result goes to
vt-results.json.

Exit code: 0 when every file scanned clean, 1 when any engine flagged
something, 2 when a scan couldn't finish. Uses only the standard library.

The free API allows 4 requests a minute, so it waits at least 16 seconds
between requests. A result is a snapshot: engines keep updating their
verdicts, so a file that's clean today can be flagged tomorrow, and the other
way round.
"""

from __future__ import annotations

import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

API = "https://www.virustotal.com/api/v3"
DIRECT_LIMIT = 32 * 1024 * 1024  # bigger files need a one-time upload URL
REQUEST_GAP = 16                 # seconds; the free API allows 4 requests a minute
TIMEOUT = 45 * 60                # give up waiting for engines after this long
FLAGGED = {"malicious", "suspicious"}

_last_request = 0.0


def _request(method: str, url: str, key: str, body: bytes | None = None, headers: dict | None = None) -> dict:
    global _last_request
    wait = _last_request + REQUEST_GAP - time.monotonic()
    if wait > 0:
        time.sleep(wait)
    request = urllib.request.Request(url, data=body, method=method, headers={"x-apikey": key, **(headers or {})})
    for attempt in range(5):
        _last_request = time.monotonic()
        try:
            with urllib.request.urlopen(request, timeout=600) as response:
                return json.loads(response.read() or b"{}")
        except urllib.error.HTTPError as error:
            if error.code == 429 and attempt < 4:  # over the rate limit: back off and retry
                time.sleep(60)
                continue
            detail = error.read().decode("utf-8", "replace")[:300]
            raise RuntimeError(f"{method} {url.split('?')[0]} failed: HTTP {error.code} {detail}") from None
    raise RuntimeError(f"{method} {url} kept hitting the rate limit")


def _multipart(path: Path) -> tuple[bytes, str]:
    boundary = uuid.uuid4().hex
    head = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{path.name}\"\r\n"
            "Content-Type: application/octet-stream\r\n\r\n").encode()
    return head + path.read_bytes() + f"\r\n--{boundary}--\r\n".encode(), f"multipart/form-data; boundary={boundary}"


def upload(path: Path, key: str) -> str:
    """Uploads a file and returns its analysis id."""
    url = f"{API}/files"
    if path.stat().st_size > DIRECT_LIMIT:
        url = _request("GET", f"{API}/files/upload_url", key)["data"]
    body, content_type = _multipart(path)
    return _request("POST", url, key, body, {"Content-Type": content_type})["data"]["id"]


def wait_for(analysis_id: str, key: str) -> dict:
    """Polls until every engine has reported; returns the analysis attributes."""
    deadline = time.monotonic() + TIMEOUT
    while time.monotonic() < deadline:
        attributes = _request("GET", f"{API}/analyses/{analysis_id}", key)["data"]["attributes"]
        if attributes.get("status") == "completed":
            return attributes
        time.sleep(60)
    raise RuntimeError(f"analysis {analysis_id} didn't finish within {TIMEOUT // 60} minutes")


def summarise(path: Path, attributes: dict) -> dict:
    stats = attributes.get("stats", {})
    results = attributes.get("results", {})
    flagged = sorted(
        (name, verdict.get("result") or verdict.get("category"))
        for name, verdict in results.items() if verdict.get("category") in FLAGGED
    )
    scanned = sum(stats.get(k, 0) for k in ("malicious", "suspicious", "undetected", "harmless"))
    return {
        "file": path.name,
        "bytes": path.stat().st_size,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "flagged": flagged,
        "ratio": f"{len(flagged)}/{scanned}",
        "stats": stats,
    }


def _escape(text: str, prop: bool = False) -> str:
    """Escapes text for a GitHub Actions workflow command."""
    text = text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    return text.replace(":", "%3A").replace(",", "%2C") if prop else text


def annotate(report: dict) -> None:
    if os.environ.get("GITHUB_ACTIONS") != "true":
        return
    names = ", ".join(f"{engine} ({label})" for engine, label in report["flagged"]) or "No engine flagged it."
    level = "warning" if report["flagged"] else "notice"
    title = _escape(f"VirusTotal {report['file']} {report['ratio']}", prop=True)
    print(f"::{level} title={title}::{_escape(names)} sha256 {report['sha256']}", flush=True)


def main(argv: list[str]) -> int:
    files = [Path(arg) for arg in argv]
    key = os.environ.get("VT_API_KEY", "").strip()
    if not key:
        print("VT_API_KEY isn't set, so nothing was scanned.")
        return 0
    pending, reports, failed = [], [], False
    for path in files:  # upload everything first, so the engines work on all of them at once
        print(f"Uploading {path.name} ({path.stat().st_size:,} bytes)...", flush=True)
        try:
            pending.append((path, upload(path, key)))
        except (RuntimeError, OSError, KeyError, ValueError) as error:
            print(f"  couldn't upload it: {error}")
            failed = True
    for path, analysis in pending:
        print(f"Waiting for the engines on {path.name}...", flush=True)
        try:
            report = summarise(path, wait_for(analysis, key))
        except (RuntimeError, OSError, KeyError, ValueError) as error:
            print(f"  couldn't scan it: {error}")
            failed = True
            continue
        reports.append(report)
        print(f"  {report['ratio']}  sha256 {report['sha256']}")
        print(f"  https://www.virustotal.com/gui/file/{report['sha256']}")
        for engine, label in report["flagged"]:
            print(f"    {engine}: {label}")
        annotate(report)
    Path("vt-results.json").write_text(json.dumps(reports, indent=1))
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        lines = ["## VirusTotal", "", "| File | Result | Flagged by |", "|---|---|---|"]
        for report in reports:
            names = ", ".join(f"{engine} ({label})" for engine, label in report["flagged"]) or "nobody"
            link = f"[{report['ratio']}](https://www.virustotal.com/gui/file/{report['sha256']})"
            lines.append(f"| {report['file']} | {link} | {names} |")
        with open(summary, "a", encoding="utf-8") as out:
            out.write("\n".join(lines) + "\n")
    if failed:
        return 2
    return 1 if any(report["flagged"] for report in reports) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
