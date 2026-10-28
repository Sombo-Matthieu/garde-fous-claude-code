#!/bin/bash
# Scan de secrets AVANT tout commit des dépôts de sauvegarde (#670).
# Leçon du 09/07/2026 : une clé sb_secret s'était glissée dans un fichier de
# mémoire et est partie sur GitHub ; le script de scan de l'époque a été perdu
# avec un scratchpad. Celui-ci vit dans le dépôt de config, versionné.
#
# Ce qu'il fait : sur chaque dépôt (défaut : ~/.claude, ~/.claude/projects et le coffre Obsidian),
# il lit les fichiers que `git add -A` prendrait (suivis + non suivis non ignorés)
# et cherche les formes connues de secrets. Aucune exemption par nom d'hôte ou
# « exemple » : le 17/08, une exemption trop large avait désarmé la détection
# d'un mot de passe distant. Un faux positif se lit et se juge ; un vrai secret
# poussé ne se rattrape pas (il faut roter la clé).
#
# Sortie : 0 = « aucun secret — N dépôt(s), M fichier(s) lu(s) » ; 1 = au moins un
# motif trouvé, listé fichier:ligne avec la valeur MASQUÉE (jamais réimprimée en
# clair) ; 2 = « SCAN INCOMPLET » (un dépôt ou un fichier n'a pas pu être lu).
# Usage : bash scan-secrets-memoire.sh [dépôt…]
# Test : bash ~/.claude/hooks/scan-secrets-memoire.test.sh

set -uo pipefail

MOTIFS='sb_secret_[A-Za-z0-9_-]{8,}|sb_publishable_[A-Za-z0-9_-]{8,}|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}|postgres(ql)?://[^:/[:space:]]+:[^@[:space:]]{4,}@|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-ant-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
# Ajout du 2026-10-01, avec la sauvegarde du coffre Obsidian : ses notes parlent de
# Google, de Meta, de l'anti-robot du site… La liste d'origine, écrite pour la
# mémoire de Claude, n'en connaissait aucun. Formes : Google (AIza), Meta (EAA),
# Resend (re_, en DÉBUT de mot seulement), Sentry (sntrys_), Turnstile (0x4AAAA),
# Stripe (sk_live_). ⚠️ Limite connue : un secret SANS forme reconnaissable (jeton
# Pennylane, clé de notifications push, mot de passe en clair) passe toujours.
MOTIFS+='|AIza[0-9A-Za-z_-]{35}|EAA[A-Za-z0-9]{40,}|\bre_[A-Za-z0-9_]{20,}|sntrys_[A-Za-z0-9_=-]{20,}|0x4AAAA[A-Za-z0-9_-]{20,}|sk_live_[A-Za-z0-9]{20,}'

if [ "$#" -gt 0 ]; then
  DEPOTS=("$@")
else
  # Le coffre Obsidian est sauvegardé depuis le 2026-10-01 : scanné par défaut lui aussi.
  DEPOTS=("$HOME/.claude" "$HOME/.claude/projects" "$HOME/Documents/Obsidian Vault")
fi

TROUVES=0
NON_LUS=0    # dépôts ou fichiers que le scan n'a PAS pu lire
LUS_DEPOTS=0
LUS_FICHIERS=0
for depot in "${DEPOTS[@]}"; do
  # « Je n'ai pas pu regarder » n'est pas « rien trouvé » : un dépôt introuvable
  # (coffre déplacé ou renommé) ou une liste de fichiers illisible donne un verdict
  # à part, jamais « aucun secret » (relecture du 01/10).
  if ! git -C "$depot" rev-parse --git-dir >/dev/null 2>&1; then
    echo "✗ $depot : pas un dépôt git — NON LU"
    NON_LUS=$((NON_LUS + 1))
    continue
  fi
  if ! git -C "$depot" ls-files --cached --others --exclude-standard >/dev/null 2>&1; then
    echo "✗ $depot : liste des fichiers illisible — NON LU"
    NON_LUS=$((NON_LUS + 1))
    continue
  fi
  LUS_DEPOTS=$((LUS_DEPOTS + 1))
  # -z : chemins avec espaces ou accents ; on lit fichier par fichier.
  while IFS= read -r -d '' f; do
    [ -f "$depot/$f" ] || continue
    if [ ! -r "$depot/$f" ]; then
      echo "✗ $depot/$f : fichier illisible — NON LU"
      NON_LUS=$((NON_LUS + 1))
      continue
    fi
    LUS_FICHIERS=$((LUS_FICHIERS + 1))
    # Binaire ? grep -I le saute. -n : ligne. -o : seulement le motif, masqué ensuite.
    while IFS= read -r ligne; do
      num="${ligne%%:*}"
      valeur="${ligne#*:}"
      # Seule exemption, étroite : le mot de passe PAR DÉFAUT de la stack Supabase
      # locale (« postgres »), documenté partout, qui ne protège rien. Toute autre
      # URL avec mot de passe reste signalée, quel que soit l'hôte.
      case "$valeur" in postgres://postgres:postgres@|postgresql://postgres:postgres@) continue ;; esac
      masque="${valeur:0:6}…(${#valeur} car.)"
      echo "✗ $depot/$f:$num : $masque"
      TROUVES=$((TROUVES + 1))
    done < <(grep -n -o -E -I "$MOTIFS" "$depot/$f" 2>/dev/null || true)
  done < <(git -C "$depot" ls-files -z --cached --others --exclude-standard 2>/dev/null)
done

if [ "$TROUVES" -gt 0 ]; then
  echo "SECRETS : $TROUVES motif(s) trouvé(s) — NE PAS commiter avant caviardage, puis roter la clé si elle est réelle."
  exit 1
fi
if [ "$NON_LUS" -gt 0 ]; then
  echo "SCAN INCOMPLET : $NON_LUS dépôt(s) ou fichier(s) non lu(s) — NE PAS commiter ce qui n'a pas été lu, corriger le chemin puis relancer."
  exit 2
fi
echo "aucun secret — $LUS_DEPOTS dépôt(s), $LUS_FICHIERS fichier(s) lu(s)"
exit 0
