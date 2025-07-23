#!/bin/bash
set -euo pipefail

NON_INTERACTIVE=false
[[ "${1:-}" == "--non-interactive" ]] && NON_INTERACTIVE=true

BASELINE_VERSIONS=(
  "16.3.6"
  "16.7.6"
  "16.9.1"
  "16.11.5"
  "17.0.3"
  "17.1.4"
  "17.3.4"
  "17.4.2"
  "18.0.1"
  "18.2.0"
)

OS_CODENAME="jammy"
ARCH="amd64"
BASE_URL="https://packages.gitlab.com/gitlab/gitlab-ee/packages/ubuntu/${OS_CODENAME}"

LOGFILE="/var/log/gitlab-smart-upgrade.log"
DOWNLOAD_DIR="/tmp/gitlab-upgrade"
mkdir -p "$DOWNLOAD_DIR"
cd "$DOWNLOAD_DIR"

log() {
  echo "[`date`] $1" | tee -a "$LOGFILE"
}

progress_bar() {
  local message="$1"
  printf "🔄 %-60s" "$message"
}

done_bar() {
  echo -e " ✅"
}

get_current_version() {
  sudo gitlab-rake gitlab:env:info 2>/dev/null \
    | awk '/^GitLab information/,/^GitLab Shell/' \
    | grep -m1 "^Version:" \
    | sed -E 's/Version:[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+).*/\1/'
}

find_next_version() {
  local current="$1"
  local found=0
  for v in "${BASELINE_VERSIONS[@]}"; do
    [[ "$found" == "1" ]] && { echo "$v"; return; }
    [[ "$v" == "$current" ]] && found=1
  done
  echo ""
}

attempt_upgrade() {
  local version="$1"
  local file="gitlab-ee_${version}-ee.0_${ARCH}.deb"
  local url="${BASE_URL}/${file}/download.deb"

  progress_bar "Downloading $version..."
  wget -q "$url" -O "$file"
  done_bar

  progress_bar "Installing $version..."
  if ! sudo dpkg -i "$file" > /dev/null 2>dpkg_error.log; then
    done_bar
    log "❌ Install failed — parsing for required version..."

    local required_minor
    required_minor=$(grep -oP "upgrade to the latest \K[0-9]+\.[0-9]+(?=\.x)" dpkg_error.log || true)

    if [[ -n "$required_minor" ]]; then
      case "$required_minor" in
        "16.3") required_minor="16.3.6" ;;
        "16.7") required_minor="16.7.6" ;;
        "16.9") required_minor="16.9.1" ;;
        "16.11") required_minor="16.11.5" ;;
        "17.0") required_minor="17.0.3" ;;
        "17.1") required_minor="17.1.4" ;;
        "17.3") required_minor="17.3.4" ;;
        "17.4") required_minor="17.4.2" ;;
        "18.0") required_minor="18.0.1" ;;
        "18.2") required_minor="18.2.0_
