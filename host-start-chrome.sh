#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_file="${HOST_CHROME_CONFIG:-$script_dir/host/chrome-bridge.env}"

if [[ -f "$config_file" ]]; then
  # shellcheck source=/dev/null
  source "$config_file"
fi

if [[ "${HOST_CHROME_ENABLED:-${ENABLE_HOST_CHROME:-false}}" != "true" ]]; then
  echo "Host Chrome bridge disabled in ${config_file}."
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
