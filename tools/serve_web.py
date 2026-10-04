#!/usr/bin/env python3
"""Serve the web export so you can play it in a browser: `make serve-web`, then open http://localhost:8060.

Usage: serve_web.py <dir> [port] [host]

A browser won't run a Godot web game from a file:// address, so it needs a tiny web server. This is one, from
Python's standard library, with the two details Godot needs: the right type for .wasm files, and no caching (so a
fresh export always shows up when you reload). It also sends the COOP/COEP headers; our single-threaded export
doesn't need them, but they keep local play identical to a threaded build if that is ever switched on.

host 0.0.0.0 lets other devices on your home network play: open http://<this computer's IP>:8060 on a phone or
tablet (make serve-web WEB_HOST=0.0.0.0).
"""
import functools
import http.server
import socket
import sys


class GodotWebHandler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".js": "text/javascript",
    }

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):
        pass  # quiet: a page load is dozens of requests


def lan_ip() -> str:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("10.255.255.255", 1))
            return s.getsockname()[0]
    except OSError:
        return "<this computer's IP>"


def main() -> None:
    directory = sys.argv[1] if len(sys.argv) > 1 else "build/web"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8060
    host = sys.argv[3] if len(sys.argv) > 3 else "127.0.0.1"
    handler = functools.partial(GodotWebHandler, directory=directory)
    http.server.ThreadingHTTPServer.allow_reuse_address = True
    with http.server.ThreadingHTTPServer((host, port), handler) as server:
        print(f"Serving {directory}", flush=True)
        print(f"  Play:  http://localhost:{port}/      (Ctrl+C to stop)", flush=True)
        if host == "0.0.0.0":
            print(f"  On another device at home:  http://{lan_ip()}:{port}/", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
