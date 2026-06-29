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
ENV PNPM_HOME=/home/${USERNAME}/.local/share/pnpm
ENV UV_CACHE_DIR=/home/${USERNAME}/.cache/uv
ENV PATH=/usr/local/share/npm-global/bin:/home/${USERNAME}/.local/share/pnpm:/home/${USERNAME}/.local/bin:${PATH}
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
  pipx \
  procps \
  python3 \
  python3-pip \
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

RUN python3 -m venv /opt/uv \
  && /opt/uv/bin/pip install --no-cache-dir --upgrade pip \
  && /opt/uv/bin/pip install --no-cache-dir uv \
  && ln -sf /opt/uv/bin/uv /usr/local/bin/uv \
  && ln -sf /opt/uv/bin/uvx /usr/local/bin/uvx

RUN python3 -m venv /opt/headroom \
  && /opt/headroom/bin/pip install --no-cache-dir --upgrade pip \
  && /opt/headroom/bin/pip install --no-cache-dir 'headroom-ai[proxy]' \
  && ln -sf /opt/headroom/bin/headroom /usr/local/bin/headroom

RUN mkdir -p \
    /home/${USERNAME}/.agents \
    /home/${USERNAME}/.claude \
    /home/${USERNAME}/.codex \
    /home/${USERNAME}/.config/git \
    /home/${USERNAME}/.gsd \
    /home/${USERNAME}/.local/share/pnpm \
    /home/${USERNAME}/.local/share/headroom \
    /home/${USERNAME}/.local/bin \
    /home/${USERNAME}/.npm \
    /home/${USERNAME}/.cache \
    /home/${USERNAME}/.vscode-server \
    /jail-requests \
    /shell_history \
    /usr/local/share/npm-global \
    /workspace \
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
    'export ANTHROPIC_BASE_URL="http://${HEADROOM_HOST}:${HEADROOM_PORT}"' \
    'export OPENAI_BASE_URL="http://${HEADROOM_HOST}:${HEADROOM_PORT}/v1"' \
    'alias headroom-attach="tmux attach -t headroom"' \
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
    'export ANTHROPIC_BASE_URL="http://${HEADROOM_HOST}:${HEADROOM_PORT}"' \
    'export OPENAI_BASE_URL="http://${HEADROOM_HOST}:${HEADROOM_PORT}/v1"' \
    'alias headroom-attach="tmux attach -t headroom"' \
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
RUN chmod 0755 \
  /usr/local/bin/jailctl \
  /usr/local/bin/ssh \
  /usr/local/bin/headroom-proxy \
  /usr/local/bin/jail-start \
  /usr/local/bin/jail-hardening-check

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
ENV NO_PROXY=localhost,127.0.0.1,::1,egress-proxy
ENV npm_config_proxy=http://egress-proxy:8080
ENV npm_config_https_proxy=http://egress-proxy:8080

USER ${USERNAME}

RUN git config --global url."git-broker://".insteadOf "git@broker:" \
  && printf '%s\n' \
    'CLAUDE.md' \
    '.claude' \
    '.codex' \
    'AGENTS.md' \
    >> /home/${USERNAME}/.config/git/ignore

WORKDIR /workspace

CMD ["jail-start"]
