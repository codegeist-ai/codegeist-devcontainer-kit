#!/usr/bin/env python3
"""Check the entrypoint's real shared proxy using environment captured from oc.

Usage: python3 tests/opencode-http.py <oc-env.json> <second-oc-env.json>, after the tmux test in
tests/docker-build.sh. Its self-signed local origin is not added to proxy trust.
Local HTTP/TLS origins and a gated SSE stream exercise real mitmdump traffic.
The final OpenCode 2 server uses isolated user state to fetch its real catalog
and execute a shell through the logging wrapper. Its stdin lease owns its lifetime;
temporary state and origins are cleaned up while Docker owns the shared proxy.
"""

from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
import base64
from http.client import HTTPConnection
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
from urllib.request import build_opener, HTTPSHandler, ProxyHandler


RELEASES = {name: threading.Event() for name in ("one", "two")}


class Origin(BaseHTTPRequestHandler):
    """Hold the last SSE chunk until the client explicitly releases the stream."""

    protocol_version = "HTTP/1.1"

    def log_message(self, *_args):
        pass

    def do_GET(self):
        assert "Proxy-Authorization" not in self.headers, "internal run marker reached origin"
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
        if path.startswith("/disconnect/"):
            self.connection.shutdown(socket.SHUT_RDWR)
            self.close_connection = True
            return
        body = b"response-secret"
        self.send_response(404 if path.startswith("/missing/") else 200)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Set-Cookie", "response-cookie-secret")
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        self.rfile.read(int(self.headers["Content-Length"]))
        self.do_GET()


def curl(*args, env=None):
    return subprocess.run(["curl", "--silent", "--show-error", "--max-time", "10",
                           *args], env=env, capture_output=True, text=True)


