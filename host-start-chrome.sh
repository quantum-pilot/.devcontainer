PORT=9222
PROFILE="$HOME/.chrome-remote"

if ! lsof -nP -iTCP:9222 -sTCP:LISTEN >/dev/null 2>&1 ; then
  echo "🔵 Starting Dev-Container Chrome on port ${PORT}"
  open -na "Google Chrome" --args \
    --remote-debugging-port=${PORT} \
    --remote-debugging-address=0.0.0.0 \
    --user-data-dir="${PROFILE}" \
    --remote-allow-origins="*" \
    --no-first-run --no-default-browser-check
else
  echo "🟢 Reusing existing Dev-Container Chrome on port ${PORT}"
fi
