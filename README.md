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
5. After the container opens, `jail check` runs.

Host-owned jail state lives outside the project at:

```text
$HOME/.devcontainer-jail
```

Set `DEVCONTAINER_JAIL_HOME` before launching VS Code if you want that state in
a different location.

## Verify

Inside the worker:

```bash
jail check
```

Expected result: every check prints `OK`.

To test egress approval:

```bash
curl -I https://example.com
```

Before approval, this creates a pending request and holds the client connection.

## Jail Helper

The worker exposes one helper command:

```bash
jail check
jail bootstrap
jail agent-login codex
jail agent-login claude
jail tmux snapshot
jail tmux restore
```

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

## Agent Login

Run agent login inside the worker:

```bash
jail agent-login codex
jail agent-login claude
```

> This bypasses Headroom for auth by running the equivalent of
> `env -u OPENAI_BASE_URL codex login` or
> `env -u ANTHROPIC_BASE_URL claude`.

Agent state is kept in jail-owned Docker volumes, not mounted from your host
agent config directories.

## Network Access

Proxy-aware network requests are default-deny. Unknown HTTP/HTTPS targets create
or update one pending request per target. If approved before the client times
out, the original request continues.

Host raw-TCP services configured in `customizations.jail.bridgePorts` are
reachable at `proxy:<port>`. For example, Postgres on the host at `5432` should
use `proxy:5432` from inside the worker.

For package-manager work, run the package manager normally. Unknown network
targets will appear in the operator for approval.

Node/JavaScript tooling is enabled by default. `pnpm`, `uv`, and `mise` are the
preferred package and toolchain managers.

Install Python with `uv` or `mise`, and Go/Rust with `mise`, on demand inside
the worker. The alias `m` is available for `mise`. User and per-repo toolchain
state lives under persisted `/home/node/.local` paths.

For shell customizations, edit `~/.zshrc.local`; it is persisted under
`/home/node/.local/config/shell/zshrc` and sourced on startup.

## tmux Layouts

Rebuilds recreate containers and kill running tmux processes. Save and restore
the layout with:

```bash
jail tmux snapshot
jail tmux restore
```

The snapshot is stored at `.devcontainer/.jail/tmux-layout.json`. It includes
all tmux sessions, windows, panes, working directories, and best-effort pane
commands, except managed sessions listed in `JAIL_MANAGED_TMUX_SESSIONS`, which
are started automatically.
Edit a pane's `command` field before restore when needed.

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

Forwarding and proxy-style SSH features are intentionally denied by the broker.

## Browser Bridge

The optional host Chrome bridge is configured in
`customizations.jail.hostChrome` in `.devcontainer/devcontainer.json`.
By default it starts on macOS during devcontainer initialization when `open`,
`lsof`, and Google Chrome are available. It uses the dedicated profile:

```text
$HOME/.chrome-remote-test
```

Agents can connect to the host browser's CDP endpoint at:

```text
http://host.docker.internal:9222
```

## Agent Tooling

The worker image includes:

- [Claude Code](https://github.com/anthropics/claude-code)
- [Codex CLI](https://github.com/openai/codex)
- [Headroom](https://github.com/headroomlabs-ai/headroom)
- [Ponytail](https://github.com/DietrichGebert/ponytail)
- [Graphify](https://github.com/rhanka/graphify)
- [GSD Core](https://github.com/open-gsd/gsd-core)

Headroom starts automatically in a detached worker tmux session named by
`JAIL_HEADROOM_TMUX_SESSION`.

Ponytail is installed, but plugins are not silently trusted. Install plugins
from the agent UI or CLI. If plugin installation needs GitHub, approve that
egress request in the operator.
