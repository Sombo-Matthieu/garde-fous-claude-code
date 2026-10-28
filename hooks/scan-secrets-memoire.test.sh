#!/usr/bin/env bash
# Test du scan de secrets (scan-secrets-memoire.sh) — #670.
# Lancer : bash ~/.claude/hooks/scan-secrets-memoire.test.sh
#
# Ce que ce test vérifie, en langage humain :
#   1. un dépôt sans secret → « aucun secret », code 0 ;
#   2. cinq faux secrets de formes différentes, dont un dans un fichier NON suivi
#      (celui que `git add -A` prendrait) → tous trouvés, code 1, valeurs MASQUÉES ;
#   3. un mot de passe de base derrière un hôte « exemple » est trouvé quand même ;
#   4. le mot de passe PAR DÉFAUT de la stack locale (postgres:postgres) est la seule
#      exemption — un autre mot de passe sur le même hôte reste signalé
#      (le 17/08, une exemption « exemple » l'avait laissé passer).
set -u
SCRIPT="${1:-$HOME/.claude/hooks/scan-secrets-memoire.sh}"
ECHECS=0
ok()   { printf '  ✓ %s\n' "$1"; }
ko()   { printf '  ✗ %s\n' "$1"; ECHECS=$((ECHECS+1)); }
contient() { case "$1" in *"$2"*) ok "$3" ;; *) ko "$3 (absent : « $2 »)" ;; esac; }
absent()   { case "$1" in *"$2"*) ko "$3 (présent : « $2 »)" ;; *) ok "$3" ;; esac; }

T="$(mktemp -d)"
git init -q "$T" && git -C "$T" config core.autocrlf false && git -C "$T" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init

echo "1. dépôt sans secret"
echo "rien de sensible ici, sb_secret_ tout court n'est pas une clé" > "$T/propre.md"
git -C "$T" add -A
S=$(bash "$SCRIPT" "$T"); C=$?
contient "$S" "aucun secret" "verdict propre"
[ "$C" -eq 0 ] && ok "code 0" || ko "code $C"

echo "2. cinq faux secrets, un dans un fichier non suivi"
# Les faux secrets sont assemblés en deux morceaux : ce fichier de test ne doit
# pas contenir lui-même un motif complet, sinon le scan réel des dépôts le
# signale (constaté au premier passage, 14/09).
FAUX_SB="sb_secret_""FAUX1234567890abcdefghij"
FAUX_JWT="eyJhbGciOiJIUzI1NiIsInR5""cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlhdCI6MTUxNjIzOTAyMn0"
FAUX_GH="ghp_""FAUXFAUXFAUXFAUXFAUXFAUXFAUXFAUXFAUX12"
FAUX_ANT="sk-ant-""FAUX-abcdefghijklmnopqrstuvwxyz"
FAUX_CLE="-----BEGIN ""RSA PRIVATE KEY-----"
printf '%s\n%s\n%s\n' "$FAUX_SB" "$FAUX_JWT" "$FAUX_GH" > "$T/suivi.md"
git -C "$T" add -A
printf 'clé : %s\n' "$FAUX_ANT" > "$T/non-suivi.md"
echo "$FAUX_CLE" > "$T/cle.md"
S=$(bash "$SCRIPT" "$T"); C=$?
[ "$C" -eq 1 ] && ok "code 1" || ko "code $C"
contient "$S" "5 motif(s)" "cinq motifs trouvés"
contient "$S" "non-suivi.md" "le fichier non suivi est scanné"
absent "$S" "$FAUX_SB" "la valeur n'est jamais réimprimée en clair"
contient "$S" "sb_sec…" "valeur masquée"

