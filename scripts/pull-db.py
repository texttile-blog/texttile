#!/usr/bin/env python3
"""Download a consistent database through Texttile's read-only backup API."""
import argparse
import os
from pathlib import Path
import shutil
import sqlite3
import tempfile
import urllib.request


def download(url, token, target):
    """Replace the local snapshot only after SQLite verifies the download."""
    if not url.startswith("https://") or not token:
        raise ValueError("Set an HTTPS TEXTTILE_URL and a TEXTTILE_TOKEN from Settings > Backup.")
    request = urllib.request.Request(url.rstrip("/") + "/backup/db",
                                     headers={"Authorization": "Bearer " + token})
    target = Path(target).resolve()
    with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as temporary:
        path = Path(temporary.name)
    try:
        with urllib.request.urlopen(request, timeout=300) as response, path.open("wb") as output:
            shutil.copyfileobj(response, output)
        with path.open("rb") as downloaded:
            if downloaded.read(16) != b"SQLite format 3\0":
                raise sqlite3.DatabaseError("The response is not a SQLite database.")
        db = sqlite3.connect(path.as_uri() + "?mode=ro", uri=True)
        try:
            if db.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
                raise ValueError("The downloaded database failed its integrity check.")
        finally:
            db.close()
        path.replace(target)
    finally:
        path.unlink(missing_ok=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output")
    args = parser.parse_args()
    download(os.environ.get("TEXTTILE_URL", "https://staging.texttile.blog"),
             os.environ.get("TEXTTILE_TOKEN", ""), args.output)
    print(f"Snapshot ready: {Path(args.output).resolve()}")
