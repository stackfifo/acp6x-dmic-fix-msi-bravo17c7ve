#!/usr/bin/env bash
# rebuild_acp6xfix.sh — Télécharge les sources noyau, applique le patch
#                        DMI "Bravo 17 C7VE", compile les modules ACP6x
#                        et les installe en override.
#
# Usage :
#   sudo ./rebuild_acp6xfix.sh          # tout-en-un
#   sudo ./rebuild_acp6xfix.sh --no-install   # compile seulement
#
# Pré-requis : dkms build-essential linux-headers-$(uname -r)
#              deb-src activé dans /etc/apt/sources.list
# ──────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Couleurs ─────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()   { echo -e "${RED}[ERREUR]${NC} $*" >&2; exit 1; }

# ── Options ──────────────────────────────────────────────────────────
NO_INSTALL=0
if [[ "${1:-}" == "--no-install" ]]; then
    NO_INSTALL=1
fi

# ── Variables ────────────────────────────────────────────────────────
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

echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo -e "${BOLD} ACP6x DMIC Fix — MSI Bravo 17 C7VE (MS-17LN)${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo

info "Kernel courant : ${KVER}"
info "Headers noyau  : ${KDIR}"
echo

# ── pré-requis ──────────────────────────────────────────
[[ -d "$KDIR" ]] || die "Headers noyau introuvables (${KDIR}). Installe : sudo apt install linux-headers-${KVER}"

for cmd in make gcc patch find install; do
    command -v "$cmd" &>/dev/null || die "Commande '${cmd}' introuvable. Installe build-essential."
done

# ── Étape 1 : Télécharger les sources du noyau ──────────────────────
info "Étape 1/5 — Téléchargement des sources noyau Kali ..."
mkdir -p "$SRC_BASE"
cd "$SRC_BASE"

# Si un dossier linux-* existe déjà avec nos sources, on le réutilise
LINUX_DIR="$(find "$SRC_BASE" -maxdepth 1 -type d -name 'linux-*' | sort -V | tail -n 1 || true)"

if [[ -z "$LINUX_DIR" ]] || [[ ! -f "${LINUX_DIR}/sound/soc/amd/yc/acp6x-mach.c" ]]; then
    info "Téléchargement via apt source linux ..."
    apt source linux 2>&1 | tail -5
    LINUX_DIR="$(find "$SRC_BASE" -maxdepth 1 -type d -name 'linux-*' | sort -V | tail -n 1)"
fi

[[ -n "$LINUX_DIR" && -d "$LINUX_DIR" ]] || die "Impossible de trouver le dossier source du noyau."
cd "$LINUX_DIR"
ok "Sources noyau : ${LINUX_DIR}"
echo

# ── Étape 2 : vérifier / appliquer le patch DMI ─────────────────────
info "Étape 2/5 — Application du patch DMI ..."
MACH_FILE="sound/soc/amd/yc/acp6x-mach.c"

if grep -q '"Bravo 17 C7VE"' "$MACH_FILE" 2>/dev/null; then
    ok "Le quirk 'Bravo 17 C7VE' est déjà présent — patch non nécessaire."
