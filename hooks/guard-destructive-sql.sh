#!/bin/bash
# Hook PreToolUse : garde anti-ecritures SQL destructrices.
#
# Bloque AVANT execution (exit 2) tout DELETE/UPDATE sans WHERE, TRUNCATE, ou
# DROP TABLE/SCHEMA/DATABASE lance par Claude via le MCP Supabase
# (execute_sql / apply_migration) ou psql direct. Un hook PreToolUse qui sort
# en code 2 bloque MEME en mode bypassPermissions : c'est le seul mecanisme qui
# transforme les regles-voeux (feedback_jamais_delete_global) en blocage reel.
# Origine : le 2026-05-11, un bug applicatif a efface une semaine de commandes
# en production. Ce garde empeche l'agent de reproduire ce type de geste.
#
# Analyse fine deleguee a python (guard-destructive-sql.py), calquee sur la
# convention des autres hooks (parsing JSON via python, pas jq).
#
# Fail-CLOSED : si python casse ou est absent ALORS qu'un mot-cle destructeur
# est present, on BLOQUE plutot que de laisser passer un wipe potentiel
# (jamais de faux filet silencieux -- cf. feedback_outil_consommateur).

set -uo pipefail

INPUT=$(cat)

# Pre-filtre rapide : aucun mot-cle destructeur dans l'appel -> laisser passer
# sans meme lancer python (la immense majorite des appels : SELECT, INSERT...).
if ! printf '%s' "$INPUT" | grep -iqE 'delete|truncate|drop|update'; then
  exit 0
fi

PY="$(command -v python3 || command -v python)"
printf '%s' "$INPUT" | "${PY:-python}" "$HOME/.claude/hooks/guard-destructive-sql.py"
rc=$?

if [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ]; then
  exit "$rc"
fi

# rc != 0 et != 2 : python indisponible/en erreur AVEC un mot-cle destructeur
# present -> fail-closed (bloquer).
cat >&2 <<'EOF'

⛔ [garde SQL] Analyse impossible (python indisponible ou erreur interne) alors
   qu'un mot-cle destructeur (DELETE/TRUNCATE/DROP/UPDATE) est present dans l'appel.
   -> Blocage par securite (fail-closed). Verifie ~/.claude/hooks/guard-destructive-sql.py
   et que `python3` (ou `python`) est dans le PATH du hook.
EOF
exit 2
