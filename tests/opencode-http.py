#!/usr/bin/env python3
"""Check the entrypoint's real shared proxy using environment captured from oc.

Usage: python3 tests/opencode-http.py <oc-env.json>, after the tmux test in
tests/docker-build.sh. Its local origin CA uses mitmproxy's native config.yaml.
Local HTTP/TLS origins and a gated SSE stream exercise real mitmdump traffic.
The final OpenCode catalog refresh uses isolated user state and public network
access. Temporary home state and origins are cleaned up; Docker owns the proxy.
"""

from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
from urllib.parse import urlsplit
from urllib.request import urlopen


RELEASES = {name: threading.Event() for name in ("one", "two")}


class Origin(BaseHTTPRequestHandler):
    """Hold the last SSE chunk until the client explicitly releases the stream."""

    protocol_version = "HTTP/1.1"

    def log_message(self, *_args):
        pass

    def do_GET(self):
        path = urlsplit(self.path).path
        if path.startswith("/stream/"):
            release = RELEASES[path.rsplit("/", 1)[1]]
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            first = b"data: first\n\n"
            self.wfile.write(f"{len(first):x}\r\n".encode() + first + b"\r\n")
            self.wfile.flush()
            if release.wait(8):
                last = b"data: last\n\n"
                self.wfile.write(f"{len(last):x}\r\n".encode() + last + b"\r\n0\r\n\r\n")
                self.wfile.flush()
            self.close_connection = True
            return
        if path.startswith("/release/"):
            RELEASES[path.rsplit("/", 1)[1]].set()
        if path == "/disconnect":
            self.connection.shutdown(socket.SHUT_RDWR)
            self.close_connection = True
            return
        body = b"response-secret"
        self.send_response(404 if path == "/missing" else 200)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Set-Cookie", "response-cookie-secret")
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        self.rfile.read(int(self.headers["Content-Length"]))
        self.do_GET()


def curl(*args):
    return subprocess.run(["curl", "--silent", "--show-error", "--max-time", "10",
                           *args], capture_output=True, text=True)


def client(token, http_url, https_url, bypass_url):
    """Exercise HTTP, TLS, and streaming through the same proxy as other clients."""
    for base in (http_url, https_url):
        result = curl("--fail", "-H", "Authorization: Bearer header-secret",
                      "-H", "Cookie: cookie-secret", "--data", "body-secret",
                      base + "/submit?query-secret")
        assert result.returncode == 0, result.stderr
        assert result.stdout == "response-secret", result.stdout
    with urlopen(https_url + "/python", timeout=10) as response:
        assert response.read() == b"response-secret", "Python HTTPS body mismatch"
    assert curl("--fail", bypass_url + "/local-bypass").returncode == 0
    assert curl("--fail", http_url + "/missing").returncode == 22
    assert curl("--fail", http_url + "/disconnect").returncode != 0

    # A buffering proxy deadlocks: the origin only finishes after the client
    # receives the first chunk and issues a separate release request.
    with subprocess.Popen(["curl", "--silent", "--show-error", "--fail",
                           "--no-buffer", "--max-time", "10",
                           https_url + "/stream/" + token],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE) as stream:
        first = stream.stdout.read(len(b"data: first\n\n"))
        assert first == b"data: first\n\n", f"first streaming chunk: {first!r}"
        assert curl("--fail", http_url + "/release/" + token).returncode == 0
        rest, error = stream.communicate(timeout=12)
        assert stream.returncode == 0, error.decode()
        assert rest == b"data: last\n\n", f"last streaming chunk: {rest!r}"


