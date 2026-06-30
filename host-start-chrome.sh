#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_file="$script_dir/devcontainer.json"

config_values="$(
  DEVCONTAINER_JSON="$config_file" python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path

config_path = Path(os.environ["DEVCONTAINER_JSON"])
config = json.loads(config_path.read_text(encoding="utf-8"))
chrome = config.get("customizations", {}).get("jail", {}).get("hostChrome", {})

def value(name, default):
    return chrome.get(name, default)

def shell_value(name, value):
    if isinstance(value, bool):
        value = "true" if value else "false"
    print(f"{name}={shlex.quote(str(value))}")

shell_value("HOST_CHROME_ENABLED", value("enabled", False))
shell_value("CHROME_REMOTE_PORT", value("port", 9222))
shell_value("CHROME_REMOTE_BIND", value("bind", "127.0.0.1"))
shell_value("CHROME_REMOTE_PROFILE", value("profile", "$HOME/.chrome-remote-test"))
PY
)"
eval "$config_values"

if [[ "${HOST_CHROME_ENABLED}" != "true" ]]; then
  echo "Host Chrome bridge disabled in devcontainer.json."
  exit 0
fi

if ! command -v open >/dev/null 2>&1; then
  echo "Host Chrome bridge skipped: this launcher currently supports macOS 'open'."
  exit 0
fi

if ! command -v lsof >/dev/null 2>&1; then
  echo "Host Chrome bridge skipped: lsof is not available."
  exit 0
fi

PORT="${CHROME_REMOTE_PORT:-9222}"
PROFILE="${CHROME_REMOTE_PROFILE:-$HOME/.chrome-remote-test}"
BIND_ADDRESS="${CHROME_REMOTE_BIND:-127.0.0.1}"
PROFILE="${PROFILE/#\$HOME/$HOME}"

if ! lsof -nP -iTCP:"${PORT}" -sTCP:LISTEN >/dev/null 2>&1 ; then
  echo "Starting Dev-Container Chrome on port ${PORT}"
  open -na "Google Chrome" --args \
    --remote-debugging-port=${PORT} \
    --remote-debugging-address="${BIND_ADDRESS}" \
    --user-data-dir="${PROFILE}" \
    --remote-allow-origins="*" \
    --no-first-run --no-default-browser-check
else
  echo "Reusing existing Dev-Container Chrome on port ${PORT}"
fi
