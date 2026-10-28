#!/usr/bin/env bash
# Test du compteur de réexplications (lisibilite-compteur.py).
# Lancer : bash ~/.claude/hooks/lisibilite-compteur.test.sh [chemin du script à tester]
# Le 2e argument optionnel sert au test de mutation (script modifié = le test doit rougir).
#
# Ce que ce test vérifie, en langage humain :
#   1. un message normal n'est PAS compté ;
#   2. « c'est quoi … » est compté, avec le message précédent de Claude retrouvé ;
#   3. « ?? » en tête de message est compté à coup sûr ;
#   4. au démarrage d'une session, avec 2 cas sur les 5 dernières sessions,
#      l'alarme sonne des DEUX côtés (ligne pour Claude + message visible pour Matthieu) ;
#   5. quand les 2 cas sortent de la fenêtre des 5 sessions, silence — mais le battement reste ;
#   6. après acquittement, les anciens cas ne comptent plus ;
#   7. la sortie reste du JSON valide, même sans rien en entrée ;
#   8. « cest quoi » et « c est quoi », écrits sans apostrophe comme Matthieu les tape, sont comptés
#      (le 05/10, le compteur avait manqué 5 vraies demandes sur 7 pour cette raison) ;
#   9. un message écrit par l'application (fin d'une tâche de fond) n'est JAMAIS compté,
#      même s'il contient « pas compris » (faux cas du 05/10).
set -u
export PYTHONIOENCODING=utf-8
SCRIPT="${1:-$HOME/.claude/hooks/lisibilite-compteur.py}"
PY="$(command -v python3 || command -v python)"
# Chemins au format C:/... : Python sous Windows n'ouvre pas les chemins /tmp/... de Git Bash.
TMPDIR_POSIX="$(mktemp -d)"
if command -v cygpath >/dev/null 2>&1; then export FG_LISIBILITE_DIR="$(cygpath -m "$TMPDIR_POSIX")"; else export FG_LISIBILITE_DIR="$TMPDIR_POSIX"; fi
TRANSCRIPT="$FG_LISIBILITE_DIR/transcript.jsonl"
ECHECS=0

ok()   { printf '  ✓ %s\n' "$1"; }
ko()   { printf '  ✗ %s\n' "$1"; ECHECS=$((ECHECS+1)); }
verif(){ if [ "$1" = "$2" ]; then ok "$3"; else ko "$3 (attendu: $2, obtenu: $1)"; fi; }

# transcription factice : un message de Claude plein de jargon
printf '%s\n' '{"type":"user","message":{"content":"bonjour"}}' > "$TRANSCRIPT"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"La PR outils est mergée, le hook Stop est armé sur le worktree."}]}}' >> "$TRANSCRIPT"

prompt() { # $1 session, $2 message
  printf '{"hook_event_name":"UserPromptSubmit","session_id":"%s","cwd":"C:/Users/utilisateur/frites-and-go/.claude/worktrees/x","transcript_path":"%s","prompt":"%s"}' "$1" "$TRANSCRIPT" "$2" | "$PY" "$SCRIPT"
}
demarrage() {
  printf '{"hook_event_name":"SessionStart","session_id":"nouvelle","cwd":"C:/Users/utilisateur/frites-and-go"}' | "$PY" "$SCRIPT"
}
nb_journal() { if [ -f "$FG_LISIBILITE_DIR/journal.jsonl" ]; then wc -l < "$FG_LISIBILITE_DIR/journal.jsonl" | tr -d ' '; else echo 0; fi; }

echo "1. message normal"
prompt s1 "on merge la PR et on passe au stock" > /dev/null
verif "$(nb_journal)" 0 "rien journalisé"

echo "2. c'est quoi"
SORTIE=$(prompt s2 "c'est quoi le niveau suivant")
verif "$(nb_journal)" 1 "1 cas journalisé"
case "$SORTIE" in *"journalis"*) ok "Claude est prévenu" ;; *) ko "Claude n'est pas prévenu : $SORTIE" ;; esac
case "$(cat "$FG_LISIBILITE_DIR/journal.jsonl")" in *"PR outils"*) ok "message précédent de Claude retrouvé" ;; *) ko "message précédent absent" ;; esac

