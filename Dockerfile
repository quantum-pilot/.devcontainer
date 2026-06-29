FROM node:24

ARG USERNAME=node
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEVCONTAINER=true
ENV SHELL=/bin/zsh
ENV EDITOR=nano
ENV VISUAL=nano
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=/usr/local/share/npm-global/bin:/home/${USERNAME}/.local/bin:${PATH}
ENV HTTP_PROXY=http://egress-proxy:8080
ENV HTTPS_PROXY=http://egress-proxy:8080
ENV ALL_PROXY=http://egress-proxy:8080
ENV NO_PROXY=localhost,127.0.0.1,::1,egress-proxy
ENV npm_config_proxy=http://egress-proxy:8080
ENV npm_config_https_proxy=http://egress-proxy:8080
ENV GIT_CONFIG_GLOBAL=/home/${USERNAME}/.gitconfig

RUN apt-get update && apt-get install -y --no-install-recommends \
  bash \
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
  tmux \
  unzip \
  vim \
  zsh \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir -p \
    /home/${USERNAME}/.config/git \
    /home/${USERNAME}/.local/bin \
    /home/${USERNAME}/.npm \
    /home/${USERNAME}/.cache \
    /home/${USERNAME}/.vscode-server \
    /jail-requests \
    /shell_history \
    /usr/local/share/npm-global \
    /workspace \
  && touch /shell_history/.bash_history \
  && chown -R ${USERNAME}:${USERNAME} \
    /home/${USERNAME} \
    /jail-requests \
    /shell_history \
    /usr/local/share/npm-global \
    /workspace

COPY scripts/jailctl /usr/local/bin/jailctl
COPY scripts/ssh /usr/local/bin/ssh
COPY scripts/jail-hardening-check /usr/local/bin/jail-hardening-check
RUN chmod 0755 /usr/local/bin/jailctl /usr/local/bin/ssh /usr/local/bin/jail-hardening-check

RUN set -eux; \
  rm -rf \
    /home/${USERNAME}/.ssh \
    /home/${USERNAME}/.gnupg \
    /home/${USERNAME}/.claude \
    /home/${USERNAME}/.codex; \
  find / -xdev -perm /6000 -type f -exec chmod a-s {} + 2>/dev/null || true; \
  command -v setcap >/dev/null 2>&1 && getcap -r / 2>/dev/null | cut -d= -f1 | xargs -r setcap -r || true; \
  rm -f /etc/sudoers.d/${USERNAME}; \
  if command -v sudo >/dev/null 2>&1; then chmod 0755 "$(command -v sudo)" || true; fi; \
  passwd -l root || true

USER ${USERNAME}

RUN git config --global url."git-broker://".insteadOf "git@broker:" \
  && printf '%s\n' \
    'CLAUDE.md' \
    '.claude' \
    '.codex' \
    'AGENTS.md' \
    >> /home/${USERNAME}/.config/git/ignore

WORKDIR /workspace

CMD ["sleep", "infinity"]
