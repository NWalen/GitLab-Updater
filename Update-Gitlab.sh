#!/bin/bash
set -euo pipefail

# Optional flag
NON_INTERACTIVE=false
[[ "${1:-}" == "--non-interactive" ]] && NON_INTERACTIVE=true

# Known good upgrade path (updated with missing minors)
BASELINE_VERSIONS=(
  "16.3.6"
  "16.7.6"
  "16.9.1"
  "16.11.5"
  "17.0.3"
  "17.1.4"
  "17.3.4"
  "17.4.2"
  "17.8.4"
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


find_upgrade_path() {
  local current="$1"
  local started=0
  UPGRADE_PATH=()

  for v in "${BASELINE_VERSIONS[@]}"; do
    if [[ "$started" -eq 1 ]]; then
      UPGRADE_PATH+=("$v")
    elif [[ "$v" == "$current" ]]; then
      started=1
    fi
  done
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
    log "❌ dpkg failed for $version — checking for required intermediate version..."

    local required_version
    required_version=$(grep -oP "upgrade to the latest \K[0-9]+\.[0-9]+(?=\.x)" dpkg_error.log || true)

    if [[ -n "$required_version" ]]; then
      case "$required_version" in
        "16.3")  required_version="16.3.6" ;;
        "16.7")  required_version="16.7.6" ;;
        "16.9")  required_version="16.9.1" ;;
        "16.11") required_version="16.11.5" ;;
        "17.0")  required_version="17.0.3" ;;
        "17.1")  required_version="17.1.4" ;;
        "17.3")  required_version="17.3.4" ;;
        "17.4")  required_version="17.4.2" ;;
        "18.0")  required_version="18.0.1" ;;
        "18.2")  required_version="18.2.0" ;;
        *) log "⚠️ Unknown version requirement: $required_version"; exit 1 ;;
      esac

      log "➕ Inserting required version: $required_version before $version"
      UPGRADE_PATH=("$required_version" "$version" "${UPGRADE_PATH[@]:1}")
    else
      log "❌ Could not determine missing version. Check dpkg_error.log."
      exit 1
    fi
    return 1
  fi
  done_bar

  progress_bar "Reconfiguring $version..."
  sudo gitlab-ctl reconfigure > /dev/null
  done_bar

  log "✅ Successfully upgraded to $version"
  sudo gitlab-rake gitlab:env:info >> "$LOGFILE"

  if [[ "$NON_INTERACTIVE" == false ]]; then
    read -p "🔎 Press Enter to continue..."
  fi

  return 0
}

main() {
  local current
  current=$(get_current_version)
  log "📌 Current GitLab version: $current"

  find_upgrade_path "$current"

  if [[ "${#UPGRADE_PATH[@]}" -eq 0 ]]; then
    log "✅ Already at latest known version."
    exit 0
  fi

  log "🚀 Starting upgrade path from $current → ${UPGRADE_PATH[-1]}"

  local i=0
  while [[ $i -lt ${#UPGRADE_PATH[@]} ]]; do
    if attempt_upgrade "${UPGRADE_PATH[$i]}"; then
      ((i++))
    fi
  done

  log "🎉 GitLab successfully upgraded to ${UPGRADE_PATH[-1]}"
}

main
