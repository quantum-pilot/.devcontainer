FROM node:24

ARG USERNAME=node
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEVCONTAINER=true
ENV SHELL=/bin/zsh
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV TERM=xterm-256color
ENV COLORTERM=truecolor
ENV EDITOR=nano
ENV VISUAL=nano
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=/usr/local/share/npm-global/bin:/home/${USERNAME}/.local/bin:${PATH}
ENV GIT_CONFIG_GLOBAL=/home/${USERNAME}/.gitconfig
ENV NPM_CONFIG_UPDATE_NOTIFIER=false

RUN apt-get update && apt-get install -y --no-install-recommends \
  bash \
  build-essential \
  ca-certificates \
  curl \
  fzf \
  git \
  jq \
  less \
  nano \
  openssh-client \
  procps \
  python3 \
  python3-venv \
  ripgrep \
  tmux \
  unzip \
  vim \
  zsh \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

RUN npm install -g --omit=dev \
    @anthropic-ai/claude-code \
    @openai/codex \
    @dietrichgebert/ponytail \
    @opengsd/gsd-core \
    pnpm \
    @sentropic/graphify \
  && for bin in claude codex graphify gsd-core gsd-tools gsd_run pnpm; do \
    ln -sf "/usr/local/share/npm-global/bin/${bin}" "/usr/local/bin/${bin}"; \
  done \
  && npm cache clean --force

RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

RUN env \
    UV_TOOL_DIR=/opt/uv-tools \
    UV_TOOL_BIN_DIR=/usr/local/bin \
    uv tool install 'headroom-ai[proxy]'

ARG ENABLE_PLAYWRIGHT=false
RUN if [ "${ENABLE_PLAYWRIGHT}" = "true" ]; then \
    apt-get update && apt-get install -y --no-install-recommends \
      libnspr4 libnss3 libdbus-1-3 libatk1.0-0 libatk-bridge2.0-0 \
      libcups2 libxkbcommon0 libatspi2.0-0 libxcomposite1 libxdamage1 \
      libxfixes3 libxrandr2 libgbm1 libasound2 libx11-xcb1 libxcursor1 \
      libgtk-3-0 libgdk-pixbuf2.0-0 libgstreamer1.0-0 libgtk-4-1 \
      libgraphene-1.0-0 libwoff1 libvpx7 libopus0 \
      libgstreamer-plugins-base1.0-0 libgstreamer-plugins-bad1.0-0 \
      gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
      gstreamer1.0-plugins-bad gstreamer1.0-libav flite libavif15 \
      libharfbuzz-icu0 libenchant-2-2 libsecret-1-0 libhyphen0 \
      libmanette-0.2-0 libgles2 libx264-dev libxss1 libdrm2 \
      libglib2.0-0 libpango-1.0-0 libpangocairo-1.0-0 libcairo2 \
      libfreetype6 libfontconfig1 libwebp7 libwebpdemux2; \
    mkdir -p /home/${USERNAME}/.local/share/ms-playwright; \
    PLAYWRIGHT_BROWSERS_PATH=/home/${USERNAME}/.local/share/ms-playwright npx playwright install; \
    npm install -g @playwright/mcp@latest; \
    chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.local/share/ms-playwright; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
  fi

ARG ENABLE_PYTHON=false
ARG PYTHON_VERSION=3.12
RUN if [ "${ENABLE_PYTHON}" = "true" ]; then \
    env \
      UV_PYTHON_INSTALL_DIR=/opt/uv-python \
      UV_PYTHON_BIN_DIR=/usr/local/bin \
      UV_PYTHON_INSTALL_BIN=true \
      uv python install --default "${PYTHON_VERSION}"; \
  fi

ARG ENABLE_GO=false
ARG GO_VERSION=1.26.4
ARG GO_ARCH=amd64
RUN if [ "${ENABLE_GO}" = "true" ]; then \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" -o /tmp/go.tgz; \
    rm -rf /usr/local/go; \
    tar -C /usr/local -xzf /tmp/go.tgz; \
    rm /tmp/go.tgz; \
  fi

