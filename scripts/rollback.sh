#!/usr/bin/env bash
# rollback.sh — Supprime les modules ACP6x patchés et restaure l'état d'origine
#
# Usage : sudo ./rollback.sh
#
# Ce script :
#   1. Supprime le dossier override /lib/modules/$(uname -r)/updates/acp6xfix/
#   2. Exécute depmod -a pour que le noyau reprenne les modules stock
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
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()   { echo -e "${RED}[ERREUR]${NC} $*" >&2; exit 1; }

# ── Vérification root ────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Ce script doit être exécuté en root (sudo)."

# ── Variables ────────────────────────────────────────────────────────
KVER="$(uname -r)"
OVERRIDE_DIR="/lib/modules/${KVER}/updates/acp6xfix"

echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo -e "${BOLD} Rollback — ACP6x DMIC Fix${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo

info "Kernel courant   : ${KVER}"
info "Dossier override : ${OVERRIDE_DIR}"
echo

# ── Vérifier l'existence du dossier override ─────────────────────────
if [[ ! -d "$OVERRIDE_DIR" ]]; then
    warn "Le dossier override n'existe pas — rien à supprimer."
    info "Le système utilise déjà les modules noyau d'origine."
    exit 0
fi

# ── Afficher ce qui va être supprimé ─────────────────────────────────
info "Modules qui seront supprimés :"
ls -lh "$OVERRIDE_DIR"/*.ko 2>/dev/null || echo "    (aucun .ko trouvé)"
echo

# ── Confirmation ─────────────────────────────────────────────────────
read -rp "Confirmer la suppression ? [o/N] " REPLY
case "$REPLY" in
    [oOyY]) ;;
    *)
        info "Annulé."
        exit 0
        ;;
esac
echo

# ── Suppression ──────────────────────────────────────────────────────
info "Suppression de ${OVERRIDE_DIR} ..."
rm -rf "$OVERRIDE_DIR"
ok "Dossier override supprimé."

# Nettoyer le parent s'il est vide
PARENT_DIR="$(dirname "$OVERRIDE_DIR")"
if [[ -d "$PARENT_DIR" ]] && [[ -z "$(ls -A "$PARENT_DIR" 2>/dev/null)" ]]; then
    rmdir "$PARENT_DIR" 2>/dev/null && ok "Dossier parent vide supprimé : ${PARENT_DIR}" || true
fi

# ── depmod ───────────────────────────────────────────────────────────
info "Exécution de depmod -a ..."
depmod -a
ok "depmod terminé — le noyau utilisera les modules stock au prochain boot."

# ── initramfs ────────────────────────────────────────────────────────
if command -v update-initramfs &>/dev/null; then
    info "Mise à jour de l'initramfs ..."
    update-initramfs -u -k "${KVER}"
    ok "initramfs mis à jour."
else
    warn "update-initramfs introuvable — pense à régénérer l'initramfs manuellement."
fi

echo
echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
ok "Rollback terminé."
echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo
info "Redémarre maintenant pour revenir aux modules d'origine :"
echo "    sudo systemctl reboot -i"
echo
info "Pour réappliquer le fix plus tard :"
echo "    sudo ./rebuild_acp6xfix.sh"