else
    if [[ -f "$PATCH_FILE" ]]; then
        # on tente le patch en premier
        if patch --forward -p1 --dry-run < "$PATCH_FILE" &>/dev/null; then
            patch --forward -p1 < "$PATCH_FILE"
            ok "Patch appliqué depuis ${PATCH_FILE}"
        else
            warn "Le patch ne s'applique pas proprement — insertion manuelle."
            # puis l'insertion manuelle
            QUIRK_BLOCK=$'\t{\n\t\t.driver_data = &acp6x_card,\n\t\t.matches = {\n\t\t\tDMI_MATCH(DMI_BOARD_VENDOR, "Micro-Star International Co., Ltd."),\n\t\t\tDMI_MATCH(DMI_PRODUCT_NAME, "Bravo 17 C7VE"),\n\t\t}\n\t},'
            # recherche de la dernière ligne de fermeture de la table
            if grep -n '^	{}' "$MACH_FILE" | tail -1 | grep -q .; then
                LINE=$(grep -n '^	{}' "$MACH_FILE" | tail -1 | cut -d: -f1)
                head -n $((LINE - 1)) "$MACH_FILE" > "${MACH_FILE}.tmp"
                printf '%s\n' "$QUIRK_BLOCK" >> "${MACH_FILE}.tmp"
                tail -n +"$LINE" "$MACH_FILE" >> "${MACH_FILE}.tmp"
                mv "${MACH_FILE}.tmp" "$MACH_FILE"
                ok "Quirk 'Bravo 17 C7VE' inséré manuellement dans la table."
            else
                die "Impossible de trouver la fin de yc_acp_quirk_table[] dans ${MACH_FILE}"
            fi
        fi
    else
        warn "Fichier patch introuvable (${PATCH_FILE}) — insertion manuelle."
        if grep -n '^	{}' "$MACH_FILE" | tail -1 | grep -q .; then
            QUIRK_BLOCK=$'\t{\n\t\t.driver_data = &acp6x_card,\n\t\t.matches = {\n\t\t\tDMI_MATCH(DMI_BOARD_VENDOR, "Micro-Star International Co., Ltd."),\n\t\t\tDMI_MATCH(DMI_PRODUCT_NAME, "Bravo 17 C7VE"),\n\t\t}\n\t},'
            LINE=$(grep -n '^	{}' "$MACH_FILE" | tail -1 | cut -d: -f1)
            head -n $((LINE - 1)) "$MACH_FILE" > "${MACH_FILE}.tmp"
            printf '%s\n' "$QUIRK_BLOCK" >> "${MACH_FILE}.tmp"
            tail -n +"$LINE" "$MACH_FILE" >> "${MACH_FILE}.tmp"
            mv "${MACH_FILE}.tmp" "$MACH_FILE"
            ok "Quirk 'Bravo 17 C7VE' inséré manuellement."
        else
            die "Impossible de trouver la fin de yc_acp_quirk_table[]"
        fi
    fi
fi

# vérification
grep -q '"Bravo 17 C7VE"' "$MACH_FILE" || die "Le quirk n'est pas présent après patch !"
echo

# ── Étape 3 : Compilation des modules ACP6x ─────────────────────────
info "Étape 3/5 — Compilation des modules ACP6x ..."
make -C "$KDIR" M="$PWD/sound/soc/amd/yc" modules -j"$(nproc)" 2>&1 | tail -20
echo

# Vérification
FOUND=0
for mod in "${MODULES[@]}"; do
    if [[ -f "sound/soc/amd/yc/${mod}" ]]; then
        ok "Compilé : ${mod}"
        ((FOUND++))
    else
        warn "Absent  : ${mod}"
    fi
done

[[ $FOUND -gt 0 ]] || die "Aucun module compilé — la compilation a échoué."
echo

# ── Étape 4 : Installation override ─────────────────────────────────
if [[ $NO_INSTALL -eq 1 ]]; then
    info "Mode --no-install : les modules sont compilés dans :"
    echo "    ${LINUX_DIR}/sound/soc/amd/yc/"
    info "Pour installer manuellement :"
    echo "    sudo ${REPO_DIR}/scripts/install_override.sh ${LINUX_DIR}/sound/soc/amd/yc"
    exit 0
fi

[[ $EUID -eq 0 ]] || die "L'installation nécessite les droits root (sudo)."

info "Étape 4/5 — Installation des modules en override ..."
mkdir -p "$OVERRIDE_DIR"

for mod in "${MODULES[@]}"; do
    src="sound/soc/amd/yc/${mod}"
    if [[ -f "$src" ]]; then
        install -m 0644 "$src" "${OVERRIDE_DIR}/"
        ok "Installé : ${OVERRIDE_DIR}/${mod}"
    fi
done

info "Exécution de depmod -a ..."
depmod -a
ok "depmod terminé."
echo

# ── Étape 5 : Mise à jour initramfs ─────────────────────────────────
info "Étape 5/5 — Mise à jour de l'initramfs ..."
if command -v update-initramfs &>/dev/null; then
    update-initramfs -u -k "${KVER}"
    ok "initramfs mis à jour."
else
    warn "update-initramfs introuvable — pense à régénérer l'initramfs manuellement."
fi

echo
echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
ok "Build + installation terminés avec succès !"
echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo
info "Redémarre maintenant :"
echo "    sudo systemctl reboot -i"
echo
info "Après reboot, vérifie :"
echo "    dmesg | grep -i 'Enabling ACP DMIC support'"
echo "    pactl list short sources"
echo "    arecord -l"
echo
info "Rollback si besoin :"
echo "    sudo ${REPO_DIR}/scripts/rollback.sh"
