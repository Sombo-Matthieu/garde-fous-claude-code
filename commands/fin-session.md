---
description: Audite la fin de session par exception — vérifie les invariants (rien de perdu, SESSION.md fidèle au réel + vitrine committée ETAT-PROJET.md à jour aux jalons, dettes tracées) et n'agit/n'affiche que sur les écarts. Ne re-produit PAS ce que les hooks font en continu. Un worktree par session (app desktop) : n'audite que celui de la session.
---

L'utilisateur termine sa session. **Ce n'est PAS un rapport à produire — c'est un audit de sécurité à passer.**

## But (et critère de réussite)

Garantir qu'à la coupure, **trois invariants** tiennent :
1. **Rien ne peut être perdu** (tout commité + poussé, ou WIP explicitement assumé).
2. **SESSION.md ne ment pas** sur l'état réel (git/gh).
3. **Aucune dette ni objectif non clos ne s'évapore** (tout est tracé en issue ou parqué dans SESSION.md).

**Réussite = ces 3 invariants vérifiés, ou les écarts corrigés/tracés.** La commande finit par une assertion nette : « tu peux couper » OU « avant de couper : <liste courte> ».

## Principe directeur (lis-le avant d'agir)

- **Vérifie, ne re-produis pas.** Le fil de l'eau (hooks SESSION.md + `stop-memory-check` + dettes créées en issue au moment où elles surgissent) a déjà fait l'essentiel pendant la session. Cette commande est le **filet** qui rattrape ce que le continu a laissé tomber — pas une cérémonie qui le refait.
- **Sortie par exception.** Une vérif qui passe → **une ligne** (`✓ <invariant> : OK`). Une vérif qui échoue → **corrige sur place** (si trivial/évident) ou **trace** (issue `dette`), puis affiche uniquement ça. Pas de sections vides étalées.
- **Agis, ne mentionne pas.** Toute dette détectée passe par un fix-sur-place (< 2 min) OU `gh issue create --label dette`. Jamais « à noter pour plus tard » sans support — c'est la dette cognitive interdite ([[feedback_trois_dettes]], [[reference_registre_dette]]).
- **Aucune question.** L'utilisateur est à moitié parti. Si une décision semble requise (objectif non clos), applique le défaut sûr (parquer dans SESSION.md + signaler) plutôt que de bloquer sur une question. Rien ne doit dépendre d'une réponse qui ne viendra peut-être pas.

## Les vérifications (dans cet ordre)

### V1 — Rien de perdu (sécurité git) — l'invariant le plus critique
- `git status --short` → working tree propre ? Si fichiers modifiés/non commités : c'est du WIP qui **disparaît au crash**. Le signaler comme risque concret (rappeler l'incident de reprise post-crash : seul le commité survit).
- `git log @{upstream}..HEAD --oneline 2>$null` → commits non poussés ? Les signaler (le local seul = filet unique). Branche de session sans upstream (cas courant en worktree) : `git log origin/main..HEAD --oneline`.
- `git branch --show-current` + `gh pr list --head <branche> --state all --json number,state,mergedAt --limit 3` → si la PR est **mergée**, la branche locale est un résidu (à supprimer) ; si ouverte avec commits poussés, OK.
- `git worktree list` → **depuis le 09/09 l'app desktop crée un worktree PAR SESSION** : plusieurs worktrees = normal, pas une dette. Ne vérifier que celui de LA session (propre + rien de non poussé). Ne JAMAIS retirer le worktree d'une autre session : elle peut être active (constaté le 19/09 : 7 worktrees, dont 3 nés le jour même). L'inventaire des autres est déjà fait au démarrage par `wt-session-guard.sh`.
- **Verdict V1** : « aucune perte possible » UNIQUEMENT si tout est commité ET poussé (ou si le WIP restant est nommé et explicitement assumé). Sinon, c'est le premier point à régler.

### V2 — SESSION.md fidèle au réel (la valeur unique de cette commande)
- Lire le `SESSION.md` du projet (selon la convention retenue : racine du dépôt, ou `~/.claude/projects/<projet>/SESSION.md` pour le garder hors du dépôt).
- **Croiser ses affirmations avec la vérité git/gh** : chaque PR # citée avec un statut → vérifier son état réel (`gh pr view <n> --json state,mergedAt`). Format depuis le 16/10 (#1098) : une ligne par chantier en cours, 10 max, 250 car. chacune, aucune section.
- **Toute contradiction se corrige sur place, mais seulement sur la ligne de CETTE session** (ex. « PR #226 ouverte » alors qu'elle est mergée → réécrire). Chantier livré → sa ligne sort (le jalon va dans `ETAT-PROJET.md` s'il compte). Les lignes des autres sessions ne se touchent pas : un écart y est signalé, pas corrigé. Contrôle de forme : `node scripts/check-taille-docs.mjs`.
- C'est exactement le contrôle qui rattrape la dérive que le fil de l'eau laisse passer. Reporter chaque correction faite.
- Si `SESSION.md` absent → le créer **à l'emplacement hors dépôt ci-dessus, jamais dans le dossier courant** (format dans `CLAUDE.md` du projet). Si le hook signale « DEUX SESSION.md » → écart V2 : le nommer à Matthieu, ne pas écrire l'ancien.

### V2b — ETAT-PROJET.md (vitrine cloud) synchro — conditionnel
- N'apparaît **que si** `ETAT-PROJET.md` existe à la racine (sinon omettre). C'est la **synthèse committée** de l'avancement, seul canal vers le setup Claude hors PC (app mobile, routines cloud) qui ne voient que le repo — cf. [[reference_etat_projet_committe]].
- Déclencheur : un **jalon réel** a-t-il eu lieu cette session (PR mergée, chantier bouclé, décision durable) qui n'est PAS reflété dans `ETAT-PROJET.md` (comparer son contenu / `git log -1 --format=%cd -- ETAT-PROJET.md` aux merges du jour) ? Si non → `✓ V2b à jour`. Ne PAS régénérer pour du bruit (c'est une synthèse aux jalons, pas un miroir).
- Si oui → régénérer la synthèse **depuis `SESSION.md` rendu fidèle en V2**, puis la committer + pousser sur `main` (via worktree isolé si du WIP non commité occupe le working tree).
- **Garde-fou sécu NON négociable** : la vitrine est **expurgée** — aucun nom réel de personne, client ou fournisseur (rôles génériques), cf. [[feedback_pas_nommer_personne_securite]]. **Relire le diff avant le commit** pour confirmer zéro nom propre. Un nom réel committé = écart à corriger, pas à laisser passer.

