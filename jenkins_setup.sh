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

apt_cmd() {
  as_root env \
    DEBIAN_FRONTEND=noninteractive \
    NEEDRESTART_MODE=a \
    apt-get "$@"
}

apt_update() {
  local attempt

  for attempt in 1 2 3; do
    log "Running apt-get update (attempt ${attempt}/3)"

    if apt_cmd update; then
      return 0
    fi

    log "apt-get update failed, cleaning APT metadata"

    apt_cmd clean || true
    as_root rm -rf /var/lib/apt/lists/*
    as_root mkdir -p /var/lib/apt/lists/partial

    sleep 5
  done

  log "=== APT diagnostics ==="

  as_root sh -c \
    'cat /etc/apt/sources.list 2>/dev/null || true'

  as_root sh -c \
    'find /etc/apt/sources.list.d -maxdepth 1 -type f -exec sh -c '\''echo "--- $1"; cat "$1"'\'' _ {} \; 2>/dev/null || true'

  df -h || true
  df -i || true

  fail "apt-get update failed after 3 attempts"
}

install_debian_family() {
  log "Cleaning existing APT metadata"

  apt_cmd clean || true

  as_root rm -rf /var/lib/apt/lists/*
  as_root mkdir -p /var/lib/apt/lists/partial

  apt_update

  log "Installing base dependencies"

  apt_cmd install -y \
    ca-certificates \
    curl \
    wget \
    fontconfig \
    gnupg \
    "$JAVA_PACKAGE_DEBIAN"

  if [[ "$INSTALL_GIT" == "true" ]]; then
    apt_cmd install -y git
  fi

  log "Creating APT keyring directory"

  as_root install \
    -m 0755 \
    -d /etc/apt/keyrings

  local repo_base

  if [[ "$JENKINS_REPO_CHANNEL" == "stable" ]]; then
    repo_base="debian-stable"
  else
    repo_base="debian"
  fi

  log "Adding Jenkins APT repository"

  curl -fsSL \
    "https://pkg.jenkins.io/${repo_base}/jenkins.io-2026.key" \
    | as_root tee \
      /etc/apt/keyrings/jenkins-keyring.asc \
      >/dev/null

  echo \
    "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/${repo_base} binary/" \
    | as_root tee \
      /etc/apt/sources.list.d/jenkins.list \
      >/dev/null

  log "Refreshing APT metadata after adding Jenkins repository"

  as_root rm -rf /var/lib/apt/lists/*
  as_root mkdir -p /var/lib/apt/lists/partial

  apt_update

  log "Installing Jenkins"

  apt_cmd install -y jenkins
}

install_rhel_family() {
  local pm

  if command -v dnf >/dev/null 2>&1; then
    pm="dnf"
  else
    pm="yum"
  fi

  log "Installing base dependencies"

  as_root "$pm" -y install \
    ca-certificates \
    curl \
    wget \
    fontconfig \
    "$JAVA_PACKAGE_RHEL"

  if [[ "$INSTALL_GIT" == "true" ]]; then
    as_root "$pm" -y install git
  fi

  local repo_base

  if [[ "$JENKINS_REPO_CHANNEL" == "stable" ]]; then
    repo_base="redhat-stable"
  else
    repo_base="redhat"
  fi

  log "Adding Jenkins RPM repository"

  as_root wget \
    -q \
    -O /etc/yum.repos.d/jenkins.repo \
    "https://pkg.jenkins.io/${repo_base}/jenkins.repo"

  as_root rpm \
    --import \
    "https://pkg.jenkins.io/${repo_base}/jenkins.io-2023.key"

  log "Installing Jenkins"

  as_root "$pm" -y install jenkins
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

start_jenkins() {
  log "Starting Jenkins"

  as_root systemctl daemon-reload
  as_root systemctl enable jenkins

  if ! as_root systemctl restart jenkins; then
    log "Jenkins failed to start"

    echo "=== systemctl status jenkins ==="
    as_root systemctl status jenkins --no-pager || true

    echo "=== journalctl -u jenkins ==="
    as_root journalctl \
      -u jenkins \
      --no-pager \
      -n 150 || true

    echo "=== Java version ==="
    java -version || true

    fail "Jenkins service failed to start"
  fi

  log "Waiting for Jenkins"

  wait_for_jenkins "$JENKINS_URL"
}

run_initial_setup() {
  log "Running initial Jenkins setup"

  as_root env \
    JENKINS_URL="$JENKINS_URL" \
    JENKINS_ADMIN_USER="${JENKINS_ADMIN_USER:-admin}" \
    JENKINS_ADMIN_PASSWORD="${JENKINS_ADMIN_PASSWORD:-}" \
    JENKINS_ADMIN_FULLNAME="${JENKINS_ADMIN_FULLNAME:-Jenkins Administrator}" \
    JENKINS_ADMIN_EMAIL="${JENKINS_ADMIN_EMAIL:-admin@example.invalid}" \
    bash "${SCRIPT_DIR}/jenkins_unlock.sh"
}

install_plugins() {
  log "Installing Jenkins plugins"

  as_root env \
    JENKINS_URL="$JENKINS_URL" \
    JENKINS_ADMIN_USER="${JENKINS_ADMIN_USER:-admin}" \
    JENKINS_ADMIN_PASSWORD="${JENKINS_ADMIN_PASSWORD:-}" \
    JENKINS_PLUGIN_FILE="${JENKINS_PLUGIN_FILE:-${SCRIPT_DIR}/plugins.txt}" \
    bash "${SCRIPT_DIR}/jenkins_plugins.sh"

  log "Restarting Jenkins after plugin installation"

  if ! as_root systemctl restart jenkins; then
    echo "=== systemctl status jenkins ==="
    as_root systemctl status jenkins --no-pager || true

    echo "=== journalctl -u jenkins ==="
    as_root journalctl \
      -u jenkins \
      --no-pager \
      -n 150 || true

    fail "Jenkins failed to restart after plugin installation"
  fi

  wait_for_jenkins "$JENKINS_URL"
}

configure_root_url() {
  log "Configuring Jenkins root URL"

  as_root env \
    JENKINS_URL="$JENKINS_URL" \
    JENKINS_ROOT_URL="${JENKINS_ROOT_URL:-$JENKINS_URL}" \
    JENKINS_ADMIN_USER="${JENKINS_ADMIN_USER:-admin}" \
    JENKINS_ADMIN_PASSWORD="${JENKINS_ADMIN_PASSWORD:-}" \
    bash "${SCRIPT_DIR}/jenkins_confirm_url.sh"
}

main() {
  require_command curl

  install_jenkins
  start_jenkins

  if [[ "$RUN_INITIAL_SETUP" == "true" ]]; then
    run_initial_setup
  fi

  if [[ "$INSTALL_PLUGINS" == "true" ]]; then
    install_plugins
  fi

  if [[ "$CONFIGURE_ROOT_URL" == "true" ]]; then
    configure_root_url
  fi

  log "Jenkins base setup completed"
}

main "$@"
