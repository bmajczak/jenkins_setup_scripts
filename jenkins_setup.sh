#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=jenkins_common.sh
source "${SCRIPT_DIR}/jenkins_common.sh"

JENKINS_URL="${JENKINS_URL:-http://127.0.0.1:8080}"
JENKINS_REPO_CHANNEL="${JENKINS_REPO_CHANNEL:-stable}"
JAVA_PACKAGE_RHEL="${JAVA_PACKAGE_RHEL:-java-21-openjdk}"
JAVA_PACKAGE_DEBIAN="${JAVA_PACKAGE_DEBIAN:-openjdk-21-jre}"
INSTALL_GIT="${INSTALL_GIT:-true}"
RUN_INITIAL_SETUP="${RUN_INITIAL_SETUP:-true}"
INSTALL_PLUGINS="${INSTALL_PLUGINS:-true}"
CONFIGURE_ROOT_URL="${CONFIGURE_ROOT_URL:-true}"

as_root() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

install_rhel_family() {
  local pm
  if command -v dnf >/dev/null 2>&1; then pm=dnf; else pm=yum; fi

  as_root "$pm" -y install ca-certificates curl wget fontconfig "$JAVA_PACKAGE_RHEL"
  [[ "$INSTALL_GIT" == true ]] && as_root "$pm" -y install git

  local repo_base
  if [[ "$JENKINS_REPO_CHANNEL" == "stable" ]]; then repo_base="redhat-stable"; else repo_base="redhat"; fi

  as_root wget -q -O /etc/yum.repos.d/jenkins.repo \
    "https://pkg.jenkins.io/${repo_base}/jenkins.repo"
  as_root rpm --import "https://pkg.jenkins.io/${repo_base}/jenkins.io-2023.key"
  as_root "$pm" -y install jenkins
}

install_debian_family() {
  as_root apt-get update
  as_root apt-get install -y ca-certificates curl wget fontconfig gnupg "$JAVA_PACKAGE_DEBIAN"
  [[ "$INSTALL_GIT" == true ]] && as_root apt-get install -y git

  as_root install -m 0755 -d /etc/apt/keyrings
  local repo_base
  if [[ "$JENKINS_REPO_CHANNEL" == "stable" ]]; then repo_base="debian-stable"; else repo_base="debian"; fi

  curl -fsSL "https://pkg.jenkins.io/${repo_base}/jenkins.io-2026.key" \
    | as_root tee /etc/apt/keyrings/jenkins-keyring.asc >/dev/null
  echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/${repo_base} binary/" \
    | as_root tee /etc/apt/sources.list.d/jenkins.list >/dev/null
  as_root apt-get update
  as_root apt-get install -y jenkins
}

install_jenkins() {
  if command -v apt-get >/dev/null 2>&1; then
    log "Detected Debian/Ubuntu family"
    install_debian_family
  elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
    log "Detected RHEL/Amazon Linux family"
    install_rhel_family
  else
    fail "Unsupported package manager. Supported: apt, dnf, yum"
  fi
}

main() {
  require_command curl
  install_jenkins

  as_root systemctl daemon-reload
  as_root systemctl enable --now jenkins
  wait_for_jenkins "$JENKINS_URL"

  if [[ "$RUN_INITIAL_SETUP" == true ]]; then
    as_root env \
      JENKINS_URL="$JENKINS_URL" \
      JENKINS_ADMIN_USER="${JENKINS_ADMIN_USER:-admin}" \
      JENKINS_ADMIN_PASSWORD="${JENKINS_ADMIN_PASSWORD:-}" \
      JENKINS_ADMIN_FULLNAME="${JENKINS_ADMIN_FULLNAME:-Jenkins Administrator}" \
      JENKINS_ADMIN_EMAIL="${JENKINS_ADMIN_EMAIL:-admin@example.invalid}" \
      "${SCRIPT_DIR}/jenkins_unlock.sh"
  fi

  if [[ "$INSTALL_PLUGINS" == true ]]; then
    as_root env \
      JENKINS_URL="$JENKINS_URL" \
      JENKINS_ADMIN_USER="${JENKINS_ADMIN_USER:-admin}" \
      JENKINS_ADMIN_PASSWORD="${JENKINS_ADMIN_PASSWORD:-}" \
      JENKINS_PLUGIN_FILE="${JENKINS_PLUGIN_FILE:-${SCRIPT_DIR}/plugins.txt}" \
      "${SCRIPT_DIR}/jenkins_plugins.sh"

    as_root systemctl restart jenkins
    wait_for_jenkins "$JENKINS_URL"
  fi

  if [[ "$CONFIGURE_ROOT_URL" == true ]]; then
    as_root env \
      JENKINS_URL="$JENKINS_URL" \
      JENKINS_ROOT_URL="${JENKINS_ROOT_URL:-$JENKINS_URL}" \
      JENKINS_ADMIN_USER="${JENKINS_ADMIN_USER:-admin}" \
      JENKINS_ADMIN_PASSWORD="${JENKINS_ADMIN_PASSWORD:-}" \
      "${SCRIPT_DIR}/jenkins_confirm_url.sh"
  fi

  log "Jenkins base setup completed"
}

main "$@"
