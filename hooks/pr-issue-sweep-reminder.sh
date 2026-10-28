#!/bin/bash
# Hook PostToolUse : balayage "trous non consignés" au moment d'ouvrir une PR.
#
# Pourquoi : la classification des issues (theme:/prio:) est verrouillée, mais le
# maillon AMONT — "est-ce que tout ce qui méritait une issue en est devenu une ?"
# — reste un jugement faillible et invisible. Pire : l'auteur est le pire
# détecteur de ses propres trous (les angles morts d'écriture = angles morts de
# relecture). Donc ce hook NE se contente pas de me rappeler de réfléchir : il
# PRÉ-MÂCHE le diff et me met sous le nez des signaux objectifs, sortant la
# détection de mon seul jugement d'auteur.
#
# Calibrage : on commence SERRÉ (marqueurs à faible faux-positif). Un hook qui
# crie au loup finit ignoré (leçon post-commit-memory-reminder, mai 2026). Les
# hits sont présentés "à statuer", pas "à corriger".
#
# Déclenché à la CRÉATION de la PR (contexte frais), via "if": "Bash(gh pr create *)".

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

# Filtrage INTERNE : le "if" de settings.json ne filtre pas réellement (vérifié
# 2026-06-25 : les hooks PostToolUse Bash tournent sur TOUTE commande). On lit
# donc la commande déclenchante depuis le JSON stdin et on sort en silence si ce
# n'est pas une création de PR — sinon ce rappel bruiterait à chaque commande.
INPUT=$(cat)
CMD=$(echo "$INPUT" | "$(command -v python3 || command -v python)" -c "import json,sys; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "$INPUT")
case "$CMD" in
  *"gh pr create"*) : ;;   # création de PR → on continue
  *) exit 0 ;;             # tout le reste → silence
esac

# Échappe une chaîne pour insertion dans une valeur JSON (sur une ligne)
json_escape() {
  echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ' | tr '\t' ' '
}

SIGNALS=""

if git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1 \
   && git -C "$PROJECT_DIR" rev-parse --verify main >/dev/null 2>&1; then

  FILES=$(git -C "$PROJECT_DIR" diff --name-only main...HEAD 2>/dev/null || echo "")
  # Lignes AJOUTÉES par la branche (on ignore l'en-tête +++ )
  ADDED=$(git -C "$PROJECT_DIR" diff main...HEAD 2>/dev/null | grep '^+' | grep -v '^+++' || true)

  # 1) Notes "à finir plus tard" laissées dans le code
  TODOS=$(echo "$ADDED" | grep -ioE '(TODO|FIXME|HACK|XXX)[^"]{0,60}' | head -3 | tr '\n' ';' || true)
  [ -n "$TODOS" ] && SIGNALS="${SIGNALS}• Notes laissées dans le code : ${TODOS} → consigner en issue ou résoudre. "

  # 2) catch d'erreur ajouté sans capture Sentry (heuristique grossière mais sobre)
  CATCH_N=$(echo "$ADDED" | grep -cE 'catch[[:space:]]*\(' || true)
  SENTRY_N=$(echo "$ADDED" | grep -c 'captureException' || true)
  if [ "${CATCH_N:-0}" -gt 0 ] && [ "${SENTRY_N:-0}" -eq 0 ]; then
    SIGNALS="${SIGNALS}• ${CATCH_N} bloc(s) catch ajouté(s), 0 Sentry.captureException → vérifier (règle observabilité). "
  fi

  # 3) Migration BDD touchée sans mise à jour des types TS
  MIG_N=$(echo "$FILES" | grep -c 'supabase/migrations/' || true)
  DBT_N=$(echo "$FILES" | grep -c 'src/types/database.ts' || true)
  if [ "${MIG_N:-0}" -gt 0 ] && [ "${DBT_N:-0}" -eq 0 ]; then
    SIGNALS="${SIGNALS}• Migration(s) modifiée(s) sans toucher src/types/database.ts → types peut-être désync. "
  fi

  # 4) PR avec du code source mais aucun test touché
  SRC_N=$(echo "$FILES" | grep -E '^src/.*\.(ts|tsx)$' | grep -vE '\.(test|spec)\.' || true)
  TEST_N=$(echo "$FILES" | grep -cE '(\.(test|spec)\.|/__tests__/|\.pg\.sql$)' || true)
  if [ -n "$SRC_N" ] && [ "${TEST_N:-0}" -eq 0 ]; then
    SIGNALS="${SIGNALS}• Code source modifié, aucun test touché → règle 'chaque feature a un test'. "
  fi
fi

if [ -n "$SIGNALS" ]; then
  DETECTED="Signaux automatiques détectés dans le diff (à STATUER, pas forcément à corriger) : ${SIGNALS}"
else
  DETECTED="Aucun signal automatique dans le diff. "
fi

MSG="RAPPEL balayage fin-de-PR — ${DETECTED}EN PLUS du mécanique ci-dessus (qui ne capte pas les trous de raisonnement) : qu'as-tu vu passer pendant ce chantier qui méritait une issue et que tu n'as PAS créé ? (dette, raccourci assumé, trou hors-scope, invariant métier non garanti). Chaque trou → gh issue create avec theme:* + prio:* (cf. reference_labels_issues, prio à valider avec Matthieu). Si rien → l'énoncer explicitement."

ESCAPED=$(json_escape "$MSG")

cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"${ESCAPED}"}}
EOF
exit 0