ARG ENABLE_RUST=false
ARG RUST_VERSION=stable
RUN if [ "${ENABLE_RUST}" = "true" ]; then \
    env RUSTUP_HOME=/usr/local/rustup CARGO_HOME=/usr/local/cargo \
      sh -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain ${RUST_VERSION} --profile minimal"; \
    env RUSTUP_HOME=/usr/local/rustup CARGO_HOME=/usr/local/cargo \
      /usr/local/cargo/bin/rustup component add rust-analyzer; \
    for bin in cargo cargo-clippy cargo-fmt clippy-driver rust-analyzer rustc rustdoc rustfmt rustup; do \
      if [ -x "/usr/local/cargo/bin/${bin}" ]; then \
        printf '%s\n' \
          '#!/usr/bin/env sh' \
          'export RUSTUP_HOME=/usr/local/rustup' \
          "exec /usr/local/cargo/bin/${bin} \"\$@\"" \
          > "/usr/local/bin/${bin}"; \
        chmod 0755 "/usr/local/bin/${bin}"; \
      fi; \
    done; \
  fi

RUN mkdir -p \
    /home/${USERNAME}/.agents \
    /home/${USERNAME}/.claude \
    /home/${USERNAME}/.claude-home \
    /home/${USERNAME}/.codex \
    /home/${USERNAME}/.config/git \
    /home/${USERNAME}/.gsd \
    /home/${USERNAME}/.local/bin \
    /home/${USERNAME}/.local/cache/uv \
    /home/${USERNAME}/.local/share/cargo/bin \
    /home/${USERNAME}/.local/share/go/bin \
    /home/${USERNAME}/.local/share/ms-playwright \
    /home/${USERNAME}/.local/share/pnpm \
    /home/${USERNAME}/.local/share/rustup \
    /home/${USERNAME}/.local/share/uv/python \
    /home/${USERNAME}/.local/share/uv/tools \
    /home/${USERNAME}/.local/tmp \
    /home/${USERNAME}/.npm \
    /home/${USERNAME}/.cache \
    /home/${USERNAME}/.vscode-server \
    /jail-requests \
    /shell_history \
    /workspace \
  && ln -sf /home/${USERNAME}/.claude-home/claude.json /home/${USERNAME}/.claude.json \
  && ln -sf /home/${USERNAME}/.claude-home/claude.json.backup /home/${USERNAME}/.claude.json.backup \
  && touch /shell_history/.bash_history \
  && touch /shell_history/.zsh_history \
  && printf '%s\n' \
    'export HISTFILE=/shell_history/.zsh_history' \
    'export SAVEHIST=1000000000' \
    'export HISTSIZE=1000000000' \
    'export LANG=C.UTF-8' \
    'export LC_ALL=C.UTF-8' \
    'export TERM="${TERM:-xterm-256color}"' \
    'export COLORTERM="${COLORTERM:-truecolor}"' \
    'export HEADROOM_HOST=127.0.0.1' \
    'export HEADROOM_PORT=8787' \
    'export JAIL_HEADROOM_TMUX_SESSION="${JAIL_HEADROOM_TMUX_SESSION:-headroom}"' \
    'export JAIL_MANAGED_TMUX_SESSIONS="${JAIL_MANAGED_TMUX_SESSIONS:-$JAIL_HEADROOM_TMUX_SESSION}"' \
    'export NPM_CONFIG_PREFIX="${NPM_CONFIG_PREFIX:-$HOME/.local}"' \
    'export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"' \
    'export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-$HOME/.local/share/ms-playwright}"' \
    'export UV_CACHE_DIR="${UV_CACHE_DIR:-$HOME/.local/cache/uv}"' \
    'export UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-$HOME/.local/share/uv/python}"' \
    'export UV_PYTHON_BIN_DIR="${UV_PYTHON_BIN_DIR:-$HOME/.local/bin}"' \
    'export UV_PYTHON_INSTALL_BIN="${UV_PYTHON_INSTALL_BIN:-true}"' \
    'export UV_TOOL_DIR="${UV_TOOL_DIR:-$HOME/.local/share/uv/tools}"' \
    'export UV_TOOL_BIN_DIR="${UV_TOOL_BIN_DIR:-$HOME/.local/bin}"' \
    'export GOPATH="${GOPATH:-$HOME/.local/share/go}"' \
    'export CARGO_HOME="${CARGO_HOME:-$HOME/.local/share/cargo}"' \
    'export RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.local/share/rustup}"' \
    'export TMPDIR="${TMPDIR:-$HOME/.local/tmp}"' \
    'export PATH="$NPM_CONFIG_PREFIX/bin:$PNPM_HOME:$PNPM_HOME/bin:$GOPATH/bin:$CARGO_HOME/bin:$HOME/.local/bin:/usr/local/go/bin:$PATH"' \
    'export ANTHROPIC_BASE_URL="http://${HEADROOM_HOST}:${HEADROOM_PORT}"' \
    'export OPENAI_BASE_URL="http://${HEADROOM_HOST}:${HEADROOM_PORT}/v1"' \
    'export GIT_SSH=/usr/local/bin/ssh' \
    'alias headroom-attach="tmux attach -t =$JAIL_HEADROOM_TMUX_SESSION"' \
    'bindkey -e' \
    'bindkey "^[[1;5D" backward-word' \
    'bindkey "^[[1;5C" forward-word' \
    'bindkey "^[[5D" backward-word' \
    'bindkey "^[[5C" forward-word' \
    'bindkey "^[b" backward-word' \
    'bindkey "^[f" forward-word' \
    'bindkey "^[[H" beginning-of-line' \
    'bindkey "^[[F" end-of-line' \
    'bindkey "^[[1~" beginning-of-line' \
    'bindkey "^[[4~" end-of-line' \
    'bindkey "^[[3~" delete-char' \
    'setopt appendhistory sharehistory histignoredups' \
    'PROMPT="%n@jail:%~$ "' \
    > /home/${USERNAME}/.zshrc \
  && printf '%s\n' \
    'export HISTFILE=/shell_history/.bash_history' \
    'export HISTSIZE=' \
    'export HISTFILESIZE=' \
    'export LANG=C.UTF-8' \
    'export LC_ALL=C.UTF-8' \
    'export TERM="${TERM:-xterm-256color}"' \
    'export COLORTERM="${COLORTERM:-truecolor}"' \
    'export HEADROOM_HOST=127.0.0.1' \
    'export HEADROOM_PORT=8787' \
    'export JAIL_HEADROOM_TMUX_SESSION="${JAIL_HEADROOM_TMUX_SESSION:-headroom}"' \
    'export JAIL_MANAGED_TMUX_SESSIONS="${JAIL_MANAGED_TMUX_SESSIONS:-$JAIL_HEADROOM_TMUX_SESSION}"' \
    'export NPM_CONFIG_PREFIX="${NPM_CONFIG_PREFIX:-$HOME/.local}"' \
    'export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"' \
    'export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-$HOME/.local/share/ms-playwright}"' \
    'export UV_CACHE_DIR="${UV_CACHE_DIR:-$HOME/.local/cache/uv}"' \
    'export UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-$HOME/.local/share/uv/python}"' \
    'export UV_PYTHON_BIN_DIR="${UV_PYTHON_BIN_DIR:-$HOME/.local/bin}"' \
    'export UV_PYTHON_INSTALL_BIN="${UV_PYTHON_INSTALL_BIN:-true}"' \
    'export UV_TOOL_DIR="${UV_TOOL_DIR:-$HOME/.local/share/uv/tools}"' \
    'export UV_TOOL_BIN_DIR="${UV_TOOL_BIN_DIR:-$HOME/.local/bin}"' \
    'export GOPATH="${GOPATH:-$HOME/.local/share/go}"' \
    'export CARGO_HOME="${CARGO_HOME:-$HOME/.local/share/cargo}"' \
    'export RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.local/share/rustup}"' \
    'export TMPDIR="${TMPDIR:-$HOME/.local/tmp}"' \
    'export PATH="$NPM_CONFIG_PREFIX/bin:$PNPM_HOME:$PNPM_HOME/bin:$GOPATH/bin:$CARGO_HOME/bin:$HOME/.local/bin:/usr/local/go/bin:$PATH"' \
    'export ANTHROPIC_BASE_URL="http://${HEADROOM_HOST}:${HEADROOM_PORT}"' \
    'export OPENAI_BASE_URL="http://${HEADROOM_HOST}:${HEADROOM_PORT}/v1"' \
    'export GIT_SSH=/usr/local/bin/ssh' \
    'alias headroom-attach="tmux attach -t =$JAIL_HEADROOM_TMUX_SESSION"' \
    'PS1="\u@jail:\w$ "' \
    > /home/${USERNAME}/.bashrc \
  && printf '%s\n' \
    'set editing-mode emacs' \
    '"\e[1;5D": backward-word' \
    '"\e[1;5C": forward-word' \
    '"\e[5D": backward-word' \
    '"\e[5C": forward-word' \
    '"\eb": backward-word' \
    '"\ef": forward-word' \
    '"\e[H": beginning-of-line' \
    '"\e[F": end-of-line' \
    '"\e[1~": beginning-of-line' \
    '"\e[4~": end-of-line' \
    '"\e[3~": delete-char' \
    > /home/${USERNAME}/.inputrc \
  && chown -R ${USERNAME}:${USERNAME} \
    /home/${USERNAME} \
    /jail-requests \
    /shell_history \
    /workspace

