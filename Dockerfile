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

RUN curl -fsSL https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh

RUN env \
    UV_TOOL_DIR=/opt/uv-tools \
    UV_TOOL_BIN_DIR=/usr/local/bin \
    uv tool install 'headroom-ai[proxy]'

RUN git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git /usr/local/share/oh-my-zsh

RUN mkdir -p \
    /home/${USERNAME}/.agents \
    /home/${USERNAME}/.claude \
    /home/${USERNAME}/.claude-home \
    /home/${USERNAME}/.codex \
    /home/${USERNAME}/.config/git \
    /home/${USERNAME}/.local/config/git \
    /home/${USERNAME}/.gsd \
    /home/${USERNAME}/.local/bin \
    /home/${USERNAME}/.local/cache/zsh \
    /home/${USERNAME}/.local/config \
    /home/${USERNAME}/.local/config/shell \
    /home/${USERNAME}/.local/cache/mise \
    /home/${USERNAME}/.local/cache/uv \
    /home/${USERNAME}/.local/state/mise \
    /home/${USERNAME}/.local/share/cargo/bin \
    /home/${USERNAME}/.local/share/gnupg \
    /home/${USERNAME}/.local/share/go/bin \
    /home/${USERNAME}/.local/share/headroom \
    /home/${USERNAME}/.local/share/mise \
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
  && ln -sf /home/${USERNAME}/.local/config/shell/zshrc /home/${USERNAME}/.zshrc.local \
  && ln -sfn /home/${USERNAME}/.local/share/headroom /home/${USERNAME}/.headroom \
  && touch /shell_history/.zsh_history \
  && printf '%s\n' 'set -g mouse on' > /home/${USERNAME}/.tmux.conf \
  && printf '%s\n' \
    'export HISTFILE=/shell_history/.zsh_history' \
    'export SAVEHIST=1000000000' \
    'export HISTSIZE=1000000000' \
    'export LANG=C.UTF-8' \
    'export LC_ALL=C.UTF-8' \
    'export TERM="${TERM:-xterm-256color}"' \
    'export COLORTERM="${COLORTERM:-truecolor}"' \
    'export ZSH_COMPDUMP="${ZSH_COMPDUMP:-$HOME/.local/cache/zsh/.zcompdump}"' \
    'export HEADROOM_HOST=127.0.0.1' \
    'export HEADROOM_PORT=8787' \
    'export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.local/config}"' \
    'export GNUPGHOME="${GNUPGHOME:-$HOME/.local/share/gnupg}"' \
    'export JAIL_HEADROOM_TMUX_SESSION="${JAIL_HEADROOM_TMUX_SESSION:-headroom}"' \
    'export JAIL_MANAGED_TMUX_SESSIONS="${JAIL_MANAGED_TMUX_SESSIONS:-$JAIL_HEADROOM_TMUX_SESSION}"' \
    'export MISE_DATA_DIR="${MISE_DATA_DIR:-$HOME/.local/share/mise}"' \
    'export MISE_CONFIG_DIR="${MISE_CONFIG_DIR:-$HOME/.local/share/mise/config}"' \
    'export MISE_CACHE_DIR="${MISE_CACHE_DIR:-$HOME/.local/cache/mise}"' \
    'export MISE_STATE_DIR="${MISE_STATE_DIR:-$HOME/.local/state/mise}"' \
    'export NPM_CONFIG_PREFIX="${NPM_CONFIG_PREFIX:-$HOME/.local}"' \
    'export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"' \
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
    'export PATH="$MISE_DATA_DIR/shims:$NPM_CONFIG_PREFIX/bin:$PNPM_HOME:$PNPM_HOME/bin:$GOPATH/bin:$CARGO_HOME/bin:$HOME/.local/bin:$PATH"' \
    'export ANTHROPIC_BASE_URL="http://${HEADROOM_HOST}:${HEADROOM_PORT}"' \
    'export OPENAI_BASE_URL="http://${HEADROOM_HOST}:${HEADROOM_PORT}/v1"' \
    'export GIT_SSH=/usr/local/bin/ssh' \
    'export ZSH=/usr/local/share/oh-my-zsh' \
    'export ZSH_DISABLE_COMPFIX=true' \
    'export DISABLE_AUTO_UPDATE=true' \
    'ZSH_THEME=""' \
    'plugins=(git)' \
    'source "$ZSH/oh-my-zsh.sh"' \
    'alias m="mise"' \
    'eval "$(mise activate zsh)"' \
    'if [[ -r "$HOME/.zshrc.local" ]]; then source "$HOME/.zshrc.local"; fi' \
    'mkdir -p "$(dirname "$ZSH_COMPDUMP")" 2>/dev/null || true' \
    'autoload -Uz compinit vcs_info' \
    'compinit -d "$ZSH_COMPDUMP"' \
    "zstyle ':vcs_info:git:*' formats ' (%b)'" \
    'precmd_functions+=(vcs_info)' \
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
    'PROMPT="%n@jail:%~${vcs_info_msg_0_}$ "' \
    > /home/${USERNAME}/.zshrc \
  && chmod 700 /home/${USERNAME}/.local/share/gnupg \
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

ENV HTTP_PROXY=http://proxy:8080
ENV HTTPS_PROXY=http://proxy:8080
ENV ALL_PROXY=http://proxy:8080
ENV NO_PROXY=localhost,127.0.0.1,::1,proxy
ENV npm_config_proxy=http://proxy:8080
ENV npm_config_https_proxy=http://proxy:8080
ENV NPM_CONFIG_PREFIX=/home/${USERNAME}/.local
ENV PNPM_HOME=/home/${USERNAME}/.local/share/pnpm
ENV XDG_CONFIG_HOME=/home/${USERNAME}/.local/config
ENV GIT_CONFIG_GLOBAL=/home/${USERNAME}/.local/config/git/config
ENV GNUPGHOME=/home/${USERNAME}/.local/share/gnupg
ENV UV_CACHE_DIR=/home/${USERNAME}/.local/cache/uv
ENV UV_PYTHON_INSTALL_DIR=/home/${USERNAME}/.local/share/uv/python
ENV UV_PYTHON_BIN_DIR=/home/${USERNAME}/.local/bin
ENV UV_PYTHON_INSTALL_BIN=true
ENV UV_TOOL_DIR=/home/${USERNAME}/.local/share/uv/tools
ENV UV_TOOL_BIN_DIR=/home/${USERNAME}/.local/bin
ENV MISE_DATA_DIR=/home/${USERNAME}/.local/share/mise
ENV MISE_CONFIG_DIR=/home/${USERNAME}/.local/share/mise/config
ENV MISE_CACHE_DIR=/home/${USERNAME}/.local/cache/mise
ENV MISE_STATE_DIR=/home/${USERNAME}/.local/state/mise
ENV GOPATH=/home/${USERNAME}/.local/share/go
ENV CARGO_HOME=/home/${USERNAME}/.local/share/cargo
ENV RUSTUP_HOME=/home/${USERNAME}/.local/share/rustup
ENV TMPDIR=/home/${USERNAME}/.local/tmp
ENV PATH=/home/${USERNAME}/.local/share/mise/shims:/home/${USERNAME}/.local/bin:/home/${USERNAME}/.local/share/pnpm:/home/${USERNAME}/.local/share/pnpm/bin:/home/${USERNAME}/.local/share/go/bin:/home/${USERNAME}/.local/share/cargo/bin:${PATH}
ENV GIT_SSH=/usr/local/bin/ssh
ENV JAIL_SSH_BROKER_HOST=proxy
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