echo "3. mot de passe de base derrière un hôte « exemple »"
rm -f "$T"/*.md
FAUX_URL="postgres""ql://postgres:MotDePasseFaux@db.exemple-inexistant.net:5432/postgres"
echo "$FAUX_URL" > "$T/db.md"
git -C "$T" add -A
S=$(bash "$SCRIPT" "$T"); C=$?
[ "$C" -eq 1 ] && ok "trouvé malgré l'hôte « exemple »" || ko "raté : code $C"

echo "4. mot de passe PAR DÉFAUT de la stack locale (postgres) → seule exemption, pas un secret"
rm -f "$T"/*.md
FAUX_LOCAL="postgres""ql://postgres:postgres@127.0.0.1:54322/postgres"
echo "$FAUX_LOCAL" > "$T/local.md"
git -C "$T" add -A
S=$(bash "$SCRIPT" "$T"); C=$?
[ "$C" -eq 0 ] && ok "défaut local ignoré" || ko "faux positif sur le défaut local : $S"
FAUX_LOCAL2="postgres""ql://postgres:PasLeDefaut@127.0.0.1:54322/postgres"
echo "$FAUX_LOCAL2" > "$T/local.md"
git -C "$T" add -A
S=$(bash "$SCRIPT" "$T"); C=$?
[ "$C" -eq 1 ] && ok "un autre mot de passe sur le même hôte reste signalé" || ko "exemption trop large : code $C"

echo "5. clés des services dont parlent les notes du coffre (Google, Meta, Resend, Sentry, Turnstile, Stripe)"
# Ajouté le 01/10 avec la sauvegarde du coffre Obsidian : la liste des formes avait
# été écrite pour la mémoire de Claude et ne connaissait aucun de ces services.
rm -f "$T"/*.md
FAUX_GOOGLE="AIza""FAUXfauxFAUXfauxFAUXfauxFAUXfauxFAU"
FAUX_META="EAA""FAUXfauxFAUXfauxFAUXfauxFAUXfauxFAUXfauxFAUX"
FAUX_RESEND="re_""FAUXfaux1234_FAUXfaux5678"
FAUX_SENTRY="sntrys_""FAUXfauxFAUXfauxFAUXfaux"
FAUX_TURNSTILE="0x4AAAA""FAUXfauxFAUXfauxFAUXfaux"
FAUX_STRIPE="sk_live_""FAUXfauxFAUXfauxFAUXfaux"
printf '%s\n' "clé Google : $FAUX_GOOGLE" "jeton Meta : $FAUX_META" "Resend : $FAUX_RESEND" "Sentry : $FAUX_SENTRY" "Turnstile : $FAUX_TURNSTILE" "Stripe : $FAUX_STRIPE" > "$T/services.md"
# Un mot qui contient « re_ » au milieu n'est pas une clé Resend.
echo "before_tool_use_long_identifier_name_tres_long" > "$T/pas-une-cle.md"
git -C "$T" add -A
S=$(bash "$SCRIPT" "$T"); C=$?
[ "$C" -eq 1 ] && ok "code 1" || ko "code $C"
contient "$S" "6 motif(s)" "les six formes sont trouvées"
absent "$S" "pas-une-cle.md" "un identifiant contenant « re_ » au milieu n'est pas signalé"

echo "6. dépôt introuvable → SCAN INCOMPLET, jamais « aucun secret »"
rm -f "$T"/*.md
git -C "$T" add -A
S=$(bash "$SCRIPT" "$T" "$T/coffre-renomme-inexistant"); C=$?
[ "$C" -eq 2 ] && ok "code 2" || ko "code $C"
contient "$S" "SCAN INCOMPLET" "verdict : scan incomplet"
absent "$S" "aucun secret" "pas de verdict vert quand un dépôt n'a pas été lu"

echo "7. le verdict vert dit ce qui a été lu"
echo "une note sans rien de sensible" > "$T/note.md"
git -C "$T" add -A
S=$(bash "$SCRIPT" "$T"); C=$?
[ "$C" -eq 0 ] && ok "code 0" || ko "code $C"
contient "$S" "aucun secret — 1 dépôt(s), 1 fichier(s) lu(s)" "décompte des dépôts et des fichiers lus"

rm -rf "$T"
echo
if [ "$ECHECS" -eq 0 ]; then echo "TOUT VERT"; exit 0; else echo "$ECHECS ÉCHEC(S)"; exit 1; fi