echo "3. signal volontaire ??"
prompt s3 "?? tu peux détailler" > /dev/null
verif "$(nb_journal)" 2 "2 cas journalisés"

echo "4. deux cas sur cinq sessions → alarme des deux côtés"
prompt s4 "ok" > /dev/null
prompt s5 "ok" > /dev/null
SORTIE=$(demarrage)
case "$SORTIE" in *"SEUIL ATTEINT"*) ok "ligne rouge pour Claude" ;; *) ko "pas de ligne rouge : $SORTIE" ;; esac
case "$SORTIE" in *"systemMessage"*) ok "message visible pour Matthieu" ;; *) ko "pas de message visible" ;; esac
SORTIE=$(prompt s5 "ok")
case "$SORTIE" in *"SEUIL ATTEINT"*) ok "rappel à chaque message tant que le seuil est atteint" ;; *) ko "pas de rappel au message" ;; esac

echo "5. les cas sortent de la fenêtre → silence, battement conservé"
for s in s6 s7 s8 s9; do prompt "$s" "ok" > /dev/null; done
SORTIE=$(demarrage)
case "$SORTIE" in *"SEUIL ATTEINT"*) ko "alarme alors que la fenêtre est vide" ;; *) ok "pas d'alarme" ;; esac
case "$SORTIE" in *"systemMessage"*) ko "message visible alors que rien à dire" ;; *) ok "rien d'affiché à Matthieu" ;; esac
case "$SORTIE" in *"compteur vivant"*) ok "battement présent" ;; *) ko "battement absent : $SORTIE" ;; esac

echo "6. acquittement"
prompt s10 "c'est quoi ça" > /dev/null
prompt s10 "je ne comprends pas" > /dev/null
SORTIE=$(demarrage)
case "$SORTIE" in *"SEUIL ATTEINT"*) ok "alarme avant acquittement" ;; *) ko "pas d'alarme avant acquittement" ;; esac
sleep 1
"$PY" -c "from datetime import datetime, timezone; print(datetime.now(timezone.utc).isoformat(timespec='seconds'))" > "$FG_LISIBILITE_DIR/acquittement.txt"
SORTIE=$(demarrage)
case "$SORTIE" in *"SEUIL ATTEINT"*) ko "alarme malgré l'acquittement" ;; *) ok "silence après acquittement" ;; esac

echo "7. sortie toujours du JSON valide, même sur entrée vide"
if printf '' | "$PY" "$SCRIPT" | "$PY" -c "import sys,json; json.loads(sys.stdin.read())"; then ok "JSON valide sur entrée vide"; else ko "JSON invalide sur entrée vide"; fi

echo "8. écrit sans apostrophe"
AVANT=$(nb_journal)
prompt s11 "cest quoi un palier" > /dev/null
verif "$(nb_journal)" "$((AVANT+1))" "« cest quoi » est compté"
prompt s11 "attends c est quoi cette histoire de sommaire" > /dev/null
verif "$(nb_journal)" "$((AVANT+2))" "« c est quoi » est compté"
prompt s11 "ok cest note, on continue" > /dev/null
verif "$(nb_journal)" "$((AVANT+2))" "« cest noté » n'est pas compté"

echo "9. message écrit par l'application"
AVANT=$(nb_journal)
SORTIE=$(prompt s12 "<task-notification>\\n<task-id>abc</task-id>\\n<result>dernier cas : jai pas compris, c'est quoi le palier</result>\\n</task-notification>")
verif "$(nb_journal)" "$AVANT" "une fin de tâche de fond n'est pas comptée"
case "$SORTIE" in *"journalis"*) ko "Claude est prévenu à tort : $SORTIE" ;; *) ok "aucune fausse alerte pour Claude" ;; esac
prompt s12 "jai pas compris le resultat de la recherche" > /dev/null
verif "$(nb_journal)" "$((AVANT+1))" "la vraie question qui suit, elle, est comptée"

rm -rf "$FG_LISIBILITE_DIR"
if [ "$ECHECS" -eq 0 ]; then echo "TOUT VERT"; exit 0; else echo "ÉCHECS : $ECHECS"; exit 1; fi
