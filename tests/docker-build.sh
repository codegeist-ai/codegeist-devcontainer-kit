#!/usr/bin/env bash
# docker-build.sh - verify the kit image builds through its Taskfile
#
# Simple tool/file checks share one disposable container and fail at the first
# failed assertion. Interactive completion, scanning, and startup failure paths
# retain their own containers because they require different runtime inputs.
#
# Related files:
# - ../Taskfile.yaml
# - ../Dockerfile.base

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

local_suite=0
if [ -z "${suite_tmp_dir:-}" ]; then
  setup_suite
  local_suite=1
fi

if [ "$local_suite" -eq 1 ]; then
  trap cleanup_suite EXIT
fi

task_project docker-build

# Keep this block strict: a later successful command must not hide an earlier
# version/path mismatch. Negated matches need an explicit failure branch.
docker run --rm --entrypoint bash -w /tmp codegeist-devcontainer-kit:local -lc '
  set -euo pipefail
  . /etc/os-release
  test "$ID" = ubuntu
  test "$VERSION_ID" = 26.04
  test "$VERSION_CODENAME" = resolute
  grep -F "URIs: https://download.docker.com/linux/ubuntu" /etc/apt/sources.list.d/docker.sources >/dev/null
  grep -F "Suites: resolute" /etc/apt/sources.list.d/docker.sources >/dev/null
  if grep -R -E "download\.docker\.com/linux/debian|packages\.microsoft\.com/debian/12|bookworm" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
    printf "Unexpected Debian package source in Ubuntu image\n" >&2
    exit 1
  fi
  docker compose version >/dev/null
  docker buildx version >/dev/null
  go version >/dev/null
  pwsh -NoLogo -NoProfile -Command "exit 0"
  code --version >/dev/null
  python3 -c "import graphify, lxml_html_clean, trafilatura"
  ddgr --version >/dev/null
  mitmdump --version >/dev/null
  ssh-audit -h >/dev/null
  qemu-system-x86_64 --version >/dev/null
  pass --version >/dev/null
  test "$(command -v docker-credential-pass)" = "/usr/local/bin/docker-credential-pass"
  test -x /usr/local/bin/docker-credential-pass
  docker-credential-pass version \
    | grep -Fx "docker-credential-pass (github.com/docker/docker-credential-helpers) v0.9.12" >/dev/null
  codegeist --version >/dev/null
  jbang --version >/dev/null
  renovate --version >/dev/null
  test "$(command -v podman)" = "/usr/bin/podman"
  podman --version | grep -E "^podman version " >/dev/null

  export BITWARDENCLI_APPDATA_DIR=/tmp/bitwarden-cli-test
  install -d -m 0700 "$BITWARDENCLI_APPDATA_DIR"
  printf "%s\n" "{}" >"$BITWARDENCLI_APPDATA_DIR/data.json"
  test "$(command -v bw)" = "/usr/local/bin/bw"
  test -x /usr/local/bin/bw
  test "$(bw --version)" = "2026.10.1"

  gitleaks version >/dev/null
  ffmpeg -version >/dev/null
  whisper-cli --version | grep -F "1.9.5" >/dev/null
  vhs --version | grep -F "0.12.1" >/dev/null
  ttyd --version >/dev/null
  hugo version | grep -F "v0.169.0" >/dev/null
  tea --version | grep -F "0.16.0" >/dev/null
  java -version 2>&1 | grep -F "25.0.4.1.1" >/dev/null
  nvim --headless "+quit"
  gum --version >/dev/null
  rg --version >/dev/null
  bat --version >/dev/null
  btop --version >/dev/null
  eza --version >/dev/null
  dust --version >/dev/null
  fzf --version >/dev/null
  tmux -V >/dev/null
  uuidgen | grep -Eq "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
  tofu -version >/dev/null
  terraform version >/dev/null
  vault version >/dev/null
  test ! -L /usr/local/bin/bat
  if dpkg-query -W ripgrep >/dev/null 2>&1; then
    printf "ripgrep must use the native upstream installation\n" >&2
    exit 1
  fi

  # V2 creates its runtime temp directory even for --version; inspect the image first.
  test ! -e /tmp/opencode
  test "$(opencode --version)" = "opencode v2.2.5"
  test -d /tmp/ws-data
  test ! -e /usr/local/bin/chrome
  test "$(command -v oc-record)" = "/usr/local/bin/oc-record"
  dpkg-query -W bash-completion >/dev/null
  test -s /usr/share/bash-completion/completions/task
'

trivy_fixture_dir="$suite_tmp_dir/trivy-config"
mkdir -p "$trivy_fixture_dir"
printf '%s\n' \
  'FROM scratch' \
  'USER root' \
  >"$trivy_fixture_dir/Dockerfile"

set +e
trivy_config_output="$(docker run --rm \
  --entrypoint trivy \
  --mount "type=bind,src=$trivy_fixture_dir,dst=/scan,readonly" \
  codegeist-devcontainer-kit:local \
  config \
  --cache-dir /tmp/trivy-cache \
  --skip-check-update \
  --skip-version-check \
  --severity HIGH \
  --exit-code 1 \
  --format json \
  --quiet \
  /scan)"
trivy_config_status="$?"
set -e

[ "$trivy_config_status" -eq 1 ] \
  || fail "Trivy config scan returned $trivy_config_status instead of the expected finding exit 1"
