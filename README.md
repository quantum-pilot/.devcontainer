# Hardened LLM Devcontainer

This repository is a single safe-by-default `.devcontainer` setup for AI-assisted development. A user should be able to copy this folder into a project, open the project in VS Code, and build the devcontainer directly.

## What Starts

VS Code uses [devcontainer.json](devcontainer.json), which starts [docker-compose.yml](docker-compose.yml):

- `worker`: the development container where AI/dev commands run.
- `egress-proxy`: the only service with outbound internet access.

The worker image includes Claude Code (`claude`), Codex CLI (`codex`),
Graphify (`graphify`), GSD Core (`gsd-core`, `gsd-tools`, `gsd_run`), Headroom
(`headroom`), Ponytail (`ponytail`), `pnpm`, and `uv`.

Do not run the `Dockerfile` directly for normal use. The worker image alone can start, but approval-based networking depends on the `egress-proxy` sidecar.

## Security Model

The worker is intentionally restricted:

- no passwordless sudo
- no Docker socket mount
- no host SSH keys or SSH agent socket
- no host Claude/Codex credential mounts
- no direct internet route
- no in-container firewall that the worker can rewrite
- all Linux capabilities dropped
- `no-new-privileges` enabled
- read-only root filesystem with tmpfs scratch paths

Claude, Codex, and related agent tools run inside the worker. Their login state
is intentionally persisted in Docker named volumes mounted at paths such as
`/home/node/.claude` and `/home/node/.codex`. Agent credentials are therefore
available to processes inside the jail, but they are not direct mounts of the
host's primary agent config directories.

The workspace is still mounted broadly at `/workspace`. Files readable there are readable by the worker. Keep real secrets outside the workspace or mask them separately.

## Setup On A New Machine

Prerequisites:

- Docker Desktop, OrbStack, or another Docker engine with Compose support
- VS Code
- VS Code Dev Containers extension

Install:

1. Copy this directory as `.devcontainer` into the target project.
2. Open the project folder in VS Code.
3. Run `Dev Containers: Reopen in Container`.
4. VS Code runs `.devcontainer/host/jail-init` automatically and builds both Compose services.
5. After the container opens, the post-create check runs `jail-hardening-check`.

Manual CLI equivalent:

```bash
devcontainer up --workspace-folder .
```

Initialize host-owned state manually if needed:

```bash
.devcontainer/host/jail-init
```

Host-owned state is stored outside the project:

```text
$HOME/.devcontainer-jail/policy
$HOME/.devcontainer-jail/state
$HOME/.devcontainer-jail/requests
```

That directory is intended to survive container rebuilds, Docker restarts, and
normal host reboots. Worker shell history and agent login state are also kept in
Docker named volumes unless those volumes are explicitly removed.

To use a different host-owned state directory, set:

```bash
export DEVCONTAINER_JAIL_HOME=/tmp/my-devcontainer-jail
```

## Verification

Inside the worker:

```bash
jail-hardening-check
```

Expected result: every check prints `OK`.

Quick network behavior check:

```bash
curl -I https://example.com
```

Expected result before approval: denied by the egress proxy. For proxy-aware
tools, the request is held while a pending operator request is open. If the
operator denies, blocks, or the client times out first, the denial body includes
the attempted host/port.

## Host Operator

The worker sends proxy-aware tools through:

```text
http://egress-proxy:8080
```

The proxy is default-deny. The worker can request access, but cannot approve it;
host-side decisions happen in one TTY:

```bash
.devcontainer/host/jail-operator
```

Default-denied proxy-aware HTTP/HTTPS attempts automatically create deduplicated
pending operator requests. The proxy holds the client connection open while the
operator decides. Approval lets the original request continue if the client has
not timed out; denial returns `403` with the attempted target:

```text
HARDENED JAIL: egress denied
Attempted: connect registry.npmjs.org:443
```

This is the primary low-noise path for agents: do not repeatedly retry blocked
network commands; leave the request for the operator.

The operator live-refreshes pending requests and lets you approve, deny, review,
revoke, and permanently block access from the same TTY. Use arrow keys to move,
Page Up/Page Down or Space/`b` to page, Enter to show or hide details, `tab` to
switch between pending requests, active approvals, blacklist, and SSH aliases,
`s` to toggle timestamp/alphabetical sorting, and `q` to quit. The bottom help
line changes per view: pending requests support approve/deny/forever-deny,
approvals support TTL changes and revoke, blacklist supports unblock, and SSH
aliases support add/remove/block. TTL choices include `forever` for durable
approvals such as GitHub or agent APIs; these can be shortened or revoked later
from the active approvals view.

Expired approvals are pruned from the policy when the operator refreshes, so
they do not continue to populate the active approval list.

Blacklist entries are enforced before approvals by the egress proxy and before
SSH sessions by the operator. Blocked targets do not create repeat pending
requests and are denied immediately.

Unknown tools that ignore proxy settings should fail because the worker has no
direct internet route. Those failures may be less descriptive than proxy-aware
denials, but they are still blocked by the Docker network boundary.

## Package Installs

Direct package registry access is denied unless you approve egress. Prefer
`pnpm` for Node projects and `uv` for Python projects when the project supports
them. They are installed in the image.

For package-manager work, run one command inside the worker:

