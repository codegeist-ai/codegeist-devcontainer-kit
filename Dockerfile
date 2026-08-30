# Devcontainer image for codegeist.ai
#
# Why this exists:
# - Matches the planner devcontainer toolchain for product work.
# - Keeps Docker available inside the container via the custom entrypoint.
# - Installs the Java 25 and GraalVM toolchain needed by `app/codegeist`.
# - Provides a system Maven installation so the app does not need a wrapper.
# - Adds the Nix package manager for later package migration work without
#   switching the devcontainer setup to flakes yet.
# - Includes JBang, Hugo, Kubernetes, Terraform, Ansible, PowerShell, QEMU/KVM,
#   password-store, speech, YAML, terminal productivity and capture, network,
#   security-scan, and FTP tools so the shared workspace can handle Java
#   scripting, site, infrastructure, virtualization, deployment, docs previews,
#   and external scan tasks.
# - Installs the Codegeist CLI through the upstream Linux installer from the
#   codegeist repository's main branch.
# - `scripts/release-build.sh` copies this source file to release `Dockerfile` so
#   consuming repositories still receive the standard Dev Containers filename.
# - `initialize.sh` copies the released `Dockerfile` into `Dockerfile.merged.gen`
#   and appends an optional `.codegeist/Dockerfile` fragment before Compose
#   builds.
#
# Inputs:
# - CONTAINER_USER and CONTAINER_GROUP select the login user created in the image.
# - CONTAINER_UID and CONTAINER_GID default to 1000 and can be aligned later by the
#   devcontainer runtime.
# - VHS_VERSION and TTYD_VERSION select terminal-rendering tools used by
#   documentation capture workflows in consuming repositories.
# - TEA_VERSION pins the official Gitea CLI binary installed from dl.gitea.com.
# - TRIVY_VERSION pins the official Trivy security scanner release.
#
# Related files:
# - docker-compose.yml
# - devcontainer.json
# - entrypoint.sh
# - initialize.sh
# - scripts/release-build.sh
FROM debian:bookworm-slim

ARG CONTAINER_USER=vscode
ARG CONTAINER_GROUP=vscode
ARG CONTAINER_UID=1000
ARG CONTAINER_GID=1000
ARG GRAALVM_VERSION=25.0.2
ARG HUGO_VERSION=0.147.9
ARG VHS_VERSION=0.11.0
ARG TTYD_VERSION=1.7.7
ARG TEA_VERSION=0.14.2
ARG TRIVY_VERSION=0.74.0

ENV LANG=C.UTF-8 \
    LC_CTYPE=C.UTF-8 \
    CONTAINER_USER=${CONTAINER_USER} \
    CONTAINER_GROUP=${CONTAINER_GROUP} \
    CONTAINER_UID=${CONTAINER_UID} \
    CONTAINER_GID=${CONTAINER_GID} \
    JAVA_HOME=/opt/graalvm \
    GRAALVM_HOME=/opt/graalvm \
    PATH=/opt/nvim/bin:/opt/graalvm/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

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
 && printf 'Types: deb\nURIs: https://packages.microsoft.com/debian/12/prod\nSuites: bookworm\nComponents: main\nSigned-By: /etc/apt/keyrings/microsoft.gpg\n' \
      > /etc/apt/sources.list.d/microsoft-prod.sources \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && chmod a+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && printf 'Types: deb\nURIs: https://cli.github.com/packages\nSuites: stable\nComponents: main\nArchitectures: amd64\nSigned-By: /etc/apt/keyrings/githubcli-archive-keyring.gpg\n' \
       > /etc/apt/sources.list.d/github-cli.sources \
 && curl -fsSL https://apt.releases.hashicorp.com/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/hashicorp-archive-keyring.gpg \
 && chmod a+r /etc/apt/keyrings/hashicorp-archive-keyring.gpg \
 && printf 'Types: deb\nURIs: https://apt.releases.hashicorp.com\nSuites: %s\nComponents: main\nSigned-By: /etc/apt/keyrings/hashicorp-archive-keyring.gpg\n' \
      "${VERSION_CODENAME}" > /etc/apt/sources.list.d/hashicorp.sources

