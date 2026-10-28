#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Garde SQL destructeur — analyse fine. Invoqué par guard-destructive-sql.sh.
#
# Lit sur stdin le JSON PreToolUse de Claude Code. Décide si l'appel est une
# écriture SQL destructrice à bloquer :
#   - DELETE ... sans clause WHERE      (efface toutes les lignes)
#   - UPDATE ... SET ... sans WHERE     (modifie toutes les lignes)
#   - TRUNCATE                          (vide la table)
#   - DROP TABLE/SCHEMA/DATABASE        (supprime l'objet) — sauf via apply_migration
#
# Codes de sortie :
#   0 = laisser passer   2 = BLOQUER (message sur stderr)   3 = "je ne sais pas"
#       (JSON illisible) → le wrapper décidera (fail-closed si mot-clé destructeur).
#
# Deux modes de détection :
#   - "anchored" (MCP execute_sql / apply_migration) : on a le SQL brut, on ancre
#     la détection au DÉBUT de chaque instruction → très peu de faux positifs
#     (n'attrape pas 'delete from' dans une chaîne, ni un upsert ON CONFLICT DO UPDATE).
#   - "loose" (psql en Bash) : le SQL est noyé dans la ligne de commande, on scanne
#     sans ancrage → attrape `psql -c 'DELETE FROM t'`, avec un garde anti-upsert.
#
# Limites assumées (V1 honnête) : ne voit pas le contenu d'un `psql -f fichier.sql`
# (fichier non lu) ; un `WITH cte AS (...) DELETE ...` en tête de CTE sans WHERE
# passe (rare). Le geste catastrophique courant (DELETE/TRUNCATE/UPDATE nu) est couvert.

import json
import re
import sys


def block(tool, hits):
    lines = [
        "",
        "⛔ BLOQUE par le garde SQL destructeur (~/.claude/hooks/guard-destructive-sql).",
        "   Outil : %s" % tool,
    ]
    for reason, preview in hits:
        lines.append("   • %s" % reason)
        lines.append("     %s" % preview)
    lines += [
        "",
        "   Pourquoi : un geste de ce type a deja efface une semaine de commandes (bug du 2026-05-11).",
        "   Si c'est VOULU : clause WHERE ciblee, ou RPC transactionnelle, ou dump d'abord",
        "   (jamais d'effacement global sans cible ni sauvegarde).",
        "   Toi (humain) : Supabase Studio ou un psql que TU lances restent possibles.",
        "",
    ]
    sys.stderr.write("\n".join(lines) + "\n")
    sys.exit(2)


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(3)  # JSON illisible -> le wrapper tranche (fail-closed)

    tool = data.get("tool_name", "") or ""
    tool_input = data.get("tool_input", {}) or {}

    sql_tools = ("mcp__supabase__execute_sql", "mcp__supabase__apply_migration")

    if tool in sql_tools:
        raw = tool_input.get("query") or tool_input.get("sql") or ""
        mode = "anchored"
    elif tool == "Bash":
        cmd = tool_input.get("command", "") or ""
        if re.search(r"\bpsql\b", cmd, re.I):
            raw = cmd
            mode = "loose"
        else:
            sys.exit(0)  # Bash non-psql -> pas notre affaire
    else:
        sys.exit(0)

    if not raw or not raw.strip():
        sys.exit(0)

    # DROP est légitime dans une migration (évolution de schéma versionnée) :
    # on ne le garde PAS sur apply_migration, mais on garde la perte de DONNÉES.
    guard_drop = tool != "mcp__supabase__apply_migration"

    # Normalisation : retirer commentaires, aplatir les espaces/retours ligne.
    s = re.sub(r"--[^\n]*", " ", raw)               # commentaires -- ...
    s = re.sub(r"/\*.*?\*/", " ", s, flags=re.S)    # commentaires /* ... */
    s = re.sub(r"\s+", " ", s).strip()

    statements = [st.strip() for st in s.split(";") if st.strip()]
    find = re.match if mode == "anchored" else re.search

    def check(stmt):
        low = stmt.lower()
        has_where = re.search(r"\bwhere\b", low) is not None

        if find(r"delete\s+from\b", low) and not has_where:
            return "DELETE sans clause WHERE (efface toutes les lignes)"

        if find(r"update\b", low) and re.search(r"\bset\b", low) and not has_where:
            # en 'loose', ne pas bloquer un upsert psql (ON CONFLICT DO UPDATE SET)
            if mode == "anchored" or not re.search(r"on\s+conflict", low):
                return "UPDATE sans clause WHERE (modifie toutes les lignes)"

        if find(r"truncate\b", low):
            return "TRUNCATE (vide entierement la table)"

        if guard_drop:
            m = find(r"drop\s+(table|schema|database)\b", low)
            if m:
                return "DROP %s (supprime l'objet)" % m.group(1).upper()

        return None

    hits = []
    for st in statements:
        reason = check(st)
        if reason:
            preview = st if len(st) <= 200 else st[:197] + "..."
            hits.append((reason, "-> " + preview))

    if hits:
        block(tool, hits)

    sys.exit(0)


if __name__ == "__main__":
    main()
