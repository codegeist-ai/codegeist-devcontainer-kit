#!/usr/bin/env python3
"""Check the entrypoint's real shared proxy using environment captured from oc.

Usage: python3 tests/opencode-http.py <oc-env.json>, after the tmux test in
tests/docker-build.sh. Its local origin CA uses mitmproxy's native config.yaml.
Local HTTP/TLS origins and a gated SSE stream exercise real mitmdump traffic.
The final OpenCode 2 server uses isolated user state to fetch its real catalog
and execute a shell through the logging wrapper. Its stdin lease owns its lifetime;
temporary state and origins are cleaned up while Docker owns the shared proxy.
"""

from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import secrets
import select
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import time
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


def verify_opencode(root, proxy_env):
    """Check real V2 catalog traffic and shell logging with a bounded server lifetime."""
    log = root / ".tmp/opencode-http.jsonl"
    record_count = len(log.read_text().splitlines())
    # An OS-temp cwd keeps ancestor discovery away from the mounted developer
    # checkout. The server password stays in the isolated environment, not argv.
    with tempfile.TemporaryDirectory(prefix="oc-http-test-") as home:
        environment = {"PATH": os.environ["PATH"], "HOME": home, **proxy_env,
                       "XDG_CONFIG_HOME": home + "/config", "XDG_CACHE_HOME": home + "/cache",
                       "XDG_DATA_HOME": home + "/data", "XDG_STATE_HOME": home + "/state",
                       "SHELL": "/usr/local/lib/oc-shell/bash",
                       "OPENCODE_PASSWORD": secrets.token_urlsafe(32),
                       "DEVCONTAINER_WORKSPACE_TMP": str(root / ".tmp")}
        with subprocess.Popen(["opencode", "serve", "--stdio", "--hostname", "127.0.0.1", "--port", "0"],
                              env=environment, cwd=home, stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as native:
            try:
                assert select.select([native.stdout], [], [], 30)[0], "OpenCode server readiness timed out"
                endpoint = json.loads(native.stdout.readline())["url"]

                def cli(command, *args, timeout=30):
                    """Run the real CLI; it owns API authentication and returns stdout."""
                    result = subprocess.run(["opencode", command, "--server", endpoint, *args],
                                            env=environment, cwd=home, capture_output=True, text=True, timeout=timeout)
                    assert result.returncode == 0, f"OpenCode {command} failed: {result.stderr}"
                    return result.stdout

                cli("models")
                # Use the real shell service without submitting a model prompt.
                marker = "opencode-v2-shell-check"
                shell = json.loads(cli("api", "POST", "/api/shell", "--data",
                                       json.dumps({"command": "printf " + marker, "timeout": 5000})))["data"]
                assert shell["shell"] == environment["SHELL"], "OpenCode bypassed the logging shell"
                deadline = time.monotonic() + 10
                while shell["status"] == "running" and time.monotonic() < deadline:
                    time.sleep(0.1)
                    shell = json.loads(cli("api", "GET", "/api/shell/" + shell["id"], timeout=2))["data"]
                assert shell["status"] == "exited" and shell["exit"] == 0, "OpenCode shell did not finish"
                shell_log = root / ".tmp/opencode-shell.log"
                assert marker in shell_log.read_text(), "real OpenCode shell start was not logged"
                assert shell_log.stat().st_mode & 0o777 == 0o600, "shell log is not owner-only"

                # 2.2.5 uses the v2 catalog; query parameters are omitted by the logger.
                # Refresh is asynchronous, so require a fresh completed request.
                catalog_path = "/experimental/v2.0/api.json"
                deadline = time.monotonic() + 30
                while True:
                    records = [json.loads(line) for line in log.read_text().splitlines()[record_count:]]
                    if any(row["host"] == "models.opencode.ai" and row["path"] == catalog_path
                           and row["scheme"] == "https" and row["status"] == 200 for row in records):
                        break
                    assert time.monotonic() < deadline, \
                        f"Expected a proxied HTTPS 200 response from models.opencode.ai{catalog_path}"
                    time.sleep(0.1)
            finally:
                # communicate closes the stdin lease and drains both output pipes.
                try:
                    _, error = native.communicate(timeout=10)
                except subprocess.TimeoutExpired:
                    native.kill()
                    _, error = native.communicate()
            assert native.returncode == 0, f"OpenCode server shutdown failed: {error}"


def verify_proxy(root, proxy_env):
    """Verify real HTTP/TLS requests, streaming, metadata omissions, and strict trust."""
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

    finally:
        for release in RELEASES.values():
            release.set()
        for server in servers:
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    root = Path(os.environ["DEVCONTAINER_WORKSPACE_FOLDER"])
    proxy_env = json.loads(Path(sys.argv[1]).read_text())
    verify_proxy(root, proxy_env)
    verify_opencode(root, proxy_env)
    print("PASS: shared proxy HTTP/TLS, parallel streaming, metadata, and real OpenCode 2 CA trust and shell logging")
