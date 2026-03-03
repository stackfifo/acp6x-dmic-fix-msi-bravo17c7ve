#!/usr/bin/env bash
# install_override.sh — Install ACP6xfix patched modules as an override
#
# Usage:
#   sudo ./install_override.sh [PATH_TO_KO_DIR]
#
# What this script does:
#   1) Copies the ACP6x-related .ko modules into:
#        /lib/modules/$(uname -r)/updates/acp6xfix/
#   2) Runs depmod -a
#   3) Regenerates initramfs for the running kernel (if update-initramfs exists)
#   4) Prints a reboot recommendation
#
# Notes:
# - This override is kernel-version specific: if uname -r changes, you must reinstall.
# - PipeWire sources may show SUSPENDED when idle; they switch to RUNNING when an app records.
# ----------------------------------------------------------------------

set -euo pipefail

# ---- Colors ----------------------------------------------------------
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

# ---- Kernel / paths --------------------------------------------------
KVER="$(uname -r)"
OVERRIDE_DIR="/lib/modules/${KVER}/updates/acp6xfix"

# ---- Expected modules ------------------------------------------------
MODULES=(
  snd-pci-acp6x.ko
  snd-acp6x-pdm-dma.ko
  snd-soc-acp6x-mach.ko
)

# ---- KO directory (argument or auto-detect) --------------------------
KO_DIR="${1:-}"

auto_detect_ko_dir() {
  # Prefer a source tree that matches the current kernel version if available.
  # Fallback: newest ~/src/linux-*/sound/soc/amd/yc across /home/* users.
  local best=""

  # 1) Try current user first
  for d in "${HOME}/src"/linux-*/sound/soc/amd/yc; do
    [[ -d "${d}" ]] || continue
    if compgen -G "${d}/*.ko" >/dev/null 2>&1; then
      best="${d}"
    fi
  done

  # 2) Try other users (common on multi-user systems)
  if [[ -z "${best}" ]]; then
    for d in /home/*/src/linux-*/sound/soc/amd/yc; do
      [[ -d "${d}" ]] || continue
      if compgen -G "${d}/*.ko" >/dev/null 2>&1; then
        best="${d}"
      fi
    done
  fi

  echo "${best}"
}

if [[ -z "${KO_DIR}" ]]; then
  KO_DIR="$(auto_detect_ko_dir)"
fi

[[ -n "${KO_DIR}" && -d "${KO_DIR}" ]] || die "KO directory not found. Usage: sudo $0 /path/to/sound/soc/amd/yc"

echo -e "${BOLD}=======================================================${NC}"
echo -e "${BOLD} Install override — ACP6x DMIC Fix${NC}"
echo -e "${BOLD}=======================================================${NC}"
echo
info "Running kernel : ${KVER}"
info "KO directory   : ${KO_DIR}"
info "Override dir   : ${OVERRIDE_DIR}"
echo

# ---- Validate presence of modules -----------------------------------
missing=0
for mod in "${MODULES[@]}"; do
  if [[ ! -f "${KO_DIR}/${mod}" ]]; then
    warn "Missing module: ${mod}"
    missing=1
  fi
done

if [[ ${missing} -eq 1 ]]; then
  warn "Some modules are missing. The script will install the ones that exist."
fi

# ---- Copy modules ----------------------------------------------------
mkdir -p "${OVERRIDE_DIR}"

installed=0
for mod in "${MODULES[@]}"; do
  src="${KO_DIR}/${mod}"
  if [[ -f "${src}" ]]; then
    install -m 0644 "${src}" "${OVERRIDE_DIR}/"
    ok "Installed: ${mod}"
    ((installed++))
  fi
done

[[ ${installed} -gt 0 ]] || die "No modules installed — nothing to do."

# ---- depmod ----------------------------------------------------------
info "Running depmod -a ..."
depmod -a
ok "depmod complete."

# ---- initramfs -------------------------------------------------------
if command -v update-initramfs >/dev/null 2>&1; then
  info "Updating initramfs for ${KVER} ..."
  update-initramfs -u -k "${KVER}"
  ok "initramfs updated."
else
  warn "update-initramfs not found — regenerate initramfs manually if your system requires it."
fi

echo
ok "Override install completed (${installed} module(s) in ${OVERRIDE_DIR})."
echo
info "Reboot recommended to ensure the stock modules are replaced by the override:"
echo "    sudo systemctl reboot -i"
echo
info "After reboot, verify:"
echo "    pactl list short sources"
echo "    pactl list sources | sed -n '/Name: alsa_input.*HiFi__Mic1__source/,/Active Port:/p'"
