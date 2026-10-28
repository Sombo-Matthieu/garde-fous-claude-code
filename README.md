# Garde-fous pour travailler avec un agent IA (Claude Code)

Je développe seul, avec l'agent IA **Claude Code**, le logiciel de gestion interne d'une PME
agroalimentaire (commandes, production, stock, CRM, facturation, traçabilité HACCP), en production
depuis 2026. Ce dépôt rassemble les **garde-fous qui encadrent l'agent** : ce qu'il a le droit de
faire sans demander, ce qui le bloque, et ce qui l'oblige à garder une trace de son travail.

## Pourquoi

En mai 2026, un bug de l'application a effacé une semaine de commandes en production. Ce n'était
pas l'agent, mais l'incident a montré qu'une seule suppression sans condition suffit à faire
disparaître des données réelles, et l'agent a les droits pour lancer exactement ce type de requête.
D'où le principe de ce dépôt : une consigne écrite (« ne supprime jamais tout ») ne suffit pas. Un
agent qui a accès à une base de données et à un dépôt Git a besoin de **garde-fous automatiques qui
bloquent avant l'exécution**.

## Ce que ça fait

| Garde-fou | Fichier | Rôle |
|---|---|---|
| **Garde SQL destructeur** | `hooks/guard-destructive-sql.py` | Bloque avant exécution un `DELETE` ou un `UPDATE` sans `WHERE`, un `TRUNCATE` ou un `DROP` lancé par l'agent, via l'outil SQL comme via `psql`. Ce blocage s'applique même quand les validations manuelles sont désactivées. Si l'analyse elle-même échoue (Python absent ou en erreur) alors qu'un mot-clé destructeur est présent, il bloque par précaution. |
| **Scanner de secrets** | `hooks/scan-secrets-memoire.sh` | Détecte les clés d'API, jetons et mots de passe (Supabase, GitHub, Anthropic, AWS, Stripe, Google…) avant qu'ils ne finissent dans les notes persistantes de l'agent. Les valeurs trouvées sont masquées à l'affichage. |
| **Permissions** | `settings.json` | 77 actions autorisées sans demander : lecture, tests, consultation des déploiements, mais aussi des requêtes SQL (filtrées par le garde ci-dessus), le pilotage du navigateur et la gestion des tickets GitHub. 20 interdits, dont la lecture directe des fichiers `.env` (Read, `cat`, `head`, `tail`, `grep`), des clés SSH et certificats, `find -delete` et l'exécution de code à la volée (`node -e`, `python -c`). En mode automatique, la réinitialisation et l'envoi du schéma de base ne passent pas sans validation. |
| **Rappels de traçabilité** | `hooks/post-commit-memory-reminder.sh`, `hooks/pr-issue-sweep-reminder.sh`, `hooks/stop-memory-check.sh` | Après un commit, demande à l'agent si ses notes doivent être mises à jour. À la création d'une demande de fusion, signale les « TODO » laissés dans le code, à transformer en tickets. Dans les 10 minutes qui suivent un commit, le rappelle une dernière fois en fin de réponse. |
| **Compteur de lisibilité** | `hooks/lisibilite-compteur.py` | Compte les fois où je dois redemander « c'est quoi X ? » : au-delà d'un seuil, l'agent doit revoir sa façon d'expliquer. Je ne suis pas développeur de formation ; ce garde-fou m'oblige à comprendre ce que je mets en production. |

S'y ajoutent un sous-agent (`agents/memory-curator.md`), deux commandes personnalisées
(`/audit-memoire`, `/fin-session`) et les consignes globales de l'agent (`CLAUDE.md`).

**Limites connues du garde SQL** : il ne lit pas le contenu d'un fichier passé à `psql -f`, et ne
voit pas un `DELETE` placé après une clause `WITH`. Il couvre le geste catastrophique courant, pas
toutes les façons d'effacer des données.

## Tests

Trois scripts ont leurs tests (`hooks/*.test.sh`) :
- le garde SQL : 15 cas (gestes bloqués, travail normal autorisé, migrations, `WHERE` caché dans un commentaire) ;
- le scanner de secrets : faux secrets à trouver, faux positifs à ignorer ;
- le compteur de lisibilité.

Une fois la configuration installée dans `~/.claude/` :

```bash
for t in ~/.claude/hooks/*.test.sh; do bash "$t"; done
```

## Ce que ce dépôt ne contient pas (volontairement)

- **Aucun secret** : identifiants, `.mcp.json` et `settings.local.json` restent sur la machine.
- **Aucune donnée métier** : la mémoire de l'agent et le code de l'application restent dans des dépôts privés.

## Installer

1. Copier le contenu de ce dépôt dans `~/.claude/`. Il faut Bash, Git et Python 3 (`python3` ou `python`) ; sous Windows, Git Bash.
2. Reconnecter ses comptes (aucun secret n'est ici) : `claude` (connexion Anthropic), `gh auth login`,
   serveurs MCP éventuels (`claude mcp add ...`).
3. Lancer les tests ci-dessus pour vérifier l'installation.
