#!/usr/bin/env python3
"""Exercise the installed Gum/lnav pane through real OpenCode/tmux PTYs.

Run from tests/docker-build.sh after the proxy checks. The fixture uses a private
tmux server and isolated OpenCode home. Actual shell starts and local HTTP requests
must retain their values, including different/unattributed runs, and update live.
lnav must recognize both log formats, preserve every field, scroll/search while
following, retry missing/replaced logs, and exit cleanly on quit or pane closure.
Its configuration/history/work files must stay in workspace temporary storage,
even when the caller already has ~/.lnav and XDG configuration directories.
All fixture processes and temporary home state are cleaned on exit.
"""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import threading
import time
import uuid


class Origin(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        assert "Proxy-Authorization" not in self.headers
        self.send_response(200)
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"ok")


def wait(check, description):
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        result = check()
        if result:
            return result
        time.sleep(0.1)
    raise AssertionError("Timed out: " + description)


def tui_checks():
    """Select formatted logs with Gum and focus dashboard/origin via distinct keys."""
    with tempfile.TemporaryDirectory(prefix="oc-dash-", dir="/tmp/opencode") as tmp:
        home = Path(tmp)
        root = Path(os.environ["DEVCONTAINER_WORKSPACE_TMP"])
        (home / ".lnav").mkdir()
        (home / ".lnav" / "sentinel").write_text("user-owned configuration\n")
        (home / "xdg").mkdir()
        environment = {"PATH": os.environ["PATH"], "HOME": str(home), "TERM": "xterm-256color",
                       "XDG_CONFIG_HOME": str(home / "xdg"),
                       "TMUX_TMPDIR": str(home), "OPENCODE_CONFIG_DIR": str(home / "config"),
                       "DEVCONTAINER_WORKSPACE_FOLDER": os.environ["DEVCONTAINER_WORKSPACE_FOLDER"],
                       "DEVCONTAINER_WORKSPACE_TMP": str(root)}
        wrapper = os.environ.get("OC_SHELL_BIN", "/usr/local/lib/oc-shell/bash")

        def tmux(*args):
            return subprocess.run(["tmux", *args], env=environment, capture_output=True, text=True).stdout.strip()

        def active():
            return tmux("display-message", "-p", "#{pane_id}")

        def screen():
            return tmux("capture-pane", "-p")

        def viewer_line():
            """Read lnav's selected-line indicator, independent of wrapped rows."""
            return int(re.search(r"(?m)^ L(\d+)\s", screen()).group(1))

        def origins():
            return [pane for line in tmux("list-panes", "-a", "-F", "#{pane_id}|#{@oc-log-origin}").splitlines()
                    for pane, _, origin in [line.partition("|")] if pane == origin]

        def descendants(pane):
            """Capture viewer PIDs so an idle log cannot hide orphaned processes."""
            parent = int(tmux("display-message", "-p", "-t", pane, "#{pane_pid}"))
            pairs = [tuple(map(int, line.split())) for line in subprocess.check_output(
                ["ps", "-eo", "pid=,ppid="], text=True).splitlines()]
            found = {parent}
            while children := {pid for pid, ppid in pairs if ppid in found} - found:
                found.update(children)
            return found - {parent}

        client = subprocess.Popen(["script", "-qec", "stty cols 140 rows 45; exec oc", "/dev/null"],
                                  env=environment, cwd=home, stdin=subprocess.PIPE,
                                  stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        origin = ThreadingHTTPServer(("127.0.0.2", 0), Origin)
        threading.Thread(target=origin.serve_forever, daemon=True).start()

        def keys(value):
            client.stdin.write(value)
            client.stdin.flush()

        def request(label, run_id):
            proxy = f"http://oc-run-{run_id}:observe@127.0.0.1:18080"
            subprocess.run(["curl", "--silent", "--show-error", "--fail", "--max-time", "10",
                            "--noproxy", "", "--proxy", proxy,
                            f"http://127.0.0.2:{origin.server_port}/dashboard-" + label],
                           env=environment, stdout=subprocess.DEVNULL, check=True)

        readers = set()
        try:
            pane = wait(origins, "first oc pane registration")[0]
            wait(lambda: "Ask anything" in screen(), "real OpenCode TUI")
            process = tmux("display-message", "-p", "-t", pane, "#{pane_pid}")
            window = tmux("display-message", "-p", "-t", pane, "#{window_id}")
            bindings = {key: shlex.split(tmux("list-keys", "-T", "prefix", key))[-1] for key in ("g", "o")}
            for key in bindings:
                tmux("bind-key", key, "display-message", "keep-user-binding-" + key)
            tmux("new-window", "-d", "-c", str(home), "oc")
            both = wait(lambda: origins() if len(origins()) == 2 else None, "second oc pane")
            for key in bindings:
                assert "keep-user-binding-" + key in tmux("list-keys", "-T", "prefix", key)
            second_pane = next(candidate for candidate in both if candidate != pane)
            for key, binding in bindings.items():
                tmux("bind-key", key, "run-shell", "-b", binding)
            tmux("set-buffer", "clipboard-unchanged")

            # Different run IDs and unattributed starts remain visible together.
            for label in ("one", "two"):
                run_id = str(uuid.uuid4())
                subprocess.run([wrapper, "-c", ":", "dashboard-command-" + label,
                                "\x1b]52;c;ZXhlY3V0ZWQ=\a $(touch " + str(home / "injected") + ")"],
                               env={**environment, "OC_RUN_ID": run_id}, check=True)
                request(label, run_id)
            subprocess.run([wrapper, "-c", ":", "dashboard-unattributed"], env=environment, check=True)
            logs = {root / name: (root / name).read_bytes()
                    for name in ("opencode-shell.log", "opencode-http.jsonl")}

            tmux("select-window", "-t", pane)
            wait(lambda: active() == pane, "select first origin")
            keys(b"t040 keep this draft")
            wait(lambda: "t040 keep this draft" in screen(), "unsubmitted OpenCode draft")
            windows = tmux("list-windows", "-F", "#{window_id}")
            keys(b"\x02g")
            dash = wait(lambda: active() if active() != pane else None, "dashboard focus")
            wait(lambda: "Shell log" in screen() and "HTTP log" in screen(), "Gum log selection")
            assert "Return to OpenCode" not in screen()
            assert window == tmux("display-message", "-p", "-t", dash, "#{window_id}"), "dashboard opened a window"
            panes = tmux("list-panes", "-t", window, "-F", "#{pane_id}")
            assert len(panes.splitlines()) == 2
            keys(b"\r")
            wait(lambda: "event=shell_start" in screen() and "argv=" in screen(), "raw shell log")
            # Whole values may span lnav's wrapped display rows as PIDs/path
            # lengths vary. Verify them through its real unwrapped renderer.
            state = str(root / "oc-dashboard")
            rendered = subprocess.check_output(
                ["lnav", "-Nn", str(root / "opencode-shell.log")], text=True,
                env={**environment, "HOME": state, "XDG_CONFIG_HOME": state, "TMPDIR": state})
            assert all(value in rendered for value in (
                "dashboard-command-one", "dashboard-command-two", "dashboard-unattributed", "run_id=unattributed"))
            colored_shell = tmux("capture-pane", "-epJ", "-S", "-2000")
            assert re.search(r"\x1b\[38;[\d;]*m(?:event|run_id|cwd|argv)\x1b\[", colored_shell), \
                "shell log field names lack syntax highlighting"
            assert not (home / "injected").exists()
            assert tmux("show-buffer") == "clipboard-unchanged"
            for _ in range(2):
                keys(b"\x02o")
                wait(lambda: active() == pane, "return to exact origin")
                wait(lambda: "t040 keep this draft" in screen(), "preserved draft after pane resize")
                keys(b"\x02g")
                wait(lambda: active() == dash, "reuse dashboard pane")
            assert windows == tmux("list-windows", "-F", "#{window_id}")
            assert panes == tmux("list-panes", "-t", window, "-F", "#{pane_id}")
            assert process == tmux("display-message", "-p", "-t", pane, "#{pane_pid}")
            assert (root / "opencode-shell.log").read_bytes() == logs[root / "opencode-shell.log"]
            for path, before in logs.items():
                assert path.read_bytes().startswith(before), "viewer rewrote the log"
                assert path.stat().st_mode & 0o777 == 0o600

            # lnav reads new records directly and exits without a reader pipeline.
            previous_line = viewer_line()
            subprocess.run([wrapper, "-c", ":", "after-follow"], env=environment, check=True)
            last_shell_line = len((root / "opencode-shell.log").read_text().splitlines()) - 1
            wait(lambda: viewer_line() == last_shell_line > previous_line, "live shell log")
            keys(b"\x03")
            wait(lambda: "Shell log" in screen() and "HTTP log" in screen(), "Ctrl+C returns to Gum")
            assert active() == dash and "Return to OpenCode" not in screen()
            keys(b"j\r")
            wait(lambda: "/dashboard-two" in screen(), "HTTP request and response records")
            assert "opencode_http" in screen(), "HTTP JSON was misidentified by a built-in format"
            assert all(value in screen() for value in (
                "http_request", "http_response", "request_id:", "run_id:", "scheme:",
                "host:", "port:", "status:", "duration_ms:")), "HTTP metadata is missing"
            colored_http = tmux("capture-pane", "-epJ", "-S", "-2000")
            assert any("/dashboard-two" in line and "\x1b[" in line
                       for line in colored_http.splitlines()), "HTTP log lacks syntax highlighting"
            request("live", run_id)
            wait(lambda: "/dashboard-live" in screen(), "live HTTP log")
            for index in range(6):
                request("scroll-" + str(index), run_id)
            wait(lambda: "/dashboard-scroll-5" in screen(), "HTTP follow reaches newest records")
            keys(b"g/dashboard-scroll-0\r")
            wait(lambda: "/dashboard-scroll-0" in screen(), "scroll/search to earlier HTTP records")
            earlier_line = viewer_line()
            keys(b"\x1b[6~")
            wait(lambda: viewer_line() > earlier_line, "PageDown scrolls forward")
            later_line = viewer_line()
            keys(b"\x1b[5~")
            wait(lambda: viewer_line() < later_line and "/dashboard-scroll-0" in screen(),
                 "PageUp scrolls backward")
            request("paused", run_id)
            assert "/dashboard-paused" not in screen(), "new output moved the paused viewport"
            keys(b"G")
            wait(lambda: "/dashboard-paused" in screen(), "resume follow includes records received while paused")
            readers = descendants(dash)
            keys(b"q")
            wait(lambda: "Shell log" in screen() and "HTTP log" in screen(), "q returns to Gum")
            wait(lambda: all(not Path(f"/proc/{pid}").exists() for pid in readers), "idle lnav processes cleaned after q")
            keys(b"j\r")
            wait(lambda: "/dashboard-paused" in screen(), "reopen HTTP viewer at the live end")
            readers = descendants(dash)
            tmux("kill-pane", "-t", dash)
            wait(lambda: all(not Path(f"/proc/{pid}").exists() for pid in readers), "lnav processes cleaned on pane closure")
            tmux("select-window", "-t", pane)
            keys(b"\x02g")
            dash = wait(lambda: active() if active() != pane else None, "reopen closed dashboard pane")
            wait(lambda: "Shell log" in screen(), "reopened Gum menu")
            keys(b"\r")
            wait(lambda: "event=shell_start" in screen(), "reopened shell log")
            wait(lambda: viewer_line() == last_shell_line, "reopened shell log at live end")

            tmux("kill-pane", "-t", pane)
            keys(b"\x02o")
            wait(lambda: "origin pane is closed" in tmux("show-messages"), "closed-origin message")
            assert active() == dash
            tmux("select-window", "-t", second_pane)
            keys(b"\x02g")
            second_dash = wait(lambda: active() if active() not in (dash, second_pane) else None, "second log view")
            wait(lambda: "Shell log" in screen(), "second Gum menu")
            keys(b"\r")
            wait(lambda: "event=shell_start" in screen(), "shared log in second view")
            wait(lambda: viewer_line() == last_shell_line, "second view at live end")
            assert second_dash != dash
            keys(b"\x02o")
            wait(lambda: active() == second_pane, "second origin return")

            # Exact globs must wait for the producer without creating logs, even
            # in directories with spaces/glob metacharacters. Follow replacements
            # by name after rotation, rather than staying on the old inode.
            missing = home / "missing [logs]*?"
            missing.mkdir()
            missing_pane = tmux("new-window", "-P", "-F", "#{pane_id}",
                                "oc-dashboard", "view", str(missing))
            wait(lambda: "Shell log" in screen(), "missing-log chooser")
            keys(b"\r")
            wait(lambda: "No such file" in screen(), "lnav missing-file diagnostic")
            log = missing / "opencode-shell.log"
            assert not log.exists(), "viewer created a missing producer log"
            subprocess.run([wrapper, "-c", ":", "after-missing"],
                           env={**environment, "DEVCONTAINER_WORKSPACE_TMP": str(missing),
                                "OC_RUN_ID": "after-missing"}, check=True)
            wait(lambda: "after-missing" in screen(), "missing log appears without reopening")
            before_rotation = log.read_bytes()
            log.rename(missing / "rotated.log")
            subprocess.run([wrapper, "-c", ":", "after-rotation"],
                           env={**environment, "DEVCONTAINER_WORKSPACE_TMP": str(missing),
                                "OC_RUN_ID": "after-rotation"}, check=True)
            wait(lambda: "after-rotation" in screen(), "replacement log followed by name")
            assert (missing / "rotated.log").read_bytes() == before_rotation
            assert log.stat().st_mode & 0o777 == 0o600
            readers = descendants(missing_pane)
            keys(b"\x03")
            wait(lambda: "Shell log" in screen() and "HTTP log" in screen(), "Ctrl+C leaves missing-log view")
            wait(lambda: all(not Path(f"/proc/{pid}").exists() for pid in readers), "lnav cleaned after Ctrl+C")

            assert list((home / ".lnav").iterdir()) == [home / ".lnav" / "sentinel"]
            assert (home / ".lnav" / "sentinel").read_text() == "user-owned configuration\n"
            assert not (home / "xdg" / "lnav").exists(), "lnav wrote to caller XDG configuration"
            assert (root / "oc-dashboard" / "lnav").is_dir(), "lnav state is not workspace-local"
            assert (root / "oc-dashboard").stat().st_mode & 0o777 == 0o700
        except BaseException:
            print("Dashboard fixture screen:\n" + ascii(screen()))
            print("Dashboard fixture styles:\n" + ascii(tmux("capture-pane", "-epJ")))
            messages = [line for line in tmux("show-messages").splitlines()
                        if "command: capture-pane" not in line and "command: display-message -p" not in line]
            print("tmux messages:\n" + "\n".join(messages[:60]))
            print("tmux panes:\n" + tmux("list-panes", "-a", "-F", "#{pane_id} #{pane_current_command} #{@oc-log-origin}"))
            if readers:
                print("Log viewer processes:\n" + subprocess.run(
                    ["ps", "-o", "pid,ppid,pgid,stat,comm", "-p", ",".join(map(str, readers))],
                    capture_output=True, text=True).stdout)
            raise
        finally:
            tmux("kill-server")
            client.communicate(timeout=10)
            origin.shutdown()
            origin.server_close()


if __name__ == "__main__":
    tui_checks()
    print("PASS: Gum/lnav formats, scroll/search/follow/quit/cleanup, missing/rotated logs, workspace state, g/o navigation")