# Install the shared development toolchain in one APT transaction.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential \
      ansible \
      bash \
      bash-completion \
      ca-certificates \
      code \
      containerd.io \
      curl \
      direnv \
      docker-buildx-plugin \
      docker-ce \
      docker-ce-cli \
      docker-compose-plugin \
      espeak-ng \
      ffmpeg \
      ftp \
      gh \
      git \
      jq \
      lftp \
      gnupg \
      bridge-utils \
      cloud-image-utils \
      cpio \
      dnsmasq \
      expect \
      hping3 \
      iproute2 \
      iputils-ping \
      iptables \
      kmod \
      netcat-openbsd \
      nmap \
      maven \
      nodejs \
      nushell \
      openssh-client \
      pass \
      powershell \
      procps \
      pwgen \
      python3 \
      python3-dev \
      python3-pip \
      qemu-kvm \
      qemu-system-x86 \
      qemu-utils \
      rsync \
      sslscan \
      sshpass \
      socat \
      sudo \
      terraform \
      testssl.sh \
      tigervnc-viewer \
      unzip \
      wget \
      x11-apps \
      x11-utils \
      xauth \
      xvfb \
      xz-utils \
      zlib1g-dev \
  && rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh \
  | env UV_UNMANAGED_INSTALL=/usr/local/bin sh

RUN npm install -g --prefix /usr/local opencode-ai repomix @ast-grep/cli @devcontainers/cli @mermaid-js/mermaid-cli tiktoken-cli \
 && rm -f /usr/local/bin/sg \
 && rm -rf /tmp/opencode \
 && npm cache clean --force

RUN python3 -m pip install --break-system-packages --no-cache-dir \
      ddgr \
      graphifyy \
      lxml_html_clean \
      ssh-audit==3.9.0 \
      trafilatura

RUN curl -fsSL "https://github.com/boyter/scc/releases/latest/download/scc_Linux_x86_64.tar.gz" \
      -o /tmp/scc.tar.gz \
 && tar -xzf /tmp/scc.tar.gz -C /usr/local/bin scc \
 && chmod +x /usr/local/bin/scc \
 && rm -f /tmp/scc.tar.gz

# Install the latest official Linux x86_64 terminal tools without aliases or
# user configuration. Versioned asset names use one direct release lookup each;
# stable asset names can use GitHub's releases/latest/download path directly.
RUN curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz" \
      -o /tmp/nvim.tar.gz \
 && install -d -m 0755 /opt/nvim \
 && tar -xzf /tmp/nvim.tar.gz --strip-components=1 -C /opt/nvim \
 && rm -f /tmp/nvim.tar.gz

RUN gum_url="$(curl -fsSL https://api.github.com/repos/charmbracelet/gum/releases/latest \
      | jq -er '.assets[] | select(.name | test("_Linux_x86_64\\.tar\\.gz$")) | .browser_download_url')" \
 && curl -fsSL "$gum_url" -o /tmp/gum.tar.gz \
 && tar -xzf /tmp/gum.tar.gz --wildcards --strip-components=1 \
      -C /usr/local/bin '*/gum' \
 && rm -f /tmp/gum.tar.gz

RUN rg_url="$(curl -fsSL https://api.github.com/repos/BurntSushi/ripgrep/releases/latest \
      | jq -er '.assets[] | select(.name | test("-x86_64-unknown-linux-musl\\.tar\\.gz$")) | .browser_download_url')" \
 && curl -fsSL "$rg_url" -o /tmp/rg.tar.gz \
 && tar -xzf /tmp/rg.tar.gz --wildcards --strip-components=1 \
      -C /usr/local/bin '*/rg' \
 && rm -f /tmp/rg.tar.gz

RUN bat_url="$(curl -fsSL https://api.github.com/repos/sharkdp/bat/releases/latest \
      | jq -er '.assets[] | select(.name | test("-x86_64-unknown-linux-gnu\\.tar\\.gz$")) | .browser_download_url')" \
 && curl -fsSL "$bat_url" -o /tmp/bat.tar.gz \
 && tar -xzf /tmp/bat.tar.gz --wildcards --strip-components=1 \
      -C /usr/local/bin '*/bat' \
 && rm -f /tmp/bat.tar.gz

RUN curl -fsSL "https://github.com/aristocratos/btop/releases/latest/download/btop-x86_64-unknown-linux-musl.tar.gz" \
      -o /tmp/btop.tar.gz \
 && tar -xzf /tmp/btop.tar.gz --strip-components=3 \
      -C /usr/local/bin ./btop/bin/btop \
 && rm -f /tmp/btop.tar.gz

RUN curl -fsSL "https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-gnu.tar.gz" \
      -o /tmp/eza.tar.gz \
 && tar -xzf /tmp/eza.tar.gz -C /usr/local/bin ./eza \
 && rm -f /tmp/eza.tar.gz

