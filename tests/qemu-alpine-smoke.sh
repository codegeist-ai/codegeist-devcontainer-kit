#!/usr/bin/env bash
# qemu-alpine-smoke.sh - boot a downloaded Alpine ISO through QEMU
#
# Why this exists:
# - Verifies the devcontainer image includes working QEMU tooling, not just
#   package names.
# - Requires /dev/kvm so the smoke test proves hardware virtualization works.
# - Downloads a fixed Alpine ISO into the repo-local test cache to avoid
#   depending on arbitrary /tmp bind-mount visibility from the Docker daemon.
#
# Related files:
# - ../Dockerfile.base
# - ../Taskfile.yaml
# - ./run.sh

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

image_name="codegeist-devcontainer-kit:local"
cache_dir="${DEVCONTAINER_QEMU_CACHE_DIR:-$project_root/.test-tmp/qemu-cache}"
alpine_version="3.20.3"
alpine_major_minor="${alpine_version%.*}"
alpine_file="alpine-standard-${alpine_version}-x86_64.iso"
alpine_base_url="https://dl-cdn.alpinelinux.org/alpine/v${alpine_major_minor}/releases/x86_64"
alpine_iso_url="${alpine_base_url}/${alpine_file}"

if ! docker image inspect "$image_name" >/dev/null 2>&1; then
  task_project docker-build
fi

mkdir -p "$cache_dir"

docker_args=(
  --rm
  --privileged
  --entrypoint bash
  -v "$cache_dir:/qemu-cache"
)

if [ -e /dev/kvm ]; then
  docker_args+=(--device /dev/kvm:/dev/kvm --group-add "$(stat -c %g /dev/kvm)")
fi

docker run \
  "${docker_args[@]}" \
  "$image_name" \
  -lc '
    set -euo pipefail

    alpine_iso_url="'"$alpine_iso_url"'"
    alpine_file="'"$alpine_file"'"
    qemu_log="/qemu-cache/alpine-qemu.log"

    cd /qemu-cache

    if [ ! -f "$alpine_file" ]; then
      curl -fsSL --retry 5 --retry-delay 2 -o "$alpine_file" "$alpine_iso_url"
    fi

    command -v qemu-system-x86_64 >/dev/null
    command -v qemu-img >/dev/null
    command -v expect >/dev/null
    qemu-img info "$alpine_file" >/dev/null

    if [ ! -e /dev/kvm ]; then
      printf "/dev/kvm is required for this smoke test.\n" >&2
      exit 1
    fi

    if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
      printf "/dev/kvm must be readable and writable inside the container.\n" >&2
      exit 1
    fi

    printf "KVM device is available; booting Alpine with hardware acceleration.\n"

    rm -f "$qemu_log"
    if ! expect <<EXPECT_EOF | tee "$qemu_log"
set timeout 45
spawn qemu-system-x86_64 \
  -machine accel=kvm \
  -cpu host \
  -m 512M \
  -cdrom "$alpine_file" \
  -boot d \
  -display none \
  -serial stdio \
  -no-reboot

expect {
  -exact "localhost login:" {
    set qemu_pid [exp_pid]
    exec kill -TERM \$qemu_pid
    exit 0
  }
  timeout {
    exit 124
  }
  eof {
    exit 1
  }
}
EXPECT_EOF
    then
      printf "Alpine login prompt was not found in QEMU output.\n" >&2
      if [ -f "$qemu_log" ]; then
        tail -n 80 "$qemu_log" >&2 || true
      fi
      exit 1
    fi
  '

pass "QEMU downloads Alpine ${alpine_version} and boots to login with KVM acceleration"
