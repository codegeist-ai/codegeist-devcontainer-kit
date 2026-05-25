#!/usr/bin/env bash
# remote-ssh-branch.sh - verify SSH SetEnv BRANCH selects a managed worktree
#
# Why this exists:
# - The bug this protects appeared when VS Code Remote SSH opened the repository
#   root while `SetEnv BRANCH=<branch>` was provided by the SSH config.
# - This test uses a real SSH client and sshd container so BRANCH must travel
#   through OpenSSH environment passing instead of being injected directly into
#   the devcontainer CLI process.
#
# Related files:
# - ../devcontainer.json
# - ../initialize.sh
# - ../docker-compose.yml
# - ./helpers.sh

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

repo_dir="$suite_tmp_dir/remote-ssh-branch-repo"
branch_name="develop0"
host_name="devcontainer-remote-ssh-test"
remote_user="$(expected_container_user)"
ssh_image="codegeist-devcontainer-kit-remote-ssh-test:test-$$"
ssh_image_context="$suite_tmp_dir/remote-ssh-image"
ssh_container_name="devcontainer-remote-ssh-test-$$"
ssh_container_id=""
workspace_container_id=""
ssh_dir="$suite_tmp_dir/remote-ssh"
ssh_key_file="$ssh_dir/id_ed25519"
ssh_config_file="$ssh_dir/config"
ssh_port=""
remote_log_file="$suite_tmp_dir/remote-ssh-devcontainer-up.log"
remote_command_file=""
expected_hostname=""
expected_workspace_folder=""
expected_user="$(id -u):$(id -u)"
expected_remote_workspace_folder=""
expected_user_name="$remote_user"
docker_sock_gid=""
remote_host_short=""

cleanup_remote_ssh() {
  if [ -n "$workspace_container_id" ]; then
    docker rm -f "$workspace_container_id" >/dev/null 2>&1 || true
  fi

  if [ -n "$ssh_container_id" ]; then
    docker rm -f "$ssh_container_id" >/dev/null 2>&1 || true
  fi

  docker rmi "$ssh_image" >/dev/null 2>&1 || true
}
trap cleanup_remote_ssh EXIT

[[ -S /var/run/docker.sock ]] || fail "Docker socket is required for remote SSH devcontainer test"

if ! docker image inspect codegeist-devcontainer-kit:local >/dev/null 2>&1; then
  task_project docker-build >/dev/null
fi

create_git_fixture_repo "$repo_dir"
prepare_devcontainer_home "$repo_dir"

