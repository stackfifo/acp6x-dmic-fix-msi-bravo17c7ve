#!/usr/bin/env bash
# rebuild_acp6xfix.sh — Download Kali kernel sources, apply the MSI Bravo 17 C7VE
#                       ACP6x DMIC DMI quirk patch, build ACP6x modules, and
#                       optionally install them as an override.
#
# Usage:
#   sudo ./rebuild_acp6xfix.sh               # all-in-one: download → patch → build → install
#   sudo ./rebuild_acp6xfix.sh --no-install  # download → patch → build only
#
# Requirements:
#   - build-essential, dkms (optional), linux-headers-$(uname -r), dpkg-dev
#   - deb-src enabled in /etc/apt/sources.list (needed for: apt source linux)
#
# Notes:
#   - The override is installed under /lib/modules/$(uname -r)/updates/acp6xfix/
#     and is therefore specific to the currently running kernel version.
#   - After a kernel update (uname -r changes), you must re-run this script.
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

# ---- Options ---------------------------------------------------------
NO_INSTALL=0
if [[ "${1:-}" == "--no-install" ]]; then
  NO_INSTALL=1
elif [[ -n "${1:-}" ]]; then
  die "Unknown option: ${1}. Supported: --no-install"
fi

# ---- Require root early (script uses apt source + install) -----------
[[ ${EUID:-999} -eq 0 ]] || die "This script must be run as root (use sudo)."

# ---- Variables -------------------------------------------------------
KVER="$(uname -r)"
KDIR="/lib/modules/${KVER}/build"
SRC_BASE="${HOME}/src"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
PATCH_FILE="${REPO_DIR}/patches/0001-msi-bravo17-c7ve-add-dmi-quirk-acp6x.patch"
OVERRIDE_DIR="/lib/modules/${KVER}/updates/acp6xfix"

MODULES=(
  snd-pci-acp6x.ko
  snd-acp6x-pdm-dma.ko
  snd-soc-acp6x-mach.ko
)

echo -e "${BOLD}=======================================================${NC}"
echo -e "${BOLD} ACP6x DMIC Fix — MSI Bravo 17 C7VE (MS-17LN)${NC}"
echo -e "${BOLD}=======================================================${NC}"
echo
info "Running kernel : ${KVER}"
info "Kernel headers : ${KDIR}"
echo

# ---- Preconditions ---------------------------------------------------
[[ -d "${KDIR}" ]] || die "Kernel headers not found (${KDIR}). Install: sudo apt install linux-headers-${KVER}"

for cmd in make gcc patch find install; do
  command -v "${cmd}" >/dev/null 2>&1 || die "Missing command '${cmd}'. Install: sudo apt install build-essential"
done

command -v apt >/dev/null 2>&1 || die "apt not found (unexpected on Kali/Debian)."

# ---- Step 1: Download kernel sources --------------------------------
info "Step 1/5 — Fetching Kali kernel sources (apt source linux) ..."
mkdir -p "${SRC_BASE}"
cd "${SRC_BASE}"

# Reuse an existing linux-* directory if present and looks correct
LINUX_DIR="$(find "${SRC_BASE}" -maxdepth 1 -type d -name 'linux-*' | sort -V | tail -n 1 || true)"

if [[ -z "${LINUX_DIR}" ]] || [[ ! -f "${LINUX_DIR}/sound/soc/amd/yc/acp6x-mach.c" ]]; then
  info "Downloading sources via: apt source linux"
  # apt source prints a lot; keep normal output but don't hide errors.
  apt source linux
  LINUX_DIR="$(find "${SRC_BASE}" -maxdepth 1 -type d -name 'linux-*' | sort -V | tail -n 1)"
fi

[[ -n "${LINUX_DIR}" && -d "${LINUX_DIR}" ]] || die "Could not locate extracted kernel source directory under ${SRC_BASE}."
cd "${LINUX_DIR}"
ok "Kernel sources: ${LINUX_DIR}"
echo

# ---- Step 2: Apply/ensure DMI quirk ---------------------------------
info "Step 2/5 — Applying DMI quirk patch ..."
MACH_FILE="sound/soc/amd/yc/acp6x-mach.c"

[[ -f "${MACH_FILE}" ]] || die "Missing file: ${MACH_FILE}"

if grep -q '"Bravo 17 C7VE"' "${MACH_FILE}" 2>/dev/null; then
  ok "Quirk already present: Bravo 17 C7VE (nothing to do)."
