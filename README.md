# Hardened LLM Devcontainer

This repository is a single safe-by-default `.devcontainer` setup for AI-assisted development. A user should be able to copy this folder into a project, open the project in VS Code, and build the devcontainer directly.

## What Starts

VS Code uses [devcontainer.json](devcontainer.json), which starts [docker-compose.yml](docker-compose.yml):

- `worker`: the development container where AI/dev commands run.
- `egress-proxy`: the only service with outbound internet access.

Do not run the `Dockerfile` directly for normal use. The worker image alone can start, but approval-based networking depends on the `egress-proxy` sidecar.

## Security Model

The worker is intentionally restricted:

- no passwordless sudo
- no Docker socket mount
- no host SSH keys or SSH agent socket
- no Claude/Codex credential mounts
- no direct internet route
- no in-container firewall that the worker can rewrite
- all Linux capabilities dropped
- `no-new-privileges` enabled
- read-only root filesystem with tmpfs scratch paths

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
tools, the denial body includes the attempted host/port and the matching
`jailctl` request commands.

## Egress Approvals

The worker sends proxy-aware tools through:

```text
http://egress-proxy:8080
```

The proxy is default-deny. The worker can request access, but cannot approve it.
When proxy-aware tools attempt HTTP/HTTPS egress without approval, the proxy
returns a fast `403` with guidance like:

```text
HARDENED JAIL: egress denied
Attempted: connect registry.npmjs.org:443

Generic egress:
  jailctl egress registry.npmjs.org --port 443 --reason "<why>"

Package/tool installs:
  jailctl install npm ci
```

This is the primary low-noise path for agents: do not repeatedly retry blocked
network commands; create a `jailctl` request and wait for host approval.

Inside the worker:

```bash
jailctl egress example.com --port 443 --ttl 10m --reason "docs"
```

On the host:

```bash
.devcontainer/host/jail-approve-egress add example.com --port 443 --ttl 10m --reason "docs"
```

List and prune approvals:

```bash
.devcontainer/host/jail-approve-egress list
.devcontainer/host/jail-approve-egress prune
```

Unknown tools that ignore proxy settings should fail because the worker has no
direct internet route. Those failures may be less descriptive than proxy-aware
denials, but they are still blocked by the Docker network boundary.

## Package Installs

Direct package registry access is denied unless you approve egress. For package-manager work, create a request from inside the worker:

```bash
jailctl install npm ci
jailctl install uv sync
jailctl install cargo fetch
```

The request records the manager, arguments, current project, and lockfile hashes. The host operator can then approve a narrow egress window, populate caches, or rebuild the image.

## SSH

SSH keys stay on the host. The worker has no private keys and no raw `SSH_AUTH_SOCK`.

Configure aliases on the host:

```text
$HOME/.devcontainer-jail/policy/ssh-allowlist.json
```

Template: [host/ssh-allowlist.example.json](host/ssh-allowlist.example.json).

Open an approved host-side SSH session:

```bash
.devcontainer/host/jail-ssh-broker ssh staging-readonly
```

Request SSH from inside the worker:

```bash
jailctl ssh staging-readonly
```

For repeated use from one worker shell/session:

```bash
jailctl ssh-lease staging-readonly --ttl 30m
```

Approve the lease on the host:

```bash
.devcontainer/host/jail-ssh-broker requests --kind ssh-lease
.devcontainer/host/jail-ssh-broker approve-lease <request-file> --ttl 30m
```

After approval, `ssh staging-readonly` inside the same worker session reuses the lease. Raw SSH targets such as `user@host` are blocked by the worker `ssh` wrapper.

Current limitation: SSH is brokered, not transparently tunneled. `git fetch` over SSH inside the worker is not automatically bridged yet.

## Optional Browser Bridge

The host Chrome bridge is disabled by default so first-run setup is stable on macOS, Linux, and Windows hosts.

To enable it on macOS:

```bash
ENABLE_HOST_CHROME=true code .
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
- [host/jail-init](host/jail-init): host state initializer.
- [host/jail-approve-egress](host/jail-approve-egress): host egress approval tool.
- [host/jail-ssh-broker](host/jail-ssh-broker): host SSH broker.