printf '%s' "$trivy_config_output" \
  | jq -e '
      [
        .Results[]?.Misconfigurations[]?
        | select(
            .ID == "DS-0002"
            and .Severity == "HIGH"
            and (.Message | contains("Last USER command in Dockerfile should not be"))
          )
      ]
      | length == 1
    ' >/dev/null \
  || fail "Trivy config scan did not report the expected DS-0002 root-user finding"

docker run --rm --entrypoint bash codegeist-devcontainer-kit:local -ic \
  '_completion_loader task >/dev/null 2>&1; status="$?"; { [ "$status" -eq 0 ] || [ "$status" -eq 124 ]; } && complete -p task | grep -F "complete -F _task task" >/dev/null'
# Exercise the normal entrypoint with mitmproxy's native upstream CA settings
# for the local TLS origin. Both tmux paths and real clients share its listener.
oc_workspace="$suite_tmp_dir/opencode-workspace"
mkdir -p "$oc_workspace/.tmp/opencode-http" "$oc_workspace/.devcontainer/scripts"
cp -p "$project_root/scripts/chrome.sh" "$oc_workspace/.devcontainer/scripts/"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=oc-http-test \
  -addext subjectAltName=IP:127.0.0.2 \
  -keyout "$oc_workspace/origin.key" -out "$oc_workspace/origin.pem" >/dev/null 2>&1
cat >"$oc_workspace/.tmp/opencode-http/config.yaml" <<EOF
ssl_verify_upstream_trusted_ca: "$oc_workspace/origin.pem"
ssl_verify_upstream_trusted_confdir: /etc/ssl/certs
EOF
docker run --rm --privileged \
  -e "DEVCONTAINER_WORKSPACE_FOLDER=$oc_workspace" \
  -e "DEVCONTAINER_WORKSPACE_TMP=$oc_workspace/.tmp" \
  -e "DEVCONTAINER_PROJECT_ROOT=$project_root" \
  -e "suite_tmp_dir=$suite_tmp_dir" \
  -e OC_SHELL_BIN=/usr/local/lib/oc-shell/bash \
  --mount "type=bind,src=$project_root,dst=$project_root" \
  -w "$project_root" \
  codegeist-devcontainer-kit:local \
  bash -c 'tests/opencode-tmux-wrapper.sh && tests/opencode-bash.sh && python3 tests/opencode-http.py "$suite_tmp_dir/opencode-tmux-wrapper/outside.capture.proxy"'

# Proxy failures are asynchronous: the foreground command must still execute and
# own the exit status. Wait for the real diagnostic inside the test, not runtime.
failed_workspace="$suite_tmp_dir/opencode-invalid-log"
mkdir -p "$failed_workspace/.tmp/opencode-http.jsonl" "$failed_workspace/.devcontainer/scripts"
cp -p "$project_root/scripts/chrome.sh" "$failed_workspace/.devcontainer/scripts/"
foreground_status=0
docker run --rm --privileged \
  -e "DEVCONTAINER_WORKSPACE_FOLDER=$failed_workspace" \
  -e "DEVCONTAINER_WORKSPACE_TMP=$failed_workspace/.tmp" \
  -e "DEVCONTAINER_PROJECT_ROOT=$project_root" \
  --mount "type=bind,src=$project_root,dst=$project_root" \
  -w "$project_root" \
  codegeist-devcontainer-kit:local bash -c '
    source tests/helpers.sh
    touch "$DEVCONTAINER_WORKSPACE_FOLDER/foreground-started"
    wait_for_check "proxy log-open error" grep -F IsADirectoryError \
      "$DEVCONTAINER_WORKSPACE_TMP/opencode-http/proxy.log"
    exit 23
  ' >"$failed_workspace/startup.log" 2>&1 || foreground_status="$?"
[ "$foreground_status" = 23 ] \
  || fail "foreground exit expected=23 actual=$foreground_status: $(<"$failed_workspace/startup.log")"
[ -f "$failed_workspace/foreground-started" ] || fail "proxy failure prevented the foreground command"
pass "proxy startup failure is logged and preserves the foreground command's exit status"

# In contrast, directory preparation is synchronous and must fail before exec.
invalid_state_workspace="$suite_tmp_dir/opencode-invalid-state"
mkdir -p "$invalid_state_workspace/.tmp"
touch "$invalid_state_workspace/.tmp/opencode-http"
if docker run --rm --privileged \
  -e "DEVCONTAINER_WORKSPACE_FOLDER=$invalid_state_workspace" \
  -e "DEVCONTAINER_WORKSPACE_TMP=$invalid_state_workspace/.tmp" \
  --mount "type=bind,src=$project_root,dst=$project_root" \
  codegeist-devcontainer-kit:local touch "$invalid_state_workspace/must-not-start" \
  >"$invalid_state_workspace/startup.log" 2>&1; then
  fail "synchronous runtime preparation failure was ignored"
fi
[ ! -e "$invalid_state_workspace/must-not-start" ] || fail "command ran after synchronous setup failure"
# Host-forwarded audio is not part of isolated-network acceptance. Retain the
# recorder's missing-transport regression until its removal in T027.
docker run --rm \
  --entrypoint bash \
  -e "DEVCONTAINER_PROJECT_ROOT=$project_root" \
  -e "suite_tmp_dir=$suite_tmp_dir" \
  -e "OC_RECORD_BIN=/usr/local/bin/oc-record" \
  -e "OC_RECORD_EXPECT_START_FAILURE=true" \
  --mount "type=bind,src=$project_root,dst=$project_root" \
  -w "$project_root" \
  codegeist-devcontainer-kit:local \
  tests/oc-record.sh
pass "docker image builds with terminal tools, Trivy scanning, shared commands, and Task completion available"
