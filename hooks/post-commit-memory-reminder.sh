#!/bin/bash
# Hook PostToolUse : rappel auto-mémoire non-conditionnel après git commit.
#
# Pourquoi non-conditionnel : la mémoire Claude Code vit dans
# ~/.claude/projects/<slug>/memory/ qui n'est PAS dans le repo Git du projet.
# Donc impossible de détecter de manière fiable depuis ici si Claude a
# effectivement mis à jour la mémoire pour ce commit. La version précédente
# qui essayait de détecter dans les fichiers du commit produisait des faux
# positifs systématiques (corrigé 2026-05-14).
#
# Différent de stop-memory-check.sh qui agit en fin de session — celui-ci
# alerte Claude en plein travail pour ne pas accumuler les commits sans MAJ.
#
# Filtré via "if": "Bash(git commit *)" dans settings.json, donc ne s'exécute
# que pour des commandes git commit.

set -euo pipefail

# Filtrage INTERNE : la clé "if" de settings.json ne filtre pas réellement
# (vérifié 2026-06-25 : les hooks PostToolUse Bash tournent sur TOUTE commande).
# On lit donc la commande déclenchante dans le JSON stdin et on sort en silence
# si ce n'est pas un git commit — sinon ce rappel bruite à chaque commande.
INPUT=$(cat)
PY="$(command -v python3 || command -v python || echo python)"
CMD=$(echo "$INPUT" | "$PY" -c "import json,sys; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "$INPUT")
case "$CMD" in
  *"git commit"*) : ;;   # commit → on continue
  *) exit 0 ;;          # tout le reste → silence
esac

# Dossier où la commande a tourné (champ "cwd" du JSON). CLAUDE_PROJECT_DIR pointe
# le dossier PRINCIPAL du projet : depuis un worktree, le rappel citait le dernier
# commit d'une autre session au lieu de celui qui venait d'être créé.
CWD=$(echo "$INPUT" | "$PY" -c "import json,sys; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "")
PROJECT_DIR="${CWD:-${CLAUDE_PROJECT_DIR:-$PWD}}"

# Pas un repo git → silence
if ! git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

# Dernier commit (celui qui vient d'être créé)
LAST_COMMIT=$(git -C "$PROJECT_DIR" log -1 --format="%H" 2>/dev/null || echo "")
if [ -z "$LAST_COMMIT" ]; then
  exit 0
fi

SHORT_HASH=$(echo "$LAST_COMMIT" | cut -c1-7)
FILES_CHANGED=$(git -C "$PROJECT_DIR" show --name-only --format="" "$LAST_COMMIT" 2>/dev/null || echo "")

# Échapper backslash et guillemets, tronquer pour rester JSON-safe et concis
FILES_ESCAPED=$(echo "$FILES_CHANGED" | tr '\n' ',' | sed 's/,$//' | sed 's/\\/\\\\/g; s/"/\\"/g' | head -c 300)

cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"RAPPEL feedback_maj_memoire — Commit ${SHORT_HASH} créé (fichiers : ${FILES_ESCAPED}). Avant d'enchaîner sur autre chose, vérifier si la mémoire Claude Code doit être mise à jour pour refléter ce commit (nouveau principe validé, projet modifié, pattern non-obvious, décision durable). Si rien à documenter (refacto pur, fix typo), ignorer ce rappel."}}
EOF
exit 0
