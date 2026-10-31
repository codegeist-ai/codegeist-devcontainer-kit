"""mitmdump addon for streaming, metadata-only oc request logging.

DEVCONTAINER_WORKSPACE_FOLDER selects .tmp/opencode-http.jsonl, shared by all
oc panes using the container proxy. Only explicit fields are serialized: no query,
headers, bodies, credentials, or raw exception text. Requests get a start record
and a correlated response/error record, with duration through stream completion.
Related: entrypoint.sh, cmds/oc, README.md#opencode-http-logging.
"""

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import time

from mitmproxy import http


class MetadataLog:
    """Append one complete JSON record per HTTP event without storing bodies."""

    def load(self, _loader):
        log_path = Path(os.environ["DEVCONTAINER_WORKSPACE_FOLDER"]) / ".tmp/opencode-http.jsonl"
        self.fd = os.open(log_path,
                          os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)

    def record(self, event, flow):
        """Serialize an allowlist, never a flow dump or unfiltered error message."""
        record = {
            "time": datetime.now(timezone.utc).isoformat(),
            "event": event,
            "request_id": flow.id,
            "method": flow.request.method,
            "scheme": flow.request.scheme,
            "host": flow.request.host,
            "port": flow.request.port,
            "path": flow.request.path.split("?", 1)[0].split("#", 1)[0],
            "status": flow.response.status_code if flow.response else None,
            "duration_ms": round((time.monotonic() - flow.metadata["oc_start"]) * 1000, 2),
        }
        # One O_APPEND write preserves complete JSONL records for readers.
        os.write(self.fd, (json.dumps(record, ensure_ascii=True) + "\n").encode())

    def requestheaders(self, flow: http.HTTPFlow):
        flow.request.stream = True
        flow.metadata["oc_start"] = time.monotonic()
        self.record("http_request", flow)

    def responseheaders(self, flow: http.HTTPFlow):
        flow.response.stream = True

    def response(self, flow: http.HTTPFlow):
        self.record("http_response", flow)

    def error(self, flow: http.HTTPFlow):
        # TLS/connect failures can precede requestheaders, so no request may be
        # available yet. HTTP failures after headers still get a terminal record.
        if "oc_start" in flow.metadata:
            self.record("http_error", flow)

    def done(self):
        os.close(self.fd)


addons = [MetadataLog()]
