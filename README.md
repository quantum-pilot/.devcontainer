# `.devcontainer` for <s>LLM</s> vibe coding

This is a modular devcontainer configuration that can be customized for different projects and technology stacks for vibe coding. This is an environment to reduce the attack surface of your host system through prompt injection attacks. This way, you don't have to setup Claude Code or Codex locally in your system.

Inspiration from [Claude Code](https://github.com/anthropics/claude-code/blob/main/.devcontainer/).

## Quick Start

1. Clone into your project workspace: `git clone https://github.com/quantum-pilot/.devcontainer` and remove `.git` directory or download the zip file directly and unzip.

2. If checking this out into your repository is not desirable, add it to `.gitignore`.

3. Enable the languages you need by editing `devcontainer.json`:
   ```json
   "args": {
     "ENABLE_GO": "true",
     "ENABLE_RUST": "true",
     "ENABLE_PYTHON": "false",
     ...
   }
   ```

4. Open in VS Code to rebuild and run the container
5. Vibe code your life away!

> All scripts from `.devcontainer/scripts/` are copied to `/usr/local/bin/` inside the container and _can_ be executed in root with `sudo`.

### Network Restrictions

This also includes a firewall script that limits container network access to specified networks and domains. It's enforced by default and exists in `scripts/network-restrictions.sh`, but can be removed from `postCreateCommand` in `devcontainer.json`.

The firewall is configurable via `config/allowed-networks.json`:
- `allowed_domains`: List of domains to allow access to
- `allowed_networks`: List of CIDR ranges to allow
- Various allow flags for DNS, SSH, localhost, etc.
