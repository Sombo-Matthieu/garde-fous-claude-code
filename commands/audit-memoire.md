---
description: Scanne la mémoire complète, détecte redondances/obsolescence, propose consolidations
---

Lance un audit complet du système de mémoire. **Utilise le subagent `memory-curator`** pour isoler cette analyse dans son propre contexte — tu ne dois PAS lire tous les fichiers mémoire toi-même, ça polluerait la conversation principale pour rien.

**Ton rôle ici** :
1. Invoque le subagent `memory-curator` via l'outil Agent
2. Prompt pour le subagent : "Scanne `~/.claude/projects/<projet>/memory/` au complet. Détecte : (a) entrées redondantes (2 fichiers qui disent la même chose), (b) obsolescence (projets terminés, feedbacks remplacés, références périmées), (c) doublons entre MEMORY.md et les fichiers. Retourne un rapport structuré : liste des consolidations proposées, avec pour chaque : fichier(s) concerné(s), action recommandée (merge/delete/update), justification en 1 phrase. Ne modifie AUCUN fichier — propose uniquement."
3. Présente le rapport du subagent à l'utilisateur, groupé par type d'action
4. Demande à l'utilisateur **quelles consolidations appliquer** (format liste à cocher A/B/C/D…)
5. Applique uniquement celles validées

**Règles** :
- Le subagent ne modifie rien. Seul toi (agent principal) modifies les fichiers, et seulement après validation explicite.
- Si le rapport ne détecte rien → dis "mémoire saine, rien à consolider" et arrête.
- À la fin, si des modifs ont été faites, mettre à jour `MEMORY.md` en cohérence.
