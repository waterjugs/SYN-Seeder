"""Scan files on VirusTotal from CI and report each engine's verdict.

    python tools/vt_scan.py [--rescan SHA256[:NAME] ...] FILE [FILE ...]

Needs a VirusTotal API key in the VT_API_KEY environment variable (a free
account's key works). Without one it says so and exits 0, so builds still
pass on forks and before the key is added.

It uploads every file first (files over 32 MB through a one-time upload URL),
then waits until every engine has reported on each, and prints the ratio and
every engine that flagged it. --rescan asks VirusTotal to scan a file it
already has again, by its SHA-256, without needing the file. When VirusTotal
won't take a file again so soon (HTTP 409), it asks for a rescan instead, and
if that's refused too it reports the file's latest finished scan and its date. In GitHub Actions each result also becomes an
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


def rescan(sha256: str, key: str) -> str | None:
    """Asks for a fresh scan of a file VirusTotal already has; None when it won't scan it again yet."""
    try:
        return _request("POST", f"{API}/files/{sha256}/analyse", key)["data"]["id"]
    except RuntimeError as error:
        if "HTTP 409" in str(error):
            return None
        raise


def submit(path: Path, sha256: str, key: str) -> str | None:
    """Uploads a file, or asks for a rescan when VirusTotal already took the same file recently."""
    try:
        return upload(path, key)
    except RuntimeError as error:
        if "HTTP 409" not in str(error):
            raise
    print("  VirusTotal had this exact file already, so asking for a rescan instead.", flush=True)
    return rescan(sha256, key)


def latest(sha256: str, key: str) -> dict:
    """The file's latest finished scan, in the same shape as an analysis, waiting while it has none yet."""
    deadline = time.monotonic() + TIMEOUT
    while time.monotonic() < deadline:
        try:
            attributes = _request("GET", f"{API}/files/{sha256}", key)["data"]["attributes"]
        except RuntimeError as error:
            if "HTTP 404" not in str(error):
                raise
            attributes = {}
        if attributes.get("last_analysis_results"):
            return {"stats": attributes.get("last_analysis_stats", {}), "results": attributes["last_analysis_results"],
                    "date": attributes.get("last_analysis_date"), "size": attributes.get("size")}
        time.sleep(60)
    raise RuntimeError(f"VirusTotal had no finished scan of {sha256} within {TIMEOUT // 60} minutes")


def wait_for(analysis_id: str, key: str) -> dict:
    """Polls until every engine has reported; returns the analysis attributes."""
    deadline = time.monotonic() + TIMEOUT
    missing = 0
    while time.monotonic() < deadline:
        try:
            attributes = _request("GET", f"{API}/analyses/{analysis_id}", key)["data"]["attributes"]
        except RuntimeError as error:
            # A fresh upload's analysis can take a moment to show up.
            if "HTTP 404" not in str(error) or missing >= 5:
                raise
            missing += 1
            time.sleep(30)
            continue
        if attributes.get("status") == "completed":
            return attributes
        time.sleep(60)
    raise RuntimeError(f"analysis {analysis_id} didn't finish within {TIMEOUT // 60} minutes")


def summarise(name: str, sha256: str, size: int | None, attributes: dict, fresh: bool) -> dict:
    stats = attributes.get("stats", {})
    results = attributes.get("results", {})
    flagged = sorted(
        (engine, verdict.get("result") or verdict.get("category"))
        for engine, verdict in results.items() if verdict.get("category") in FLAGGED
    )
    scanned = sum(stats.get(k, 0) for k in ("malicious", "suspicious", "undetected", "harmless"))
    when = attributes.get("date")
    return {
        "file": name,
        "bytes": size if size is not None else attributes.get("size"),
        "sha256": sha256,
        "flagged": flagged,
        "ratio": f"{len(flagged)}/{scanned}",
        "stats": stats,
        "scanned": ("fresh scan" if fresh else "earlier scan") + (
            time.strftime(" %Y-%m-%d %H:%M UTC", time.gmtime(when)) if when else ""),
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
    print(f"::{level} title={title}::{_escape(names)} ({report['scanned']}) sha256 {report['sha256']}", flush=True)


def main(argv: list[str]) -> int:
    items = []  # (name, sha256, local path or None)
    args = iter(argv)
    for arg in args:
        if arg == "--rescan":
            sha256, _, name = next(args, "").partition(":")
            items.append((name or sha256, sha256.lower(), None))
        else:
            path = Path(arg)
            items.append((path.name, hashlib.sha256(path.read_bytes()).hexdigest(), path))
    key = os.environ.get("VT_API_KEY", "").strip()
    if not key:
        print("VT_API_KEY isn't set, so nothing was scanned.")
        return 0
    pending, reports, failed = [], [], False
    for name, sha256, path in items:  # send everything first, so the engines work on all of them at once
        try:
            if path:
                print(f"Uploading {name} ({path.stat().st_size:,} bytes)...", flush=True)
                analysis = submit(path, sha256, key)
            else:
                print(f"Asking for a rescan of {name} ({sha256})...", flush=True)
                analysis = rescan(sha256, key)
        except (RuntimeError, OSError, KeyError, ValueError) as error:
            print(f"  couldn't send it: {error}")
            failed = True
            continue
        if analysis is None:
            print("  VirusTotal won't scan it again yet, so this uses its latest scan.", flush=True)
        pending.append((name, sha256, path, analysis))
    for name, sha256, path, analysis in pending:
        print(f"Waiting for the engines on {name}...", flush=True)
        try:
            attributes = wait_for(analysis, key) if analysis else latest(sha256, key)
            report = summarise(name, sha256, path.stat().st_size if path else None, attributes, analysis is not None)
        except (RuntimeError, OSError, KeyError, ValueError) as error:
            print(f"  couldn't scan it: {error}")
            failed = True
            continue
        reports.append(report)
        print(f"  {report['ratio']}  ({report['scanned']})  sha256 {report['sha256']}")
        print(f"  https://www.virustotal.com/gui/file/{report['sha256']}")
        for engine, label in report["flagged"]:
            print(f"    {engine}: {label}")
        annotate(report)
    Path("vt-results.json").write_text(json.dumps(reports, indent=1))
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        lines = ["## VirusTotal", "", "| File | Result | Flagged by | Scan |", "|---|---|---|---|"]
        for report in reports:
            names = ", ".join(f"{engine} ({label})" for engine, label in report["flagged"]) or "nobody"
            link = f"[{report['ratio']}](https://www.virustotal.com/gui/file/{report['sha256']})"
            lines.append(f"| {report['file']} | {link} | {names} | {report['scanned']} |")
        with open(summary, "a", encoding="utf-8") as out:
            out.write("\n".join(lines) + "\n")
    if failed:
        return 2
    return 1 if any(report["flagged"] for report in reports) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