RUN dust_url="$(curl -fsSL https://api.github.com/repos/bootandy/dust/releases/latest \
      | jq -er '.assets[] | select(.name | test("-x86_64-unknown-linux-gnu\\.tar\\.gz$")) | .browser_download_url')" \
 && curl -fsSL "$dust_url" -o /tmp/dust.tar.gz \
 && tar -xzf /tmp/dust.tar.gz --wildcards --strip-components=1 \
      -C /usr/local/bin '*/dust' \
 && rm -f /tmp/dust.tar.gz

RUN fzf_url="$(curl -fsSL https://api.github.com/repos/junegunn/fzf/releases/latest \
      | jq -er '.assets[] | select(.name | test("-linux_amd64\\.tar\\.gz$")) | .browser_download_url')" \
 && curl -fsSL "$fzf_url" -o /tmp/fzf.tar.gz \
 && tar -xzf /tmp/fzf.tar.gz -C /usr/local/bin fzf \
 && rm -f /tmp/fzf.tar.gz

RUN lazygit_version="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | python3 -c 'import json, sys; print(json.load(sys.stdin)["tag_name"].removeprefix("v"))')" \
 && curl -fsSL "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${lazygit_version}_Linux_x86_64.tar.gz" \
      -o /tmp/lazygit.tar.gz \
 && tar -xzf /tmp/lazygit.tar.gz -C /usr/local/bin lazygit \
 && chmod +x /usr/local/bin/lazygit \
 && rm -f /tmp/lazygit.tar.gz

RUN tea_asset="tea-${TEA_VERSION}-linux-amd64" \
 && curl -fsSL "https://dl.gitea.com/tea/${TEA_VERSION}/${tea_asset}" \
      -o "/tmp/${tea_asset}" \
 && install -m 0755 "/tmp/${tea_asset}" /usr/local/bin/tea \
 && rm -f "/tmp/${tea_asset}" \
 && tea --version

RUN curl -fsSL "https://raw.githubusercontent.com/aquasecurity/trivy/v${TRIVY_VERSION}/contrib/install.sh" \
      | sh -s -- -b /usr/local/bin "v${TRIVY_VERSION}" \
 && trivy --version

RUN curl -fsSL "https://github.com/go-task/task/releases/latest/download/task_linux_amd64.tar.gz" \
      -o /tmp/task.tar.gz \
 && tar -xzf /tmp/task.tar.gz -C /usr/local/bin task \
 && chmod +x /usr/local/bin/task \
 && task --completion bash > /usr/share/bash-completion/completions/task \
 && rm -f /tmp/task.tar.gz

RUN curl -fsSL "https://github.com/charmbracelet/vhs/releases/download/v${VHS_VERSION}/vhs_${VHS_VERSION}_amd64.deb" \
      -o /tmp/vhs.deb \
 && dpkg -i /tmp/vhs.deb \
 && rm -f /tmp/vhs.deb \
 && vhs --version \
 && curl -fsSL "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.x86_64" \
      -o /usr/local/bin/ttyd \
 && chmod +x /usr/local/bin/ttyd \
 && ttyd --version

RUN curl -fsSL https://raw.githubusercontent.com/codegeist-ai/codegeist/main/scripts/install/codegeist-install-linux.sh \
      | env CODEGEIST_INSTALL_DIR=/opt/codegeist CODEGEIST_BIN_DIR=/usr/local/bin bash \
 && codegeist --version

