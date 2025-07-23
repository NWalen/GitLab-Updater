#!/bin/bash
set -euo pipefail

# Optional flag
NON_INTERACTIVE=false
[[ "${1:-}" == "--non-interactive" ]] && NON_INTERACTIVE=true

# GitLab official required upgrade path (https://docs.gitlab.com/ee/update/#upgrade-paths)
BASELINE_VERSIONS=(
  # GitLab 15
  "15.0.5"
  "15.1.6"
  "15.4.6"
  "15.11.13"

  # GitLab 16
  "16.0.10"
  "16.1.8"
  "16.2.11"
  "16.3.9"
  "16.7.10"
  "16.11.10"

  # GitLab 17
  "17.1.8"
  "17.3.7"
  "17.4.2"
  "17.5.4"
  "17.8.4"
  "17.11.4"

  # GitLab 18
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

spinner_run() {
  local msg="$1"
  shift
  local cmd=("$@")

  local spin_chars='|/-\'
  local i=0

  printf "\n🔄 %-30s " "$msg"

  "${cmd[@]}" &>/dev/null &
  local pid=$!

  while kill -0 $pid 2>/dev/null; do
    printf "\b${spin_chars:i++%${#spin_chars}:1}"
    sleep 0.1
  done

  wait $pid
  local status=$?

  if [[ $status -eq 0 ]]; then
    printf "\b✅\n"
  else
    printf "\b❌\n"
  fi

  return $status
}

real_download_progress() {
  local version="$1"
  local url="$2"
  local outfile="$3"

  echo -e "\n🔄 Downloading $version..."
  curl -# -L "$url" -o "$outfile"
}

get_current_version() {
  local version
  version=$(sudo gitlab-rake gitlab:env:info 2>/dev/null \
    | grep -m1 '^  Version:' \
    | awk '{print $2}' \
    | cut -d '-' -f1)
  echo "$version"
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

  real_download_progress "$version" "$url" "$file"

  if ! spinner_run "Installing $version" sudo dpkg -i "$file" > /dev/null 2>dpkg_error.log; then
    log "❌ dpkg failed for $version — checking for required intermediate version..."

    local required_version=""
    required_version=$(grep -oP "upgrade to the latest \K[0-9]+\.[0-9]+(?=\.x)" dpkg_error.log || true)

    if [[ -z "$required_version" ]]; then
      required_version=$(grep -oP "It is required to upgrade to \K[0-9]+\.[0-9]+" dpkg_error.log || true)
    fi

    if [[ -n "$required_version" ]]; then
      case "$required_version" in
        "15.0")  required_version="15.0.5" ;;
        "15.1")  required_version="15.1.6" ;;
        "15.4")  required_version="15.4.6" ;;
        "15.11") required_version="15.11.13" ;;
        "16.0")  required_version="16.0.10" ;;
        "16.1")  required_version="16.1.8" ;;
        "16.2")  required_version="16.2.11" ;;
        "16.3")  required_version="16.3.9" ;;
        "16.7")  required_version="16.7.10" ;;
        "16.11") required_version="16.11.10" ;;
        "17.1")  required_version="17.1.8" ;;
        "17.3")  required_version="17.3.7" ;;
        "17.4")  required_version="17.4.2" ;;
        "17.5")  required_version="17.5.4" ;;
        "17.8")  required_version="17.8.4" ;;
        "17.11") required_version="17.11.4" ;;
        "18.0")  required_version="18.0.1" ;;
        "18.2")  required_version="18.2.0" ;;
        *) log "⚠️ Unknown required version: $required_version"; exit 1 ;;
      esac

      log "➕ Inserting required version: $required_version before $version"
      UPGRADE_PATH=("$required_version" "$version" "${UPGRADE_PATH[@]:1}")
    else
      log "❌ Could not determine required intermediate version. Dumping dpkg_error.log:"
      echo "------------ dpkg_error.log -------------"
      cat dpkg_error.log
      echo "-----------------------------------------"
      log "💡 Suggest manually checking upgrade path: https://docs.gitlab.com/ee/update/#upgrade-paths"
      exit 1
    fi
    return 1
  fi

  spinner_run "Reconfiguring $version" sudo gitlab-ctl reconfigure

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
