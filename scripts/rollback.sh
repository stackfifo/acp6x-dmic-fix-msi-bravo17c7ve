#!/usr/bin/env bash
# rollback.sh — Remove ACP6xfix override modules and restore stock kernel modules
#
# Usage:
#   sudo ./rollback.sh
#
# What this script does:
#   1) Removes the override directory:
#        /lib/modules/$(uname -r)/updates/acp6xfix/
#   2) Runs depmod -a so module dependency maps are refreshed
#   3) Regenerates initramfs for the running kernel (if update-initramfs exists)
#   4) Prints a reboot recommendation
#
# Notes:
# - The change takes effect after reboot (recommended).
# - If Secure Boot is enabled and you previously loaded unsigned modules, reboot
#   is the cleanest way to ensure the stock modules are used again.
# - This script is intended for Kali/Debian-style initramfs tooling.
# ----------------------------------------------------------------------

set -euo pipefail

# ---- Colors (safe even if not a TTY) ---------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ---- Require root ----------------------------------------------------
[[ ${EUID:-999} -eq 0 ]] || die "This script must be run as root (use sudo)."

# ---- Variables -------------------------------------------------------
KVER="$(uname -r)"
OVERRIDE_DIR="/lib/modules/${KVER}/updates/acp6xfix"

echo -e "${BOLD}=======================================================${NC}"
echo -e "${BOLD} Rollback — ACP6x DMIC Fix (remove override modules)${NC}"
echo -e "${BOLD}=======================================================${NC}"
echo

info "Running kernel : ${KVER}"
info "Override dir   : ${OVERRIDE_DIR}"
echo

# ---- Nothing to do? --------------------------------------------------
if [[ ! -d "${OVERRIDE_DIR}" ]]; then
  warn "Override directory does not exist — nothing to remove."
  info "System should already be using stock kernel modules."
  exit 0
fi

# ---- Show what will be removed --------------------------------------
info "Modules that will be removed:"
if ls -lh "${OVERRIDE_DIR}"/*.ko >/dev/null 2>&1; then
  ls -lh "${OVERRIDE_DIR}"/*.ko
else
  warn "No .ko files found inside override directory (still removing the directory)."
fi
echo

# ---- Confirmation (interactive only) --------------------------------
# If stdin is not a TTY (e.g. CI), skip confirmation.
if [[ -t 0 ]]; then
  read -rp "Confirm removal of override directory? [y/N] " REPLY
  case "${REPLY}" in
    [yY]) ;;
    *) info "Cancelled."; exit 0 ;;
  esac
  echo
else
  warn "Non-interactive session detected — proceeding without confirmation."
fi

# ---- Remove override -------------------------------------------------
info "Removing ${OVERRIDE_DIR} ..."
rm -rf -- "${OVERRIDE_DIR}"
ok "Override directory removed."

# Remove parent if empty (optional)
PARENT_DIR="$(dirname "${OVERRIDE_DIR}")"
if [[ -d "${PARENT_DIR}" ]] && [[ -z "$(ls -A "${PARENT_DIR}" 2>/dev/null)" ]]; then
  rmdir -- "${PARENT_DIR}" 2>/dev/null && ok "Removed empty parent directory: ${PARENT_DIR}" || true
fi

# ---- Refresh module deps --------------------------------------------
info "Running depmod -a ..."
depmod -a
ok "depmod complete."

# ---- Regenerate initramfs (Debian/Kali) ------------------------------
if command -v update-initramfs >/dev/null 2>&1; then
  info "Updating initramfs for ${KVER} ..."
  update-initramfs -u -k "${KVER}"
  ok "initramfs updated."
else
  warn "update-initramfs not found. If your distro requires initramfs regeneration, do it manually."
fi

echo
ok "Rollback completed."
echo
info "Reboot recommended to fully return to stock modules:"
echo "    sudo systemctl reboot -i"
echo
info "To re-apply the fix later, rebuild/install for the current kernel:"
echo "    sudo ./scripts/rebuild_acp6xfix.sh"