RUN curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" \
      -o /usr/local/bin/yq \
 && chmod +x /usr/local/bin/yq \
 && yq --version \
 && curl -fsSL "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
      -o /usr/local/bin/kubectl \
 && chmod +x /usr/local/bin/kubectl \
 && kubectl version --client=true \
 && curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
      | bash \
 && helm version \
 && curl -fsSL "https://github.com/derailed/k9s/releases/latest/download/k9s_linux_amd64.deb" \
      -o /tmp/k9s_linux_amd64.deb \
 && apt-get update \
 && apt-get install -y --no-install-recommends /tmp/k9s_linux_amd64.deb \
 && rm -f /tmp/k9s_linux_amd64.deb \
 && rm -rf /var/lib/apt/lists/* \
 && k9s version \
 && curl -fsSL https://talos.dev/install | sh \
 && talosctl version --client

RUN curl -fsSL "https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_Linux-64bit.tar.gz" \
      -o /tmp/hugo.tar.gz \
  && tar -xzf /tmp/hugo.tar.gz -C /tmp hugo \
  && install -m 0755 /tmp/hugo /usr/local/bin/hugo \
  && hugo version \
  && rm -f /tmp/hugo.tar.gz /tmp/hugo

RUN curl -fsSL "https://dl.google.com/linux/direct/google-chrome-stable_current_$(dpkg --print-architecture).deb" \
      -o /tmp/chrome.deb \
  && apt-get update \
  && apt-get install -y --no-install-recommends /tmp/chrome.deb \
  && rm -f /tmp/chrome.deb \
  && rm -rf /var/lib/apt/lists/* \
  && google-chrome --version

RUN install -d -m 0755 /etc/opt/chrome/policies/managed \
  && printf '%s\n' \
      '{' \
      '  "HardwareAccelerationModeEnabled": false' \
      '}' \
      > /etc/opt/chrome/policies/managed/disable-hardware-accel.json

RUN curl -fsSL "https://github.com/graalvm/graalvm-ce-builds/releases/download/jdk-${GRAALVM_VERSION}/graalvm-community-jdk-${GRAALVM_VERSION}_linux-x64_bin.tar.gz" \
      -o /tmp/graalvm.tar.gz \
 && install -d -m 0755 /opt/graalvm \
 && tar -xzf /tmp/graalvm.tar.gz --strip-components=1 -C /opt/graalvm \
 && /opt/graalvm/bin/java -version \
 && /opt/graalvm/bin/native-image --version \
 && rm -f /tmp/graalvm.tar.gz

RUN curl -Ls https://sh.jbang.dev \
      | env JBANG_DIR=/opt/jbang bash -s - app setup \
 && ln -sf /opt/jbang/bin/jbang /usr/local/bin/jbang \
 && jbang --version

RUN groupadd --gid "$CONTAINER_GID" "$CONTAINER_GROUP" \
 && useradd --uid "$CONTAINER_UID" --gid "$CONTAINER_GID" --create-home --shell /bin/bash "$CONTAINER_USER" \
 && install -d -m 0755 /data/Projects \
 && install -d -m 0755 /host \
 && install -d -m 0755 /nix \
 && install -d -m 1777 /tmp/ws-data \
 && ln -s /host/run/docker.sock /var/run/host-docker.sock \
 && install -d -m 0755 "/home/$CONTAINER_USER/.config/opencode" \
 && install -d -m 0755 "/home/$CONTAINER_USER/.m2" \
 && install -d -m 0755 "/home/$CONTAINER_USER/.local/share" \
 && install -d -m 0755 "/home/$CONTAINER_USER/.local/state/opencode" \
  && install -o "$CONTAINER_UID" -g "$CONTAINER_GID" -m 0600 /dev/null "/home/$CONTAINER_USER/.Xauthority" \
  && chown -R "$CONTAINER_UID:$CONTAINER_GID" /nix \
      "/home/$CONTAINER_USER/.config" \
      "/home/$CONTAINER_USER/.m2" \
      "/home/$CONTAINER_USER/.local" \
  && echo "$CONTAINER_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$CONTAINER_USER" \
  && chmod 0440 "/etc/sudoers.d/$CONTAINER_USER"

# Install Nix for the normal workspace user without enabling flakes or replacing
# the existing apt-managed toolchain yet.
RUN su - "$CONTAINER_USER" -c 'curl -L https://nixos.org/nix/install | sh -s -- --no-daemon --no-modify-profile'

# Make login shells pick up the single-user Nix profile and Neovim as well. The
# plain PATH env is not enough because login shells reset Debian's default PATH.
RUN printf '%s\n' \
      'if [ -e "/home/'"$CONTAINER_USER"'/.nix-profile/etc/profile.d/nix.sh" ]; then' \
      '  . "/home/'"$CONTAINER_USER"'/.nix-profile/etc/profile.d/nix.sh"' \
      'fi' \
      'PATH="/opt/nvim/bin:$PATH"' \
      'export PATH' \
      > /etc/profile.d/nix.sh

# Make workspace-owned devcontainer scripts directly callable in interactive
# shells. `DEVCONTAINER_WORKSPACE_FOLDER` is runtime state, so this cannot be a
# plain Dockerfile `ENV PATH=...` expansion.
RUN printf '%s\n' \
      'PATH="$DEVCONTAINER_WORKSPACE_FOLDER/.devcontainer/scripts:$PATH"' \
      'export PATH' \
      > /etc/profile.d/codegeist-workspace-scripts.sh

COPY .devcontainer/entrypoint.sh /usr/local/bin/devcontainer-entrypoint

RUN chmod +x /usr/local/bin/devcontainer-entrypoint

ENV USER=${CONTAINER_USER}
ENV HOME=/home/${CONTAINER_USER}
ENV NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV PATH=/home/${CONTAINER_USER}/.nix-profile/bin:/nix/var/nix/profiles/default/bin:${PATH}

VOLUME ["/var/lib/docker"]

ENTRYPOINT ["/usr/local/bin/devcontainer-entrypoint"]

USER ${CONTAINER_USER}