COPY scripts/jailctl /usr/local/bin/jailctl
COPY scripts/ssh /usr/local/bin/ssh
COPY scripts/headroom-proxy /usr/local/bin/headroom-proxy
COPY scripts/jail-start /usr/local/bin/jail-start
COPY scripts/jail-hardening-check /usr/local/bin/jail-hardening-check
COPY scripts/jail-tmux /usr/local/bin/jail-tmux
RUN chmod 0755 \
  /usr/local/bin/jailctl \
  /usr/local/bin/ssh \
  /usr/local/bin/headroom-proxy \
  /usr/local/bin/jail-start \
  /usr/local/bin/jail-hardening-check \
  /usr/local/bin/jail-tmux

RUN set -eux; \
  if [ -x /usr/bin/ssh ] && [ ! -e /usr/bin/ssh.real ]; then \
    mv /usr/bin/ssh /usr/bin/ssh.real; \
    chmod 000 /usr/bin/ssh.real; \
    ln -s /usr/local/bin/ssh /usr/bin/ssh; \
  fi

RUN set -eux; \
  rm -rf \
    /home/${USERNAME}/.ssh \
    /home/${USERNAME}/.gnupg; \
  find / -xdev -perm /6000 -type f -exec chmod a-s {} + 2>/dev/null || true; \
  command -v setcap >/dev/null 2>&1 && getcap -r / 2>/dev/null | cut -d= -f1 | xargs -r setcap -r || true; \
  rm -f /etc/sudoers.d/${USERNAME}; \
  if command -v sudo >/dev/null 2>&1; then chmod 0755 "$(command -v sudo)" || true; fi; \
  passwd -l root || true

