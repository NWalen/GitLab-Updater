# GitLab Smart Upgrade Script

A self-healing, semi-automated upgrade utility for **self-managed GitLab instances**.  
This script automatically:

- Detects your current GitLab version
- Determines the correct upgrade path (including all mandatory intermediate versions)
- Downloads, installs, and reconfigures each version in order
- Displays a simple progress bar for a clean UX
- Supports optional non-interactive mode for automation
- Logs all actions to `/var/log/gitlab-smart-upgrade.log`

---

## 🚀 Features

✅ Intelligent upgrade path (based on GitLab's required upgrade sequences)  
✅ Auto-detects missing intermediate versions via dpkg error parsing  
✅ Progress bar interface (no noisy terminal output)  
✅ Optional interactive or non-interactive mode  
✅ Built-in logging  
✅ Ubuntu 22.04 (`jammy`) support  
✅ Easy to update when new GitLab versions are released

---

## 📦 Requirements

- Ubuntu 22.04 or compatible Debian-based system
- Root/sudo access
- Existing GitLab **Omnibus** installation

---

## 🛠 Usage

### Step 1: Clone this repo or download the script

```bash
git clone https://github.com/NWalen/GitLab-Updater.git
cd GitLab-Updater
chmod +x Update-Gitlab.sh
sudo ./Update-Gitlab.sh --non-interactive