def client(token, proxy_env, log, http_url, https_url, bypass_url):
    """Exercise HTTP, TLS, and streaming through the same proxy as other clients."""
    environment = {**os.environ, **proxy_env}
    for base in (http_url, https_url):
        result = curl("--fail", "-H", "Authorization: Bearer header-secret",
                      "-H", "Cookie: cookie-secret", "--data", "body-secret",
                      base + "/submit/" + token + "?query-secret", env=environment)
        assert result.returncode == 0, result.stderr
        assert result.stdout == "response-secret", result.stdout
        # One curl process reuses its proxy connection for both requests.
        result = curl("--fail", base + "/reuse-a/" + token, base + "/reuse-b/" + token, env=environment)
        assert result.returncode == 0 and result.stdout == "response-secret" * 2, result.stderr
    opener = build_opener(ProxyHandler({"https": proxy_env["HTTPS_PROXY"]}),
                          HTTPSHandler(context=ssl.create_default_context(cafile=proxy_env["SSL_CERT_FILE"])))
    with opener.open(https_url + "/python/" + token, timeout=10) as response:
        assert response.read() == b"response-secret", "Python HTTPS body mismatch"
    assert curl("--fail", bypass_url + "/local-bypass", env=environment).returncode == 0
    assert curl("--fail", http_url + "/missing/" + token, env=environment).returncode == 22
    assert curl("--fail", http_url + "/disconnect/" + token, env=environment).returncode != 0

    # A buffering proxy deadlocks: the origin only finishes after the client
    # receives the first chunk and issues a separate release request.
    with subprocess.Popen(["curl", "--silent", "--show-error", "--fail",
                           "--no-buffer", "--max-time", "10",
                           https_url + "/stream/" + token],
                          env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as stream:
        first = stream.stdout.read(len(b"data: first\n\n"))
        assert first == b"data: first\n\n", f"first streaming chunk: {first!r}"
        pending = [row for row in map(json.loads, log.read_text().splitlines())
                   if row["path"] == "/stream/" + token]
        assert len(pending) == 1 and pending[0]["event"] == "http_request", pending
        assert pending[0]["run_id"] == proxy_env["OC_RUN_ID"], pending
        assert curl("--fail", http_url + "/release/" + token, env=environment).returncode == 0
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
                       "SHELL": os.environ.get("OC_SHELL_BIN", "/usr/local/lib/oc-shell/bash"),
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
                marker = "opencode-v2-shell-check-" + proxy_env["OC_RUN_ID"]
                shell = json.loads(cli("api", "POST", "/api/shell", "--data",
                                       json.dumps({"command": "printf " + marker, "timeout": 5000})))["data"]
                assert shell["shell"] == environment["SHELL"], "OpenCode bypassed the logging shell"
                deadline = time.monotonic() + 10
                while shell["status"] == "running" and time.monotonic() < deadline:
                    time.sleep(0.1)
                    shell = json.loads(cli("api", "GET", "/api/shell/" + shell["id"], timeout=2))["data"]
                assert shell["status"] == "exited" and shell["exit"] == 0, "OpenCode shell did not finish"
                shell_log = root / ".tmp/opencode-shell.log"
                lines = [line for line in shell_log.read_text().splitlines() if marker in line]
                assert len(lines) == 1 and "run_id=" + proxy_env["OC_RUN_ID"] in lines[0], \
                    "real OpenCode shell start lost its run identity"
                assert shell_log.stat().st_mode & 0o777 == 0o600, "shell log is not owner-only"

                # 2.2.5 uses the v2 catalog; query parameters are omitted by the logger.
                # Refresh is asynchronous, so require a fresh completed request.
                catalog_path = "/experimental/v2.0/api.json"
                deadline = time.monotonic() + 30
                while True:
                    records = [json.loads(line) for line in log.read_text().splitlines()[record_count:]]
                    if any(row["run_id"] == proxy_env["OC_RUN_ID"]
                           and row["host"] == "models.opencode.ai" and row["path"] == catalog_path
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


def verify_proxy(root, contexts):
    """Verify forwarding of untrusted upstream TLS, streaming, and metadata omissions."""
    os.environ.update(contexts[0])
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
        log = root / ".tmp/opencode-http.jsonl"
        with ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(client, name, context, log, *urls[:3])
                       for name, context in zip(RELEASES, contexts)]
            for future in futures:
                future.result()

        # A plain HTTP connection may carry different markers per request. An
        # unmarked request on that same connection must not inherit the last run.
        endpoint = urlsplit(contexts[0]["HTTP_PROXY"])
        with closing(HTTPConnection(endpoint.hostname, endpoint.port, timeout=10)) as connection:
            for name, context in [*zip(RELEASES, contexts), ("unattributed", None)]:
                headers = {}
                if context:
                    proxy = urlsplit(context["HTTP_PROXY"])
                    headers["Proxy-Authorization"] = "Basic " + base64.b64encode(
                        (proxy.username + ":" + proxy.password).encode()).decode()
                connection.request("GET", urls[0] + "/keepalive/" + name, headers=headers)
                assert connection.getresponse().read() == b"response-secret"
        assert curl("--fail", urls[1] + "/still-alive").returncode == 0, \
            "client exit stopped the shared proxy"

        # Streaming delivers the body before the proxy's terminal hook runs.
        # Client completion is not a log flush barrier (including earlier TUI
        # requests); wait for every observed start/end pair, without hiding any
        # unmatched records or changing the production streaming behavior.
        deadline = time.monotonic() + 10
        while True:
            text = log.read_text()
            records = [json.loads(line) for line in text.splitlines()]
            starts = {row["request_id"] for row in records if row["event"] == "http_request"}
            ends = [row for row in records if row["event"] != "http_request"]
            unmatched = starts ^ {row["request_id"] for row in ends}
            if not unmatched:
                break
            assert time.monotonic() < deadline, \
                f"uncorrelated request records: {[row for row in records if row['request_id'] in unmatched]}"
            time.sleep(0.1)

        assert log.stat().st_mode & 0o777 == 0o600, "HTTP log is not owner-only"
        for omitted in ("query-secret", "header-secret", "cookie-secret", "body-secret",
                        "response-secret", "response-cookie-secret", "local-bypass"):
            assert omitted not in text, f"unexpected HTTP log data: {omitted}"
        for name, context in zip(RELEASES, contexts):
            attributed = [row for row in records if row["path"].endswith("/" + name)]
            assert attributed and all(row["run_id"] == context["OC_RUN_ID"] for row in attributed), attributed
        unattributed = [row for row in records if row["path"] == "/keepalive/unattributed"]
        assert len(unattributed) == 2 and all(row["run_id"] is None for row in unattributed), unattributed
        assert any(row["status"] == 404 for row in ends), "HTTP failure status not recorded"
        assert any(row["event"] == "http_error" for row in ends), "transport error not recorded"
        assert all(row["duration_ms"] >= 0 for row in records), "negative request duration"
        assert {row["scheme"] for row in records} == {"http", "https"}, "missing scheme"
        assert any(row["path"].startswith("/submit/") and row["method"] == "POST" for row in ends)

        # The self-signed origin certificate covers only 127.0.0.2. Force a
        # proxied request to 127.0.0.1: upstream hostname mismatches are accepted
        # as well, while the client still verifies the proxy's generated certificate.
        result = curl("--noproxy", "", "--fail", urls[3] + "/bad-certificate")
        assert result.returncode == 0, result.stderr
        assert result.stdout == "response-secret", result.stdout

    finally:
        for release in RELEASES.values():
            release.set()
        for server in servers:
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    root = Path(os.environ["DEVCONTAINER_WORKSPACE_FOLDER"])
    contexts = [json.loads(Path(name).read_text()) for name in sys.argv[1:]]
    assert len(contexts) == 2 and contexts[0]["OC_RUN_ID"] != contexts[1]["OC_RUN_ID"]
    verify_proxy(root, contexts)
    with ThreadPoolExecutor(max_workers=2) as pool:
        list(pool.map(lambda context: verify_opencode(root, context), contexts))
    print("PASS: isolated run attribution, HTTP/TLS/streaming, metadata, and real OpenCode CA trust and shell logging")
