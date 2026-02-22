#!/usr/bin/env bash
# install_override.sh — Installe les modules ACP6x patchés en override
# Usage : sudo ./install_override.sh [chemin_vers_dossier_ko]
#
# Ce script :
#   1. Copie les 3 modules .ko compilés dans /lib/modules/$(uname -r)/updates/acp6xfix/
#   2. Exécute depmod -a
#   3. Regénère l'initramfs
#   4. Propose le reboot
#
# Doit être exécuté en root (sudo).
# ──────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Couleurs ─────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()   { echo -e "${RED}[ERREUR]${NC} $*" >&2; exit 1; }

# ── Vérification root ────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Ce script doit être exécuté en root (sudo)."

# ── Paramètres ───────────────────────────────────────────────────────
KVER="$(uname -r)"
OVERRIDE_DIR="/lib/modules/${KVER}/updates/acp6xfix"

# Dossier contenant les .ko compilés (argument ou auto-détection)
KO_DIR="${1:-}"

if [[ -z "$KO_DIR" ]]; then
    # Tente une détection automatique dans ~/src/linux-*/sound/soc/amd/yc
    for d in /home/*/src/linux-*/sound/soc/amd/yc; do
        if compgen -G "${d}/*.ko" >/dev/null 2>&1; then
            KO_DIR="$d"
            break
        fi
    done
fi

[[ -n "$KO_DIR" && -d "$KO_DIR" ]] || die "Dossier des .ko introuvable. Usage : $0 /chemin/vers/sound/soc/amd/yc"

# ── Liste des modules attendus ───────────────────────────────────────
MODULES=(
    snd-pci-acp6x.ko
    snd-acp6x-pdm-dma.ko
    snd-soc-acp6x-mach.ko
)

info "Kernel courant   : ${KVER}"
info "Dossier sources  : ${KO_DIR}"
info "Dossier override : ${OVERRIDE_DIR}"
echo

# ── Vérifier que les .ko existent ────────────────────────────────────
MISSING=0
for mod in "${MODULES[@]}"; do
    if [[ ! -f "${KO_DIR}/${mod}" ]]; then
        warn "Module manquant : ${mod}"
        MISSING=1
    fi
done

if [[ $MISSING -eq 1 ]]; then
    warn "Certains modules sont absents. On installe ceux qui existent."
fi

# ── Copier les modules ───────────────────────────────────────────────
mkdir -p "$OVERRIDE_DIR"

INSTALLED=0
for mod in "${MODULES[@]}"; do
    src="${KO_DIR}/${mod}"
    if [[ -f "$src" ]]; then
        install -m 0644 "$src" "${OVERRIDE_DIR}/"
        ok "Installé : ${mod}"
        ((INSTALLED++))
    fi
done

[[ $INSTALLED -gt 0 ]] || die "Aucun module installé — rien à faire."

# ── depmod ───────────────────────────────────────────────────────────
info "Exécution de depmod -a ..."
depmod -a
ok "depmod terminé."

# ── initramfs ────────────────────────────────────────────────────────
if command -v update-initramfs &>/dev/null; then
    info "Mise à jour de l'initramfs ..."
    update-initramfs -u -k "${KVER}"
    ok "initramfs mis à jour."
else
    warn "update-initramfs introuvable — pense à régénérer l'initramfs manuellement."
fi

echo
ok "Installation terminée (${INSTALLED} module(s) dans ${OVERRIDE_DIR})."
echo
info "Redémarre maintenant pour activer le fix :"
echo "    sudo systemctl reboot -i"
echo
info "Après reboot, vérifie avec :"
echo "    dmesg | grep -i 'Enabling ACP DMIC support'"
echo "    pactl list short sources"
