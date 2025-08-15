# `.devcontainer` for <s>LLM</s> vibe coding

A devcontainer configuration that can be customized for different projects and technology stacks to facilitate _vibe coding_. It's mainly an environment to reduce the attack surface of your host system through prompt injection attacks. This way, you don't have to setup Claude Code or Codex locally in your system, but rather mount your project into a container and let the LLMs cause havoc after.

Inspiration from [Claude Code](https://github.com/anthropics/claude-code/blob/main/.devcontainer/). Pull Requests are welcome.

## Quick Start

1. Clone into your project workspace: `git clone https://github.com/quantum-pilot/.devcontainer` and remove `.git` directory (you can also download the zip file directly and unzip). If checking this into your repository is not desirable, add it to `.gitignore`.

2. Enable the languages you need by editing `devcontainer.json`:
   ```jsonc
   "args": {
     "ENABLE_GO": "true",
     "ENABLE_RUST": "false",
     "ENABLE_PYTHON": "false",
     // for full config, check devcontainer.json
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
- Various allow flags for DNS, SSH, localhost, Docker, etc.

> Host network access through Docker gateway is enabled by default (see example below)

### Playwright MCP (Host container access)

Playwright offers a great MCP server - enabling LLMs to use browsers for human-like navigation and interaction. You may want to be able to use some specific browser profile or rather, you just want to be able to see what an LLM is doing with a browser _visually_ in your machine.

For that, you'll need additional steps:
1. `ENABLE_PLAYWRIGHT_MCP=true` in build args - this adds dependencies and ensures playwright is installed
2. Uncomment `initializeCommand` with `.devcontainer/host-start-chrome.sh` in `devcontainer.json` - this either starts a Chrome browser in host machine with a local profile or reuses it if it's open
3. Uncomment `forwardPorts` with `9222` (if you modify this, then make sure to change `host-start-chrome.sh` as well) - this forwards port to the container for MCP server
4. Ensure you prefix your command with `container-mcp-wrapper` like below in your MCP configuration file and specify `http://___GW_IP___:9222` for CDP endpoint - this substitutes the variable with Docker's gateway IP so that it communicates with your host Chrome browser instance (since `container-mcp-wrapper` is in `scripts/`, it is already part of `/usr/local/bin/` and in `$PATH`).

```json
{
  "mcpServers": {
    "playwright": {
      "type": "stdio",
      "command": "container-mcp-wrapper",
      "args": [
        "npx", "@playwright/mcp@latest",
        "--cdp-endpoint", "http://___GW_IP___:9222"
      ]
    }
  }
}
```
