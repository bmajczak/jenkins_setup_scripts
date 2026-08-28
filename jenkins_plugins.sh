#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=jenkins_common.sh
source "${SCRIPT_DIR}/jenkins_common.sh"

JENKINS_URL="${JENKINS_URL:-http://127.0.0.1:8080}"
JENKINS_ADMIN_USER="${JENKINS_ADMIN_USER:-admin}"
JENKINS_ADMIN_PASSWORD="${JENKINS_ADMIN_PASSWORD:-}"
JENKINS_PLUGIN_FILE="${JENKINS_PLUGIN_FILE:-${SCRIPT_DIR}/plugins.txt}"

[[ -n "$JENKINS_ADMIN_PASSWORD" ]] || fail "JENKINS_ADMIN_PASSWORD must be set"
[[ -f "$JENKINS_PLUGIN_FILE" ]] || fail "Plugin file not found: ${JENKINS_PLUGIN_FILE}"

require_command curl
require_command python3
wait_for_jenkins "$JENKINS_URL"

mapfile -t plugins < <(grep -Ev '^[[:space:]]*(#|$)' "$JENKINS_PLUGIN_FILE" | sed 's/[[:space:]]*$//')
((${#plugins[@]} > 0)) || fail "No plugins found in ${JENKINS_PLUGIN_FILE}"

cookie_jar="$(mktemp)"
payload_file="$(mktemp)"
trap 'rm -f "$cookie_jar" "$payload_file"' EXIT

full_crumb="$(get_crumb "$JENKINS_ADMIN_USER" "$JENKINS_ADMIN_PASSWORD" "$cookie_jar" "$JENKINS_URL")"
crumb_field="${full_crumb%%:*}"
crumb_value="${full_crumb#*:}"

python3 - "$crumb_value" "${plugins[@]}" > "$payload_file" <<'PY'
import json
import sys

crumb = sys.argv[1]
plugins = sys.argv[2:]
print(json.dumps({
    "dynamicLoad": False,
    "plugins": plugins,
    "Jenkins-Crumb": crumb,
}))
PY

log "Requesting installation of ${#plugins[@]} Jenkins plugins"

curl --silent --show-error --fail --request POST \
  --user "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" \
  --cookie "$cookie_jar" \
  --header "${crumb_field}: ${crumb_value}" \
  --header 'Content-Type: application/json' \
  --data-binary "@${payload_file}" \
  "${JENKINS_URL}/pluginManager/installPlugins" >/dev/null

log "Plugin installation requested; restart Jenkins after downloads complete"
