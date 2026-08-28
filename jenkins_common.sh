#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '[%s] %s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" \
    "$*" >&2
}

fail() {
  log "ERROR: $*"
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 \
    || fail "Required command not found: $1"
}

jenkins_url() {
  printf '%s' "${JENKINS_URL:-http://127.0.0.1:8080}"
}

wait_for_jenkins() {
  local url="${1:-$(jenkins_url)}"
  local timeout="${JENKINS_STARTUP_TIMEOUT:-300}"
  local interval="${JENKINS_POLL_INTERVAL:-5}"
  local elapsed=0

  log "Waiting for Jenkins at ${url} (timeout: ${timeout}s)"

  until curl \
    --silent \
    --show-error \
    --fail \
    --location \
    --max-time 10 \
    "${url}/login" \
    >/dev/null 2>&1
  do
    if (( elapsed >= timeout )); then
      log "Jenkins startup timeout reached"

      if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl status jenkins --no-pager >&2 || true
      fi

      if command -v journalctl >/dev/null 2>&1; then
        sudo journalctl \
          -u jenkins \
          --no-pager \
          -n 100 >&2 || true
      fi

      fail "Jenkins did not become ready within ${timeout}s"
    fi

    log "Jenkins not ready yet (${elapsed}/${timeout}s)"

    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  log "Jenkins is reachable"
}

urlencode() {
  require_command python3

  python3 - "$1" <<'PY'
import sys
from urllib.parse import quote

print(quote(sys.argv[1], safe=''))
PY
}

get_crumb() {
  local user="$1"
  local password="$2"
  local cookie_jar="$3"
  local url="${4:-$(jenkins_url)}"

  curl \
    --silent \
    --show-error \
    --fail \
    --user "${user}:${password}" \
    --cookie-jar "$cookie_jar" \
    "${url}/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,%22:%22,//crumb)"
}