### V3 — Intégrité mémoire
- Commits du jour (`git log --since="00:00" --no-merges --pretty=format:"%h %s"`) vs fichiers `memory/` modifiés aujourd'hui : un commit qui introduit un **principe durable / pattern non-obvious / décision** sans mémoire correspondante → l'ajouter (si évident) ou le signaler. (Le hook `stop-memory-check` nudge par commit ; ici c'est le contrôle d'intégrité global.)
- Cohérence `MEMORY.md` : lister les `.md` du dossier `memory/` vs les liens cités. **Fichier orphelin** (existe, pas indexé) ou **lien cassé** (indexé, fichier absent) → corriger sur place.
  - ⚠️ **Méthode junction-safe** : le dossier `memory/` est une junction Windows que `find`/`ls <dir>` ne traversent PAS (retournent 0). Utiliser le **glob** : `ls "$mem"/*.md`. Extraire les liens avec un regex qui accepte les chiffres : `grep -oE '\]\([^)]+\.md\)'` (les noms contiennent des dates type `2026_05`). À défaut, contrôle de cohérence minimal = comparer le **nombre** de fichiers `*.md` au **nombre** de liens uniques + spot-check que les fichiers mémoire créés ce jour sont bien indexés.

### V4 — Dettes & objectifs non clos tracés
- Recenser tout finding d'audit actif / décision / fragilité non bloquante soulevé cette session et **pas encore** tracé (le continu en a normalement déjà fait des issues ; ceci est le balayage de rattrapage).
- Chaque finding non tracé : fix < 2 min OU `gh issue create --label dette` (regrouper si pertinent : N findings linter → 1 méta-issue checklist). Si le label `dette` manque : `gh label create dette --color fbca04`.
- **Objectif de session non clos** (comparer la ligne de la session aux actions réelles) : ne JAMAIS le laisser disparaître en silence. Défaut sûr = sa ligne dans `SESSION.md` avec le prochain geste (ou une issue s'il dort) + le nommer dans le rapport. Geste de Matthieu → Obsidian `30 Tâches`. Interdiction de dire « session refermée proprement » s'il reste un objectif non clos non adressé.

### V5 — Tests (conditionnel, anti-friction)
- **Ne PAS lancer `npm test` si tout est poussé** : le CI l'a déjà fait sur le poussé. Afficher « code poussé → couvert par CI ».
- Lancer `npm test --silent` **uniquement s'il reste du code non commité ou non poussé** (là, le CI ne l'a pas vu). Si rouge → signaler comme dette technique ([[feedback_trois_dettes]]), ne pas fixer ici.

### V6 — Versioning (conditionnel)
- N'apparaît **que si** `CHANGELOG.md` existe à la racine. Sinon, omettre entièrement (versioning différé, sans fiche de suivi).
- Si activé : commits du jour à porter au CHANGELOG + signaler une éventuelle désync `package.json` ↔ dernier tag git.

## Format de sortie

- Titre : `## Fin de session — [YYYY-MM-DD]`
- **Une ligne par invariant vérifié** : `✓ V1 Rien de perdu — tout poussé, tout mergé` / `✓ V2 SESSION.md fidèle` / etc.
- **Pour chaque écart** : `⚠️ <quoi> → <action : corrigé sur place / issue #N / parqué dans SESSION.md>`.
- **Assertion finale, obligatoire et nette** :
  - soit `Tu peux couper : rien à perdre, SESSION.md fidèle, dettes tracées.`
  - soit `⚠️ Avant de couper : <liste courte des points restants>` (uniquement ce qui dépend d'une action de Matthieu).
- Sobre, sans emojis superflus (les marqueurs ✓/⚠️ suffisent), aucune congratulation, pas de « prochaine étape » inventée.
- **Pas de bloc de reprise copié-collé.** La reprise = `SESSION.md` à jour + `claude --continue`/`--resume`. Vouloir générer un tel bloc = signal qu'un invariant (SESSION.md fidèle) n'a pas joué → corriger la cause, pas le symptôme.

## Maintenance
- Si tu étends/réduis les vérifications, **mets à jour la ligne `description:`** du frontmatter.
- Cette commande s'audite elle-même : si en l'exécutant tu repères qu'une de ses vérifs est devenue redondante avec un nouveau hook/dispositif, signale-le (issue `dette`) au lieu de la garder par habitude — sinon elle redevient l'outil dormant qu'on vient de corriger ([[feedback_outil_consommateur]]).