mkdir -p "$ssh_image_context" "$ssh_dir"
cat >"$ssh_image_context/Dockerfile" <<'EOF'
FROM codegeist-devcontainer-kit:local
USER root
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends openssh-server \
 && rm -rf /var/lib/apt/lists/* \
 && install -d -m 0755 /run/sshd \
 && printf '\nAcceptEnv BRANCH\nPasswordAuthentication no\nKbdInteractiveAuthentication no\nPubkeyAuthentication yes\nPermitRootLogin no\n' >> /etc/ssh/sshd_config
EOF

docker build -t "$ssh_image" "$ssh_image_context" >/dev/null
ssh-keygen -t ed25519 -N "" -C "devcontainer remote ssh test" -f "$ssh_key_file" >/dev/null

docker_sock_gid="$(stat -c %g /var/run/docker.sock)"
ssh_container_id="$(docker run -d --rm \
  --name "$ssh_container_name" \
  --user root \
  --entrypoint /bin/bash \
  -p 127.0.0.1::22 \
  -e REMOTE_USER="$remote_user" \
  -e DOCKER_SOCK_GID="$docker_sock_gid" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$repo_dir:$repo_dir" \
  -v "$ssh_key_file.pub:/tmp/authorized_keys:ro" \
  "$ssh_image" \
  -lc 'set -euo pipefail
user_home="$(getent passwd "$REMOTE_USER" | cut -d: -f6)"
primary_group="$(id -gn "$REMOTE_USER")"
docker_group="$(getent group "$DOCKER_SOCK_GID" | cut -d: -f1 || true)"
if [ -z "$docker_group" ]; then
  docker_group="dockerhost"
  groupadd --gid "$DOCKER_SOCK_GID" "$docker_group"
fi
usermod -aG "$docker_group" "$REMOTE_USER"
install -d -m 0755 /run/sshd
install -d -m 0700 -o "$REMOTE_USER" -g "$primary_group" "$user_home/.ssh"
install -m 0600 -o "$REMOTE_USER" -g "$primary_group" /tmp/authorized_keys "$user_home/.ssh/authorized_keys"
exec /usr/sbin/sshd -D -e')"

ssh_port="$(docker port "$ssh_container_id" 22/tcp)"
ssh_port="${ssh_port##*:}"

cat >"$ssh_config_file" <<EOF
Host $host_name
  HostName 127.0.0.1
  Port $ssh_port
  User $remote_user
  IdentityFile $ssh_key_file
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
  SetEnv BRANCH=$branch_name
EOF

for _ in 1 2 3 4 5 6 7 8 9 10; do
  if ssh -F "$ssh_config_file" "$host_name" 'test "${BRANCH:-}" = "develop0" && docker ps >/dev/null' >/dev/null 2>&1; then
    break
  fi

  sleep 1
done

ssh -F "$ssh_config_file" "$host_name" 'test "${BRANCH:-}" = "develop0" && docker ps >/dev/null' >/dev/null \
  || fail "SSH host did not receive SetEnv BRANCH or cannot access Docker"
remote_host_short="$(ssh -F "$ssh_config_file" "$host_name" 'hostname -s 2>/dev/null || hostname')"

remote_command_file="$repo_dir/.remote-ssh-devcontainer-up.sh"
cat >"$remote_command_file" <<EOF
#!/usr/bin/env bash
set -euo pipefail

test "\${BRANCH:-}" = "$branch_name"
export HOME="$repo_dir"
mkdir -p "\$HOME/.config/opencode" "\$HOME/.local/share/opencode" "\$HOME/.local/state/opencode"
touch "\$HOME/.Xauthority"
devcontainer up --remove-existing-container --workspace-folder "$repo_dir"
EOF
chmod +x "$remote_command_file"

ssh -F "$ssh_config_file" "$host_name" "bash '$remote_command_file'" | tee "$remote_log_file"

workspace_container_id="$(extract_container_id_from_log "$remote_log_file" || true)"
[[ -n "$workspace_container_id" ]] || fail "could not extract workspace container id from remote SSH devcontainer output"

expected_workspace_folder="$(expected_workspace_folder "$repo_dir" "$branch_name")"
expected_remote_workspace_folder="$(expected_remote_workspace_folder "$repo_dir" "$branch_name")"
[[ "$(extract_remote_workspace_folder_from_log "$remote_log_file" || true)" = "$expected_remote_workspace_folder" ]] || fail "remote SSH devcontainer did not report expected worktree workspace folder"

[[ -d "$repo_dir/.worktrees/$branch_name" ]] || fail "remote SSH BRANCH did not create selected worktree"
[[ -L "$repo_dir/.worktrees/$branch_name/.local.env" ]] || fail "remote SSH worktree .local.env is not a symlink"
[[ "$(<"$repo_dir/.devcontainer/.env")" == *"BRANCH=$branch_name"* ]] || fail "remote SSH initializeCommand did not persist BRANCH"
[[ "$(<"$repo_dir/.devcontainer/.env")" == *"DEVCONTAINER_WORKSPACE_FOLDER=$expected_workspace_folder"* ]] || fail "remote SSH generated env does not select worktree workspace"

expected_hostname="$(fit_hostname "$(slug_hostname_part "$remote_host_short")-$(slug_hostname_part "$(basename "$repo_dir")")-$(slug_hostname_part "$branch_name")")"
[[ "$(<"$repo_dir/.devcontainer/compose.local.gen.yml")" == *"hostname: $expected_hostname"* ]] || fail "remote SSH generated compose file does not set branch hostname"

for _ in 1 2 3 4 5 6 7 8 9 10; do
  if docker exec -w "$expected_workspace_folder" -u "$expected_user_name" "$workspace_container_id" bash -lc 'test "$(id -un)" = "'"$expected_user_name"'" && test "$(hostname)" = "'"$expected_hostname"'" && test "$DEVCONTAINER_HOSTNAME" = "'"$expected_hostname"'" && test "$DEVCONTAINER_WORKSPACE_FOLDER" = "'"$expected_workspace_folder"'" && test "$DEVCONTAINER_UID:$DEVCONTAINER_GID" = "'"$expected_user"'" && test "$(git rev-parse --abbrev-ref HEAD)" = "develop0" && docker ps >/dev/null'; then
    pass "Remote SSH SetEnv BRANCH starts selected worktree through Dev Containers CLI"
    exit 0
  fi

  sleep 1
done

fail "remote SSH BRANCH start did not expose selected worktree, Docker, and generated runtime env"
