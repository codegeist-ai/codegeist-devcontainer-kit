# Dockerfile - devcontainer image for codegeist.ai
#
# Why this exists:
# - Matches the planner devcontainer toolchain for product work.
# - Keeps Docker available inside the container via the custom entrypoint.
# - Installs the Java 25 and GraalVM toolchain needed by `app/codegeist`.
# - Provides a system Maven installation so the app does not need a wrapper.
# - Adds the Nix package manager for later package migration work without
#   switching the devcontainer setup to flakes yet.
#
# Inputs:
# - CONTAINER_USER and CONTAINER_GROUP select the login user created in the image.
# - CONTAINER_UID and CONTAINER_GID default to 1000 and can be aligned later by the
#   devcontainer runtime.
#
# Related files:
# - .devcontainer/docker-compose.yml
# - .devcontainer/devcontainer.json
# - .devcontainer/entrypoint.sh
FROM debian:bookworm-slim

ARG CONTAINER_USER=vscode
ARG CONTAINER_GROUP=vscode
ARG CONTAINER_UID=1000
ARG CONTAINER_GID=1000
ARG GRAALVM_VERSION=25.0.2

ENV LANG=C.UTF-8 \
    LC_CTYPE=C.UTF-8 \
    CONTAINER_USER=${CONTAINER_USER} \
    CONTAINER_GROUP=${CONTAINER_GROUP} \
    CONTAINER_UID=${CONTAINER_UID} \
    CONTAINER_GID=${CONTAINER_GID} \
    JAVA_HOME=/opt/graalvm \
    GRAALVM_HOME=/opt/graalvm \
    PATH=/opt/graalvm/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Install only the minimum needed to register third-party APT repos.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      gnupg \
      wget \
 && rm -rf /var/lib/apt/lists/*

# Register all extra APT repos before the main install step.
RUN install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
      | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
 && chmod a+r /etc/apt/keyrings/nodesource.gpg \
 && printf 'deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main\n' \
      > /etc/apt/sources.list.d/nodesource.list \
 && wget -qO- https://apt.fury.io/nushell/gpg.key \
      | gpg --dearmor -o /etc/apt/keyrings/fury-nushell.gpg \
 && chmod a+r /etc/apt/keyrings/fury-nushell.gpg \
 && printf 'deb [signed-by=/etc/apt/keyrings/fury-nushell.gpg] https://apt.fury.io/nushell/ /\n' \
      > /etc/apt/sources.list.d/fury-nushell.list \
 && curl -fsSL https://download.docker.com/linux/debian/gpg \
      -o /etc/apt/keyrings/docker.asc \
 && chmod a+r /etc/apt/keyrings/docker.asc \
 && . /etc/os-release \
 && printf 'Types: deb\nURIs: https://download.docker.com/linux/debian\nSuites: %s\nComponents: stable\nSigned-By: /etc/apt/keyrings/docker.asc\n' \
      "${VERSION_CODENAME}" > /etc/apt/sources.list.d/docker.sources \
 && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
      | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg \
 && chmod a+r /etc/apt/keyrings/microsoft.gpg \
 && printf 'Types: deb\nURIs: https://packages.microsoft.com/repos/code\nSuites: stable\nComponents: main\nSigned-By: /etc/apt/keyrings/microsoft.gpg\n' \
      > /etc/apt/sources.list.d/vscode.sources \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && chmod a+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && printf 'Types: deb\nURIs: https://cli.github.com/packages\nSuites: stable\nComponents: main\nArchitectures: amd64\nSigned-By: /etc/apt/keyrings/githubcli-archive-keyring.gpg\n' \
      > /etc/apt/sources.list.d/github-cli.sources

# Install the shared development toolchain in one APT transaction.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential \
      bash \
      ca-certificates \
      code \
      containerd.io \
      curl \
      docker-buildx-plugin \
      docker-ce \
      docker-ce-cli \
      docker-compose-plugin \
      gh \
      git \
      gnupg \
      netcat-openbsd \
      maven \
      nodejs \
      nushell \
      python3 \
      python3-pip \
      ripgrep \
      sudo \
      unzip \
      wget \
      xz-utils \
      zlib1g-dev \
  && rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh \
  | env UV_UNMANAGED_INSTALL=/usr/local/bin sh

RUN npm install -g --prefix /usr/local opencode-ai repomix @ast-grep/cli @devcontainers/cli \
 && rm -f /usr/local/bin/sg \
 && npm cache clean --force

RUN python3 -m pip install --break-system-packages --no-cache-dir \
      ddgr \
      lxml_html_clean \
      trafilatura

RUN curl -fsSL "https://github.com/boyter/scc/releases/latest/download/scc_Linux_x86_64.tar.gz" \
      -o /tmp/scc.tar.gz \
 && tar -xzf /tmp/scc.tar.gz -C /usr/local/bin scc \
 && chmod +x /usr/local/bin/scc \
 && rm -f /tmp/scc.tar.gz

RUN lazygit_version="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | python3 -c 'import json, sys; print(json.load(sys.stdin)["tag_name"].removeprefix("v"))')" \
 && curl -fsSL "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${lazygit_version}_Linux_x86_64.tar.gz" \
      -o /tmp/lazygit.tar.gz \
 && tar -xzf /tmp/lazygit.tar.gz -C /usr/local/bin lazygit \
 && chmod +x /usr/local/bin/lazygit \
 && rm -f /tmp/lazygit.tar.gz

RUN curl -fsSL "https://github.com/go-task/task/releases/latest/download/task_linux_amd64.tar.gz" \
      -o /tmp/task.tar.gz \
 && tar -xzf /tmp/task.tar.gz -C /usr/local/bin task \
 && chmod +x /usr/local/bin/task \
 && rm -f /tmp/task.tar.gz

RUN curl -fsSL "https://github.com/graalvm/graalvm-ce-builds/releases/download/jdk-${GRAALVM_VERSION}/graalvm-community-jdk-${GRAALVM_VERSION}_linux-x64_bin.tar.gz" \
      -o /tmp/graalvm.tar.gz \
 && install -d -m 0755 /opt/graalvm \
 && tar -xzf /tmp/graalvm.tar.gz --strip-components=1 -C /opt/graalvm \
 && /opt/graalvm/bin/java -version \
 && /opt/graalvm/bin/native-image --version \
 && rm -f /tmp/graalvm.tar.gz

RUN groupadd --gid "$CONTAINER_GID" "$CONTAINER_GROUP" \
 && useradd --uid "$CONTAINER_UID" --gid "$CONTAINER_GID" --create-home --shell /bin/bash "$CONTAINER_USER" \
 && install -d -m 0755 /data/Projects \
 && install -d -m 0755 /host \
 && install -d -m 0755 /nix \
 && ln -s /host/run/docker.sock /var/run/host-docker.sock \
 && install -d -m 0755 "/home/$CONTAINER_USER/.config/opencode" \
 && install -d -m 0755 "/home/$CONTAINER_USER/.m2" \
 && install -d -m 0755 "/home/$CONTAINER_USER/.local/share" \
 && install -d -m 0755 "/home/$CONTAINER_USER/.local/state/opencode" \
  && chown -R "$CONTAINER_UID:$CONTAINER_GID" /nix \
      "/home/$CONTAINER_USER/.config" \
      "/home/$CONTAINER_USER/.m2" \
      "/home/$CONTAINER_USER/.local" \
  && echo "$CONTAINER_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$CONTAINER_USER" \
  && chmod 0440 "/etc/sudoers.d/$CONTAINER_USER"

# Install Nix for the normal workspace user without enabling flakes or replacing
# the existing apt-managed toolchain yet.
RUN su - "$CONTAINER_USER" -c 'curl -L https://nixos.org/nix/install | sh -s -- --no-daemon --no-modify-profile'

# Make login shells pick up the single-user Nix profile as well. The plain PATH
# env is not enough because `bash -l` resets PATH from Debian's profile logic.
RUN printf '%s\n' \
      'if [ -e "/home/'"$CONTAINER_USER"'/.nix-profile/etc/profile.d/nix.sh" ]; then' \
      '  . "/home/'"$CONTAINER_USER"'/.nix-profile/etc/profile.d/nix.sh"' \
      'fi' \
      > /etc/profile.d/nix.sh

COPY .devcontainer/entrypoint.sh /usr/local/bin/devcontainer-entrypoint

RUN chmod +x /usr/local/bin/devcontainer-entrypoint

ENV USER=${CONTAINER_USER}
ENV HOME=/home/${CONTAINER_USER}
ENV NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV PATH=/home/${CONTAINER_USER}/.nix-profile/bin:/nix/var/nix/profiles/default/bin:${PATH}

VOLUME ["/var/lib/docker"]

ENTRYPOINT ["/usr/local/bin/devcontainer-entrypoint"]

USER ${CONTAINER_USER}
