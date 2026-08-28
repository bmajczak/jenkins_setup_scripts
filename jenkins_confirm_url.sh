#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=jenkins_common.sh
source "${SCRIPT_DIR}/jenkins_common.sh"

JENKINS_URL="${JENKINS_URL:-http://127.0.0.1:8080}"
JENKINS_ROOT_URL="${JENKINS_ROOT_URL:-$JENKINS_URL}"
JENKINS_ADMIN_USER="${JENKINS_ADMIN_USER:-admin}"
JENKINS_ADMIN_PASSWORD="${JENKINS_ADMIN_PASSWORD:-}"

[[ -n "$JENKINS_ADMIN_PASSWORD" ]] || fail "JENKINS_ADMIN_PASSWORD must be set"

require_command curl
wait_for_jenkins "$JENKINS_URL"

cookie_jar="$(mktemp)"
trap 'rm -f "$cookie_jar"' EXIT

full_crumb="$(get_crumb "$JENKINS_ADMIN_USER" "$JENKINS_ADMIN_PASSWORD" "$cookie_jar" "$JENKINS_URL")"
crumb_field="${full_crumb%%:*}"
crumb_value="${full_crumb#*:}"
root_url="${JENKINS_ROOT_URL%/}/"
root_url_encoded="$(urlencode "$root_url")"
crumb_encoded="$(urlencode "$crumb_value")"

log "Setting Jenkins root URL to ${root_url}"

curl --silent --show-error --fail --request POST \
  --user "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" \
  --cookie "$cookie_jar" \
  --header "${crumb_field}: ${crumb_value}" \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data "rootUrl=${root_url_encoded}" \
  --data "Jenkins-Crumb=${crumb_encoded}" \
  --data 'core:apply=' \
  --data 'Submit=Save' \
  "${JENKINS_URL}/setupWizard/configureInstance" >/dev/null

log "Jenkins root URL configured"
