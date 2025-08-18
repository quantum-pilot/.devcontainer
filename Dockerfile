# Always use Node as base image
FROM node:24

ARG TARGETARCH
# Least likely to change - system setup
ARG USERNAME=node
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Set DEVCONTAINER environment variable
ENV DEVCONTAINER=true

# Install basic development tools
RUN apt-get update && apt-get install -y --no-install-recommends \
  aggregate \
  build-essential \
  ca-certificates \
  curl \
  dnsutils \
  fzf \
  gh \
  git \
  gnupg2 \
  iproute2 \
  ipset \
  iptables \
  jq \
  less \
  man-db \
  nano \
  pkg-config \
  procps \
  sudo \
  unzip \
  vim \
  yq \
  zsh

# Enable cross-compilation for arm64 (some go deps have issues)
RUN set -eux; \
    if [ "$TARGETARCH" = "arm64" ]; then \
      dpkg --add-architecture amd64; \
      apt-get install -y --no-install-recommends \
        gcc-x86-64-linux-gnu libc6-dev-amd64-cross; \
    fi

# Additional dependencies for playwright MCP server
ARG ENABLE_PLAYWRIGHT_MCP=false
RUN if [ "${ENABLE_PLAYWRIGHT_MCP}" = "true" ]; then \
    apt-get install -y --no-install-recommends libnspr4 libnss3 libdbus-1-3 libatk1.0-0 \
    libatk-bridge2.0-0 libcups2 libxkbcommon0 libatspi2.0-0 \
    libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libgbm1 libasound2 \
    libx11-xcb1 libxcursor1 libgtk-3-0 libgdk-pixbuf2.0-0 \
    libgstreamer1.0-0 libgtk-4-1 libgraphene-1.0-0 libwoff1 \
    libvpx7 libopus0 libgstreamer-plugins-base1.0-0 \
    libgstreamer-plugins-bad1.0-0 gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
    gstreamer1.0-libav flite libavif15 libharfbuzz-icu0 \
    libenchant-2-2 libsecret-1-0 libhyphen0 libmanette-0.2-0 \
    libgles2 libx264-dev libxss1 libdrm2 libglib2.0-0 \
    libpango-1.0-0 libpangocairo-1.0-0 libcairo2 \
    libfreetype6 libfontconfig1 libwebp7 libwebpdemux2; \
  fi

RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# Configure sudoers for the user (node user already exists in base image)
RUN echo ${USERNAME} ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/${USERNAME} && \
    chmod 0440 /etc/sudoers.d/${USERNAME}

# Set up directories, permissions and mount history
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R ${USERNAME}:${USERNAME} /usr/local/share && \
  mkdir -p /workspace && chown -R ${USERNAME}:${USERNAME} /workspace && \
  mkdir -p /home/${USERNAME}/.claude /home/${USERNAME}/.codex && \
  chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.claude /home/${USERNAME}/.codex && \
  mkdir /shell_history && touch /shell_history/.bash_history && \
  chown -R ${USERNAME}:${USERNAME} /shell_history

ARG TZ=UTC
ENV TZ="$TZ"

# Install git-delta (used by claude)
ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
  curl -L -o "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" \
    "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# Set shell environment
ENV SHELL=/bin/zsh
ENV EDITOR=nano
ENV VISUAL=nano
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin

WORKDIR /workspace

# Switch to user for installations
USER ${USERNAME}

RUN HISTORY="export PROMPT_COMMAND='history -a' && export HISTFILE=/shell_history/.bash_history"

# This only adds to your user config - you can always force add these files with `git add -f`
RUN mkdir -p ~/.config/git && \
  echo 'CLAUDE.md' >> ~/.config/git/ignore && \
  echo '.claude' >> ~/.config/git/ignore && \
  echo '.devcontainer' >> ~/.config/git/ignore && \
  echo 'AGENTS.md' >>  ~/.config/git/ignore

# zsh customizations
ARG ZSH_IN_DOCKER_VERSION=1.2.0
RUN sh -c "$(curl -fsSL https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \
  -p fzf \
  -t minimal \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/shell_history/.bash_history" \
  -x

USER root

# Install Go if enabled
ARG ENABLE_GO=false
ARG GO_VERSION=1.25.0
ARG GO_ARCH=amd64
ENV GOROOT=/usr/local/go
ENV GOPATH=/home/${USERNAME}/go
ENV PATH=$PATH:$GOROOT/bin:$GOPATH/bin

RUN if [ "${ENABLE_GO}" = "true" ]; then \
    echo "Installing Go ${GO_VERSION}..." && \
    curl -L -o /tmp/go.tgz "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" && \
    rm -rf /usr/local/go && \
    tar -C /usr/local -xzf /tmp/go.tgz && \
    rm /tmp/go.tgz && \
    mkdir -p /home/${USERNAME}/go/{bin,pkg,src} && \
    chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/go; \
  fi

# Install uv regardless
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

# Install Python if enabled
ARG ENABLE_PYTHON=false
ARG PYTHON_VERSION=3.11
ENV PATH=/home/${USERNAME}/.local/bin:$PATH
RUN echo "${ENABLE_PYTHON}" "${ENABLE_RUST}" && sleep 5

RUN if [ "${ENABLE_PYTHON}" = "true" ]; then \
    echo "Installing Python ${PYTHON_VERSION}..." && \
    UV_INSTALL_DIR=/usr/local/bin uv python install --default ${PYTHON_VERSION}; \
  fi

# Install Rust if enabled
ARG ENABLE_RUST=false
ARG RUST_VERSION=stable
ENV RUSTUP_HOME=/usr/local/rustup
ENV CARGO_HOME=/usr/local/cargo
ENV PATH=${CARGO_HOME}/bin:$PATH

RUN if [ "${ENABLE_RUST}" = "true" ]; then \
    echo "Installing Rust ${RUST_VERSION}..." && \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain ${RUST_VERSION} && \
    rustup component add rust-analyzer; \
  fi

USER ${USERNAME}

RUN if [ "${ENABLE_PYTHON}" = "true" ] && command -v pip3 >/dev/null 2>&1; then \
    echo "Installing Python tools..." && \
    pip3 install --user --upgrade pip setuptools wheel && \
    pip3 install --user virtualenv; \
  fi

# Claude Code installation
ARG CLAUDE_CODE_VERSION=latest
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}
ARG OPENAI_CODEX_VERSION=latest
RUN npm install -g @openai/codex@${OPENAI_CODEX_VERSION}

# Install claude-monitor
RUN uv tool install claude-monitor

# Install playwright if enabled
RUN if [ "${ENABLE_PLAYWRIGHT_MCP}" = "true" ]; then \
    npm i -g @playwright/mcp@latest && \
    npx playwright install; \
fi

USER root
COPY scripts/* /usr/local/bin/
RUN chmod +x /usr/local/bin/*

USER ${USERNAME}
