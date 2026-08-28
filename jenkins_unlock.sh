#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=jenkins_common.sh
source "${SCRIPT_DIR}/jenkins_common.sh"

JENKINS_URL="${JENKINS_URL:-http://127.0.0.1:8080}"
JENKINS_HOME="${JENKINS_HOME:-/var/lib/jenkins}"
JENKINS_ADMIN_USER="${JENKINS_ADMIN_USER:-admin}"
JENKINS_ADMIN_PASSWORD="${JENKINS_ADMIN_PASSWORD:-}"
JENKINS_ADMIN_FULLNAME="${JENKINS_ADMIN_FULLNAME:-Jenkins Administrator}"
JENKINS_ADMIN_EMAIL="${JENKINS_ADMIN_EMAIL:-admin@example.invalid}"
INITIAL_ADMIN_PASSWORD_FILE="${INITIAL_ADMIN_PASSWORD_FILE:-${JENKINS_HOME}/secrets/initialAdminPassword}"

[[ -n "$JENKINS_ADMIN_PASSWORD" ]] || fail "JENKINS_ADMIN_PASSWORD must be set"
[[ -r "$INITIAL_ADMIN_PASSWORD_FILE" ]] || fail "Cannot read ${INITIAL_ADMIN_PASSWORD_FILE}. Jenkins may already be configured or has not initialized yet."

require_command curl
wait_for_jenkins "$JENKINS_URL"

initial_password="$(<"$INITIAL_ADMIN_PASSWORD_FILE")"
cookie_jar="$(mktemp)"
trap 'rm -f "$cookie_jar"' EXIT

full_crumb="$(get_crumb admin "$initial_password" "$cookie_jar" "$JENKINS_URL")"
crumb_field="${full_crumb%%:*}"
crumb_value="${full_crumb#*:}"

username="$(urlencode "$JENKINS_ADMIN_USER")"
password="$(urlencode "$JENKINS_ADMIN_PASSWORD")"
fullname="$(urlencode "$JENKINS_ADMIN_FULLNAME")"
email="$(urlencode "$JENKINS_ADMIN_EMAIL")"
crumb_encoded="$(urlencode "$crumb_value")"

log "Creating Jenkins administrator '${JENKINS_ADMIN_USER}'"

curl --silent --show-error --fail --request POST \
  --user "admin:${initial_password}" \
  --cookie "$cookie_jar" \
  --header "${crumb_field}: ${crumb_value}" \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data "username=${username}" \
  --data "password1=${password}" \
  --data "password2=${password}" \
  --data "fullname=${fullname}" \
  --data "email=${email}" \
  --data "Jenkins-Crumb=${crumb_encoded}" \
  --data 'core:apply=' \
  --data 'Submit=Save' \
  "${JENKINS_URL}/setupWizard/createAdminUser" >/dev/null

log "Jenkins administrator created"