else
  if [[ -f "${PATCH_FILE}" ]]; then
    # Try patch(1) first (works if PATCH_FILE is a unified diff)
    if patch --forward -p1 --dry-run < "${PATCH_FILE}" >/dev/null 2>&1; then
      patch --forward -p1 < "${PATCH_FILE}"
      ok "Patch applied: ${PATCH_FILE}"
    else
      warn "Patch does not apply cleanly with patch(1). Falling back to safe manual insertion."
      # Manual insertion just before the final "{}" sentinel in yc_acp_quirk_table[]
      QUIRK_BLOCK=$'\t{\n\t\t.driver_data = &acp6x_card,\n\t\t.matches = {\n\t\t\tDMI_MATCH(DMI_BOARD_VENDOR, "Micro-Star International Co., Ltd."),\n\t\t\tDMI_MATCH(DMI_PRODUCT_NAME, "Bravo 17 C7VE"),\n\t\t}\n\t},'
      LINE="$(grep -n $'^\t{}' "${MACH_FILE}" | tail -1 | cut -d: -f1 || true)"
      [[ -n "${LINE}" ]] || die "Could not find end-of-table sentinel (\"\\t{}\") in ${MACH_FILE}"
      head -n $((LINE - 1)) "${MACH_FILE}" > "${MACH_FILE}.tmp"
      printf '%s\n' "${QUIRK_BLOCK}" >> "${MACH_FILE}.tmp"
      tail -n +"${LINE}" "${MACH_FILE}" >> "${MACH_FILE}.tmp"
      mv "${MACH_FILE}.tmp" "${MACH_FILE}"
      ok "Inserted DMI quirk block for Bravo 17 C7VE."
    fi
  else
    warn "Patch file not found: ${PATCH_FILE}. Falling back to manual insertion."
    QUIRK_BLOCK=$'\t{\n\t\t.driver_data = &acp6x_card,\n\t\t.matches = {\n\t\t\tDMI_MATCH(DMI_BOARD_VENDOR, "Micro-Star International Co., Ltd."),\n\t\t\tDMI_MATCH(DMI_PRODUCT_NAME, "Bravo 17 C7VE"),\n\t\t}\n\t},'
    LINE="$(grep -n $'^\t{}' "${MACH_FILE}" | tail -1 | cut -d: -f1 || true)"
    [[ -n "${LINE}" ]] || die "Could not find end-of-table sentinel (\"\\t{}\") in ${MACH_FILE}"
    head -n $((LINE - 1)) "${MACH_FILE}" > "${MACH_FILE}.tmp"
    printf '%s\n' "${QUIRK_BLOCK}" >> "${MACH_FILE}.tmp"
    tail -n +"${LINE}" "${MACH_FILE}" >> "${MACH_FILE}.tmp"
    mv "${MACH_FILE}.tmp" "${MACH_FILE}"
    ok "Inserted DMI quirk block for Bravo 17 C7VE."
  fi
fi

grep -q '"Bravo 17 C7VE"' "${MACH_FILE}" || die "Quirk not found after patch/insertion."
echo

# ---- Step 3: Build ACP6x modules ------------------------------------
info "Step 3/5 — Building ACP6x modules ..."
make -C "${KDIR}" M="$PWD/sound/soc/amd/yc" modules -j"$(nproc)"
echo

FOUND=0
for mod in "${MODULES[@]}"; do
  if [[ -f "sound/soc/amd/yc/${mod}" ]]; then
    ok "Built: ${mod}"
    ((FOUND++))
  else
    warn "Missing after build: ${mod}"
  fi
done

[[ ${FOUND} -gt 0 ]] || die "No modules were built — build failed."
echo

# ---- Step 4: Install override (optional) -----------------------------
if [[ ${NO_INSTALL} -eq 1 ]]; then
  info "--no-install mode: modules are built under:"
  echo "    ${LINUX_DIR}/sound/soc/amd/yc/"
  info "To install later, run:"
  echo "    sudo ${REPO_DIR}/scripts/install_override.sh"
  exit 0
fi

info "Step 4/5 — Installing override modules ..."
mkdir -p "${OVERRIDE_DIR}"

for mod in "${MODULES[@]}"; do
  src="sound/soc/amd/yc/${mod}"
  if [[ -f "${src}" ]]; then
    install -m 0644 "${src}" "${OVERRIDE_DIR}/"
    ok "Installed: ${OVERRIDE_DIR}/${mod}"
  fi
done

info "Running depmod -a ..."
depmod -a
ok "depmod complete."
echo

# ---- Step 5: Update initramfs ---------------------------------------
info "Step 5/5 — Updating initramfs ..."
if command -v update-initramfs >/dev/null 2>&1; then
  update-initramfs -u -k "${KVER}"
  ok "initramfs updated."
else
  warn "update-initramfs not found — regenerate initramfs manually if your system requires it."
fi

echo
echo -e "${BOLD}=======================================================${NC}"
ok "Build + install completed successfully."
echo -e "${BOLD}=======================================================${NC}"
echo
info "Reboot recommended:"
echo "    sudo systemctl reboot -i"
echo
info "After reboot, verify:"
echo "    pactl list short sources"
echo "    pactl list sources | sed -n '/Name: alsa_input.*HiFi__Mic1__source/,/Active Port:/p'"
echo
info "Rollback (remove override):"
echo "    sudo ${REPO_DIR}/scripts/rollback.sh"