def verify(root, proxy_env):
    """Verify real requests, metadata omissions, strict TLS, and the OpenCode CLI."""
    os.environ.update(proxy_env)
    state = root / ".tmp/opencode-http"
    assert state.stat().st_mode & 0o777 == 0o700, "proxy state is not private"
    assert (state / "mitmproxy-ca.pem").stat().st_mode & 0o077 == 0, "CA key is not private"
    servers = [ThreadingHTTPServer((address, 0), Origin)
               for address in ("127.0.0.2", "127.0.0.2", "127.0.0.1", "127.0.0.1")]
    tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    tls.load_cert_chain(root / "origin.pem", root / "origin.key")
    for index in (1, 3):
        servers[index].socket = tls.wrap_socket(servers[index].socket, server_side=True)
    urls = [f"{scheme}://{server.server_address[0]}:{server.server_port}"
            for scheme, server in zip(("http", "https", "http", "https"), servers)]
    try:
        for server in servers:
            threading.Thread(target=server.serve_forever, daemon=True).start()
        with ThreadPoolExecutor(max_workers=2) as pool:
            list(pool.map(lambda name: client(name, *urls[:3]), RELEASES))
        assert curl("--fail", urls[1] + "/still-alive").returncode == 0, \
            "client exit stopped the shared proxy"

        log = root / ".tmp/opencode-http.jsonl"
        text = log.read_text()
        assert log.stat().st_mode & 0o777 == 0o600, "HTTP log is not owner-only"
        for omitted in ("query-secret", "header-secret", "cookie-secret", "body-secret",
                        "response-secret", "response-cookie-secret", "local-bypass"):
            assert omitted not in text, f"unexpected HTTP log data: {omitted}"
        records = [json.loads(line) for line in text.splitlines()]
        starts = {row["request_id"] for row in records if row["event"] == "http_request"}
        ends = [row for row in records if row["event"] != "http_request"]
        assert starts == {row["request_id"] for row in ends}, "uncorrelated request records"
        assert any(row["status"] == 404 for row in ends), "HTTP failure status not recorded"
        assert any(row["event"] == "http_error" for row in ends), "transport error not recorded"
        assert all(row["duration_ms"] >= 0 for row in records), "negative request duration"
        assert {row["scheme"] for row in records} == {"http", "https"}, "missing scheme"
        assert any(row["path"] == "/submit" and row["method"] == "POST" for row in ends)

        # The origin certificate covers only 127.0.0.2. Force a proxied request
        # to 127.0.0.1: the proxy must reject the upstream hostname mismatch.
        assert curl("--noproxy", "", "--fail", urls[3] + "/bad-certificate").returncode != 0, \
            "proxy disabled upstream TLS verification"

        # Use the shipped OpenCode/Bun binary, with no provider tokens or user
        # configuration, to prove that it trusts and uses the shared proxy CA.
        with tempfile.TemporaryDirectory(prefix="oc-http-test-", dir=root / ".tmp") as home:
            environment = {"PATH": os.environ["PATH"], "HOME": home, **proxy_env,
                           "XDG_CONFIG_HOME": home + "/config", "XDG_CACHE_HOME": home + "/cache",
                           "XDG_DATA_HOME": home + "/data", "XDG_STATE_HOME": home + "/state"}
            actual = subprocess.run(["opencode", "models", "--refresh", "--pure"],
                                    env=environment, cwd=home, stdout=subprocess.DEVNULL,
                                    stderr=subprocess.PIPE, text=True, timeout=90)
            assert actual.returncode == 0, f"OpenCode catalog refresh failed: {actual.stderr}"
        records = [json.loads(line) for line in log.read_text().splitlines()]
        assert any(row["host"] == "models.opencode.ai" and row["path"] == "/api.json"
                   and row["scheme"] == "https" and row["status"] == 200 for row in records), \
            "real OpenCode did not fetch its catalog through the TLS proxy"
    finally:
        for release in RELEASES.values():
            release.set()
        for server in servers:
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    verify(Path(os.environ["DEVCONTAINER_WORKSPACE_FOLDER"]), json.loads(Path(sys.argv[1]).read_text()))
    print("PASS: shared proxy HTTP/TLS, parallel streaming, metadata, and real OpenCode CA trust")