ENV HTTP_PROXY=http://egress-proxy:8080
ENV HTTPS_PROXY=http://egress-proxy:8080
ENV ALL_PROXY=http://egress-proxy:8080
ENV NO_PROXY=localhost,127.0.0.1,::1,egress-proxy,ssh-broker-proxy
ENV npm_config_proxy=http://egress-proxy:8080
ENV npm_config_https_proxy=http://egress-proxy:8080
ENV NPM_CONFIG_PREFIX=/home/${USERNAME}/.local
ENV PNPM_HOME=/home/${USERNAME}/.local/share/pnpm
ENV PLAYWRIGHT_BROWSERS_PATH=/home/${USERNAME}/.local/share/ms-playwright
ENV UV_CACHE_DIR=/home/${USERNAME}/.local/cache/uv
ENV UV_PYTHON_INSTALL_DIR=/home/${USERNAME}/.local/share/uv/python
ENV UV_PYTHON_BIN_DIR=/home/${USERNAME}/.local/bin
ENV UV_PYTHON_INSTALL_BIN=true
ENV UV_TOOL_DIR=/home/${USERNAME}/.local/share/uv/tools
ENV UV_TOOL_BIN_DIR=/home/${USERNAME}/.local/bin
ENV GOPATH=/home/${USERNAME}/.local/share/go
ENV CARGO_HOME=/home/${USERNAME}/.local/share/cargo
ENV RUSTUP_HOME=/home/${USERNAME}/.local/share/rustup
ENV TMPDIR=/home/${USERNAME}/.local/tmp
ENV PATH=/home/${USERNAME}/.local/bin:/home/${USERNAME}/.local/share/pnpm:/home/${USERNAME}/.local/share/pnpm/bin:/home/${USERNAME}/.local/share/go/bin:/home/${USERNAME}/.local/share/cargo/bin:/usr/local/go/bin:${PATH}
ENV GIT_SSH=/usr/local/bin/ssh
ENV JAIL_SSH_BROKER_HOST=ssh-broker-proxy
ENV JAIL_SSH_BROKER_PORT=8822
ENV JAIL_SSH_BROKER_TOKEN_FILE=/jail-ssh-broker-token

USER ${USERNAME}

RUN printf '%s\n' \
    'CLAUDE.md' \
    '.claude' \
    '.codex' \
    'AGENTS.md' \
    >> /home/${USERNAME}/.config/git/ignore

WORKDIR /workspace

CMD ["jail-start"]
