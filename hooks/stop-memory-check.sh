#!/bin/bash
# Hook Stop : rappel auto-mémoire non-conditionnel après commit récent.
#
# Pourquoi non-conditionnel : la mémoire Claude Code vit dans
# ~/.claude/projects/<slug>/memory/ qui n'est PAS dans le repo Git du projet.
# Donc impossible de détecter de manière fiable depuis ici si Claude a
# effectivement mis à jour la mémoire pour ce commit. La version précédente
# qui essayait de détecter dans les fichiers du commit produisait des faux
# positifs systématiques (2026-05-14).
#
# Stratégie simplifiée : rappel court après commit < 10 min, marker file
# pour éviter de rappeler 2x pour le même commit.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
MARKER_FILE="$HOME/.claude/hooks/.last-memory-reminder"

# Pas un repo git → silence
if ! git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

# Dernier commit
LAST_COMMIT=$(git -C "$PROJECT_DIR" log -1 --format="%H" 2>/dev/null || echo "")
if [ -z "$LAST_COMMIT" ]; then
  exit 0
fi

# Déjà rappelé pour ce commit → silence
LAST_WARNED=$(cat "$MARKER_FILE" 2>/dev/null || echo "")
if [ "$LAST_WARNED" = "$LAST_COMMIT" ]; then
  exit 0
fi

# Age du commit (en secondes)
COMMIT_TIME=$(git -C "$PROJECT_DIR" log -1 --format="%at" 2>/dev/null)
NOW=$(date +%s)
AGE=$((NOW - COMMIT_TIME))

# Plus de 10 min → trop tard pour rappeler, marque comme vu et silence
if [ "$AGE" -gt 600 ]; then
  echo "$LAST_COMMIT" > "$MARKER_FILE"
  exit 0
fi

# Rappel non-conditionnel : on ne tente plus de détecter automatiquement si
# la mémoire a été touchée (impossible depuis ici, cf header).
echo "$LAST_COMMIT" > "$MARKER_FILE"
cat >&2 <<EOF
Rappel auto-mémoire : commit $(echo "$LAST_COMMIT" | cut -c1-7) fait il y a ${AGE}s.
Vérifie si la mémoire (~/.claude/projects/.../memory/) doit être mise à jour
(nouveau principe validé, projet modifié, pattern non-obvious, décision durable).
Si rien à documenter (refacto pur, fix typo), ignore ce rappel.
EOF
exit 2