```bash
jailctl install --run pnpm install --frozen-lockfile
jailctl install --run uv sync
jailctl install --run cargo fetch
```

`--run` creates the request, waits for approval in the operator, then
executes the package command in the same worker TTY. Use request-only mode when
you want to approve first and run manually later:

```bash
jailctl install --wait pnpm install --frozen-lockfile
```

Fallbacks remain available for projects that already standardize on them:

```bash
jailctl install --run npm ci
jailctl install --run pip install -r requirements.txt
```

The request records the manager, arguments, current project, and lockfile
hashes so the operator can approve a narrow egress window.

## Agent Login

Run agent login inside the worker so the jail-owned Docker volumes hold the
agent state:

```bash
jailctl agent-login codex
jailctl agent-login claude
```

The command creates a host approval request, waits for operator approval, and
then launches the agent login command inside the container. The login UI runs in
the worker terminal.

After login, use the tools normally:

```bash
codex
claude
graphify --help
gsd-tools --help
headroom --help
pnpm --version
uv --version
```

## Headroom Proxy

The worker starts Headroom automatically in a detached tmux session named
`headroom`:

```bash
tmux attach -t headroom
```

It binds explicitly to `127.0.0.1:8787` inside the worker and writes JSONL logs
to:

```text
/home/node/.local/share/headroom/proxy.jsonl
```

Interactive shells export these defaults:

```bash
ANTHROPIC_BASE_URL=http://127.0.0.1:8787
OPENAI_BASE_URL=http://127.0.0.1:8787/v1
```

The proxy process itself is launched through `headroom-proxy`, which unsets
those client-side base URL variables before starting Headroom so it does not
accidentally route upstream calls back into itself.

`host/jail-init` seeds exact-host, forever approvals for common agent endpoints
once. They remain visible in the operator and can be shortened or revoked there;
the seed marker prevents revoked defaults from being recreated on every init.

## Ponytail

Ponytail is installed from `@dietrichgebert/ponytail`, but the container does
not silently install or trust agent plugins. Install plugins from the agent UI
or CLI so the enabled hooks are visible.

For Codex:

```bash
codex plugin marketplace add DietrichGebert/ponytail
codex plugin add ponytail@ponytail
```

If hook trust is required, open `/hooks` in Codex and review it there.

For Claude Code, send these as two separate prompts:

```text
/plugin marketplace add DietrichGebert/ponytail
/plugin install ponytail@ponytail
```

Agent plugin state persists in the jail-owned Docker volumes mounted at
`/home/node/.codex` and `/home/node/.claude`.

## SSH

SSH keys stay on the host. The worker has no private keys and no raw `SSH_AUTH_SOCK`.

Manage SSH aliases from the operator's `ssh` view. Press `n` to add an alias,
`r` to remove one, and `x` to move an alias to the blacklist. The shared
blacklist view shows both egress blocks and SSH alias blocks; press `r` there to
unblock. The underlying policy is stored at
`$HOME/.devcontainer-jail/policy/ssh-allowlist.json`.

Request SSH from inside the worker:

```bash
jailctl ssh staging-readonly
```

This writes a request. Approving it in the operator opens the actual SSH process
in the operator terminal on the host, using host keys.

For scoped lease approval from one worker shell/session:

```bash
jailctl ssh-lease staging-readonly --ttl 30m --wait
```

Raw SSH targets such as `user@host` are blocked by the worker `ssh` wrapper.

Current limitation: SSH is brokered through the operator, not transparently
tunneled. `git fetch` over SSH inside the worker is not automatically bridged
yet. Prefer HTTPS remotes inside the jail, or open host-side SSH sessions
through the operator.

## Optional Browser Bridge

The host Chrome bridge is configured in:

```text
.devcontainer/host/chrome-bridge.env
```

By default it starts on macOS during devcontainer initialization when `open`,
`lsof`, and Google Chrome are available. Disable or adjust it by editing that
file:

```env
HOST_CHROME_ENABLED=true
CHROME_REMOTE_PORT=9222
CHROME_REMOTE_BIND=127.0.0.1
CHROME_REMOTE_PROFILE="$HOME/.chrome-remote-test"
```

It uses a dedicated test profile:

```text
$HOME/.chrome-remote-test
```

It binds Chrome DevTools Protocol to `127.0.0.1` by default. Keep this profile for test-app auth only; do not use your personal Chrome profile for agent-driven browser automation.

## File Map

- [devcontainer.json](devcontainer.json): VS Code entrypoint.
- [docker-compose.yml](docker-compose.yml): worker plus egress proxy topology.
- [Dockerfile](Dockerfile): locked-down worker image.
- [Dockerfile.proxy](Dockerfile.proxy): default-deny egress proxy image.
- [scripts/jailctl](scripts/jailctl): worker-side request CLI.
- [scripts/egress-proxy.py](scripts/egress-proxy.py): proxy enforcement.
- [scripts/jail-hardening-check](scripts/jail-hardening-check): in-worker validation.
- [scripts/headroom-proxy](scripts/headroom-proxy): worker-local Headroom proxy launcher.
- [scripts/jail-start](scripts/jail-start): worker startup script.
- [host/jail-init](host/jail-init): host state initializer.
- [host/jail-operator](host/jail-operator): interactive host approval TUI.
