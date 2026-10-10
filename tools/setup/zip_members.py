#!/usr/bin/env python3
"""Extract a few members from a big remote .zip (Godot's 1.3 GB export templates) using HTTP range requests,
so a computer only downloads the templates it uses (tens of MB, not 1.3 GB).

Integrity: every extracted member is checked against a PINNED sha256 (passed as --sha name=hash, recorded in
the Makefile), on top of the zip's own CRC check and HTTPS. Standard library only; Python 3.9+.

    zip_members.py URL DEST_DIR --member templates/web_nothreads_release.zip --sha web_nothreads_release.zip=<hex> ...
    zip_members.py URL --list            # names and sizes, nothing downloaded but the directory
    zip_members.py URL DEST --member M --print-sha   # extract and print hashes (to pin new versions)
"""
import argparse
import hashlib
import io
import os
import sys
import urllib.request
import zipfile


class RangeFile(io.RawIOBase):
    """A read-only, seekable file over HTTP range requests, with a small read-ahead cache."""

    def __init__(self, url: str):
        self.url = url
        self.pos = 0
        req = urllib.request.Request(url, headers={"Range": "bytes=0-0"})
        with urllib.request.urlopen(req, timeout=60) as r:
            self.url = r.geturl()  # follow GitHub's redirect once
            total = r.headers.get("Content-Range", "").rsplit("/", 1)[-1]
        if not total.isdigit():
            raise RuntimeError("server does not support range requests: %s" % url)
        self.size = int(total)
        self._cache_start, self._cache = -1, b""

    def readable(self): return True
    def seekable(self): return True
    def tell(self): return self.pos

    def seek(self, offset, whence=io.SEEK_SET):
        self.pos = {io.SEEK_SET: 0, io.SEEK_CUR: self.pos, io.SEEK_END: self.size}[whence] + offset
        return self.pos

    def read(self, n=-1):
        if n is None or n < 0:
            n = self.size - self.pos
        if n <= 0 or self.pos >= self.size:
            return b""
        end = min(self.pos + n, self.size)
        c0 = self._cache_start
        if not (c0 >= 0 and c0 <= self.pos and end <= c0 + len(self._cache)):
            fetch_end = min(self.size, max(end, self.pos + (1 << 20)))  # read ahead 1 MB for small reads
            for attempt in range(4):
                try:
                    req = urllib.request.Request(self.url, headers={"Range": "bytes=%d-%d" % (self.pos, fetch_end - 1)})
                    with urllib.request.urlopen(req, timeout=120) as r:
                        self._cache = r.read()
                    break
                except Exception:  # transient network trouble: retry, then give up loudly
                    if attempt == 3:
                        raise
            self._cache_start = self.pos
            c0 = self.pos
        data = self._cache[self.pos - c0:end - c0]
        self.pos += len(data)
        return data

    def readinto(self, b):
        data = self.read(len(b))
        b[:len(data)] = data
        return len(data)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("url")
    ap.add_argument("dest", nargs="?")
    ap.add_argument("--member", action="append", default=[])
    ap.add_argument("--sha", action="append", default=[], help="basename=sha256hex (pinned)")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--print-sha", action="store_true")
    a = ap.parse_args()
    archive = zipfile.ZipFile(io.BufferedReader(RangeFile(a.url), buffer_size=1 << 20))
    if a.list:
        for info in archive.infolist():
            print("%12d  %s" % (info.file_size, info.filename))
        return 0
    pinned = dict(s.split("=", 1) for s in a.sha)
    os.makedirs(a.dest, exist_ok=True)
    for member in a.member:
        name = os.path.basename(member)
        data = archive.read(member)  # zipfile checks the CRC
        digest = hashlib.sha256(data).hexdigest()
        if a.print_sha:
            print("%s=%s" % (name, digest))
        elif pinned.get(name) != digest:
            print("CHECKSUM MISMATCH for %s: got %s, pinned %s" % (name, digest, pinned.get(name, "(none)")))
            return 1
        out = os.path.join(a.dest, name)
        with open(out + ".part", "wb") as f:
            f.write(data)
        os.replace(out + ".part", out)
        print(">> %s (%.1f MB) ok" % (name, len(data) / 1e6))
    return 0


if __name__ == "__main__":
    sys.exit(main())
