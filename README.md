# Hardened LLM Devcontainer

A safe-by-default `.devcontainer` setup for AI-assisted development. Copy this
directory into a project, open the project in VS Code, and build the
devcontainer from the Dev Containers UI.

For implementation details, see [DESIGN.md](DESIGN.md).

## Setup

Prerequisites:

- Docker Desktop, OrbStack, or another Docker engine with Compose support
- VS Code
- VS Code Dev Containers extension

Install:

1. Copy this directory as `.devcontainer` into the target project.
2. Open the project folder in VS Code.
3. Run `Dev Containers: Reopen in Container`.
4. VS Code runs `.devcontainer/host/jail-init` automatically and builds the services.
5. After the container opens, `jail-hardening-check` runs.

Host-owned jail state lives outside the project at:

```text
$HOME/.devcontainer-jail
```

Set `DEVCONTAINER_JAIL_HOME` before launching VS Code if you want that state in
a different location.

## Verify

Inside the worker:

```bash
jail-hardening-check
```

Expected result: every check prints `OK`.

To test egress approval:

```bash
curl -I https://example.com
```

Before approval, this creates a pending request and holds the client connection.

## Operator

Run the host operator from the project root:

```bash
.devcontainer/host/jail-operator
```

Use it to approve, deny, revoke, change TTLs, inspect active SSH leases, manage
the blacklist, and run the host SSH broker. It live-refreshes pending requests.

Pending requests support approve, deny, and forever-deny. Active approvals can
be revoked or moved between finite TTLs and `forever`. Active SSH leases appear
in the `leases` view with their TTLs and can be revoked there. Recent brokered
SSH sessions appear in the `sessions` view.

## Network Access

Proxy-aware network requests are default-deny. Unknown HTTP/HTTPS targets create
or update one pending request per target. If approved before the client times
out, the original request continues.

For package-manager work, run the install through `jailctl`:

```bash
jailctl install --run pnpm install --frozen-lockfile
jailctl install --run uv sync
jailctl install --run npm ci
jailctl install --run uv pip install -r requirements.txt
```

`pnpm`, `uv`/`uvx`, Python venv support, Claude Code, Codex CLI, Graphify, GSD
Core, Headroom, and Ponytail are installed in the worker image.

Node/JavaScript tooling is enabled by default. `pnpm` and `uv` are the preferred
package managers. Python, Go, Rust, and Playwright can be preinstalled at build
time by editing `customizations.jail.buildArgs` in `.devcontainer/devcontainer.json`
and rebuilding the devcontainer:

```json
"buildArgs": {
  "ENABLE_PYTHON": "true",
  "ENABLE_GO": "true",
  "ENABLE_RUST": "true"
}
```

Without those args, install them on demand inside the worker using `uv`, `go`
tarballs, or `rustup`; user-installed tools live under the persisted
`/home/node/.local` volume.

## Agent Login

Run agent login inside the worker:

```bash
jailctl agent-login codex
jailctl agent-login claude
```

Agent state is kept in jail-owned Docker volumes, not mounted from your host
agent config directories.

## Headroom

Headroom starts automatically in a detached worker tmux session named
by `JAIL_HEADROOM_TMUX_SESSION`:

```bash
headroom-attach
```

## tmux Layouts

Rebuilds recreate containers and kill running tmux processes. Save and restore
the layout with:

```bash
jail-tmux snapshot
jail-tmux restore
```

The snapshot is stored at `.devcontainer/.jail/tmux-layout.json`. It includes
all tmux sessions, windows, panes, working directories, and best-effort pane
commands, except managed sessions listed in `JAIL_MANAGED_TMUX_SESSIONS`, which
are started automatically.
Edit a pane's `command` field before restore when needed.

## Ponytail

Ponytail is installed, but plugins are not silently trusted. Install plugins
from the agent UI or CLI.

If plugin installation needs GitHub, approve that egress request in the
operator.

## SSH

SSH keys stay on the host. The worker has no private keys and no raw
`SSH_AUTH_SOCK`.

Run the operator, then use SSH normally inside the worker:

```bash
ssh root@your-tailnet-node
ssh git@github.com
```

The first matching invocation creates a pending SSH request. If approved, the
host broker runs real host SSH and relays stdin/stdout/stderr back to the jailed
process. Git uses the same path through `GIT_SSH=/usr/local/bin/ssh`.

For scoped lease approval:

```bash
jailctl ssh-lease staging-readonly --ttl 30m --wait
jailctl ssh-lease root@100.75.201.20 --ttl 4h --wait
```

Forwarding and proxy-style SSH features are intentionally denied by the broker.

## Browser Bridge

The optional host Chrome bridge is configured in
`customizations.jail.hostChrome` in `.devcontainer/devcontainer.json`.
By default it starts on macOS during devcontainer initialization when `open`,
`lsof`, and Google Chrome are available. It uses the dedicated profile:

```text
$HOME/.chrome-remote-test
```
