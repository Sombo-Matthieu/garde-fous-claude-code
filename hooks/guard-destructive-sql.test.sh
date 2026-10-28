#!/usr/bin/env bash
# Test du garde SQL destructeur (guard-destructive-sql.sh + .py).
# Lancer : bash ~/.claude/hooks/guard-destructive-sql.test.sh
#
# Ce que ce test vérifie, en langage humain :
#   1. les gestes catastrophiques sont BLOQUÉS (code 2) : DELETE ou UPDATE sans WHERE,
#      TRUNCATE, DROP TABLE — via l'outil SQL comme via psql en ligne de commande ;
#   2. le travail normal PASSE (code 0) : SELECT, DELETE ou UPDATE ciblés par WHERE,
#      upsert psql (ON CONFLICT DO UPDATE), mot « delete » dans une simple chaîne,
#      commande Bash sans psql ;
#   3. un DROP dans une migration versionnée passe (évolution de schéma), mais un
#      DELETE sans WHERE dans une migration reste bloqué ;
#   4. un WHERE caché dans un commentaire ne suffit pas à tromper le garde.
set -u
SCRIPT="${1:-$HOME/.claude/hooks/guard-destructive-sql.sh}"
ECHECS=0
ok() { printf '  ✓ %s\n' "$1"; }
ko() { printf '  ✗ %s\n' "$1"; ECHECS=$((ECHECS+1)); }

# appel <outil> <cle> <valeur> -> code de sortie du garde
appel() {
  python3 -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[1],"tool_input":{sys.argv[2]:sys.argv[3]}}))' "$1" "$2" "$3" \
    | bash "$SCRIPT" 2>/dev/null
  echo $?
}
attendu() { # attendu <code attendu> <libellé> <outil> <cle> <valeur>
  local c; c=$(appel "$3" "$4" "$5")
  [ "$c" = "$1" ] && ok "$2" || ko "$2 (attendu $1, obtenu $c)"
}

SQL=mcp__supabase__execute_sql
MIG=mcp__supabase__apply_migration

echo "1. gestes catastrophiques bloqués"
attendu 2 "DELETE sans WHERE (outil SQL)"            $SQL query "DELETE FROM commandes"
attendu 2 "UPDATE sans WHERE (outil SQL)"            $SQL query "update clients set actif = false"
attendu 2 "TRUNCATE (outil SQL)"                     $SQL query "TRUNCATE factures"
attendu 2 "DROP TABLE (outil SQL)"                   $SQL query "drop table paiements"
attendu 2 "2e instruction destructrice d'un lot"     $SQL query "select 1; delete from stock"
attendu 2 "DELETE sans WHERE via psql"               Bash command "psql \"\$DB\" -c 'DELETE FROM commandes'"

echo "2. travail normal autorisé"
attendu 0 "SELECT"                                   $SQL query "select * from commandes"
attendu 0 "DELETE ciblé par WHERE"                   $SQL query "delete from commandes where id = 42"
attendu 0 "UPDATE ciblé par WHERE"                   $SQL query "update clients set actif = false where id in (1,2)"
attendu 0 "upsert psql (ON CONFLICT DO UPDATE SET)"  Bash command "psql -c \"insert into t values (1) on conflict (id) do update set v = 1\""
attendu 0 "le mot delete dans une chaîne"            $SQL query "insert into journal(msg) values ('delete from x')"
attendu 0 "commande Bash sans psql"                  Bash command "git commit -m 'drop table obsolète'"

echo "3. migrations versionnées"
attendu 0 "DROP TABLE dans une migration"            $MIG query "drop table ancienne_table"
attendu 2 "DELETE sans WHERE dans une migration"     $MIG query "delete from commandes"

echo "4. WHERE caché dans un commentaire"
attendu 2 "DELETE + « -- where » en commentaire"     $SQL query "delete from commandes -- where id = 1"

echo
if [ "$ECHECS" -eq 0 ]; then echo "TOUT VERT"; else echo "$ECHECS ÉCHEC(S)"; fi
exit "$ECHECS"
