#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
lisibilite-compteur.py — compteur des demandes de réexplication de Matthieu.
Levier 0 du chantier « lisibilité » (10/09/2026), cf. fiche mémoire
feedback_pedagogie_logique_metier.

Pourquoi : la règle « pas de jargon » vit dans un rappel relu à chaque message,
mais rien ne MESURE si elle marche. Ce script compte le résultat réel — les fois
où Matthieu doit demander « c'est quoi X ? » — et porte lui-même son alarme,
des deux côtés, quand le seuil validé (2 demandes sur les 5 dernières sessions)
est atteint. Un compteur que personne ne relit est un stock mort : ici l'alarme
est injectée à chaque démarrage de session (pour Claude) et affichée dans le
terminal (pour Matthieu), qui n'a donc pas besoin que Claude pense à le dire.

Deux événements, un seul script (le champ hook_event_name les distingue) :

  UserPromptSubmit
    - détecte dans le message de Matthieu une demande de réexplication
      (« c'est quoi », « réexplique », « je ne comprends pas », « pas compris »,
      « ça veut dire quoi ») ou le signal volontaire « ?? » en tête de message ;
    - journalise le cas dans journal.jsonl avec le message précédent de Claude
      (lu dans la transcription) pour qu'on puisse relire les cas réels ;
    - enregistre la session dans sessions.jsonl (une ligne par session vue) ;
    - si le seuil est atteint, injecte une ligne courte à chaque message.

  SessionStart
    - calcule N = cas sur les 5 dernières sessions enregistrées ;
    - injecte TOUJOURS une ligne (battement : prouve que le compteur est vivant) ;
    - si N ≥ SEUIL : ligne rouge pour Claude + message visible pour Matthieu.

Limites assumées :
  - reconnaissance par formulation : sous-compte (« hein ? » n'est pas vu) ;
    le signal « ?? » en tête de message compte à coup sûr ;
  - l'apostrophe est facultative (« cest quoi ») et les messages écrits par
    l'application (fin de tâche de fond, événement de CI) ne sont jamais comptés ;
  - « c'est quoi » attrape aussi des questions légitimes (« c'est quoi le chiffre
    de la semaine ? ») : l'alarme demande donc de RELIRE les cas avant de construire le
    palier suivant, le journal garde le contexte pour ça.

Acquittement : quand le palier suivant est construit (ou les cas relus et
écartés), écrire l'horodatage ISO dans <dossier>/acquittement.txt : seuls les
cas postérieurs comptent ensuite.

Dossier : ~/.claude/lisibilite/ (FG_LISIBILITE_DIR le remplace, pour les tests).
Sortie : JSON sur stdout, exit 0 TOUJOURS — un compteur qui plante ne doit
jamais bloquer une session.
"""
import io
import json
import os
import re
import sys
from datetime import datetime, timezone

SEUIL = 2                 # demandes de réexplication…
FENETRE_SESSIONS = 5      # …sur les N dernières sessions
EXTRAIT_MAX = 240         # caractères gardés du message de Matthieu
PRECEDENT_MAX = 400       # caractères gardés du message précédent de Claude

# L'apostrophe est FACULTATIVE (« cest quoi », « c est quoi ») : Matthieu tape
# souvent sans. Mesuré le 05/10/2026 : en l'exigeant, le compteur avait manqué
# 5 des 7 vraies demandes depuis le 10/09 — il sous-comptait la panne qu'il mesure.
MOTIFS = [
    ("c'est quoi",            re.compile(r"\bc[' ]?est quoi\b", re.IGNORECASE)),
    ("ça veut dire quoi",     re.compile(r"\b(ça|ca) veut dire quoi\b", re.IGNORECASE)),
    ("qu'est-ce que ça veut dire",
                              re.compile(r"qu[' ]?est[- ]ce que (ça|ca) veut dire", re.IGNORECASE)),
    ("réexplique",            re.compile(r"\br[ée]-?expli", re.IGNORECASE)),
    ("je ne comprends pas",   re.compile(r"\bje (ne |n')?comprends? pas\b", re.IGNORECASE)),
    ("pas compris",           re.compile(r"\bpas compris\b", re.IGNORECASE)),
]
SIGNAL_VOLONTAIRE = "??"
# Messages écrits par l'application, jamais tapés par Matthieu : la fin d'une tâche
# de fond, un événement de CI. Leur texte peut contenir « pas compris » sans que
# personne n'ait rien demandé (faux cas du 05/10/2026, sur une fin de recherche).
MESSAGES_AUTOMATIQUES = ("<task-notification>", "<ci-monitor-event>")


def maintenant():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def dossier():
    d = os.environ.get("FG_LISIBILITE_DIR") or os.path.join(os.path.expanduser("~"), ".claude", "lisibilite")
    try:
        os.makedirs(d, exist_ok=True)
    except Exception:
        pass
    return d


def lire_jsonl(chemin):
    lignes = []
    try:
        with io.open(chemin, "r", encoding="utf-8") as f:
            for l in f:
                l = l.strip()
                if not l:
                    continue
                try:
                    lignes.append(json.loads(l))
                except Exception:
                    continue
    except Exception:
        pass
    return lignes


def ajouter_jsonl(chemin, obj):
    with io.open(chemin, "a", encoding="utf-8") as f:
        f.write(json.dumps(obj, ensure_ascii=False) + "\n")


def nom_projet(cwd):
    """Nom lisible du projet : le dossier principal, pas le worktree."""
    if not cwd:
        return "?"
    c = cwd.replace("\\", "/")
    marqueur = "/.claude/worktrees/"
    if marqueur in c:
        c = c.split(marqueur)[0]
    return c.rstrip("/").split("/")[-1] or "?"


def detecter(prompt):
    """Retourne le libellé du motif reconnu, ou None."""
    if prompt is None:
        return None
    texte = prompt.replace("’", "'").strip()
    if texte.startswith(MESSAGES_AUTOMATIQUES):
        return None
    if texte.startswith(SIGNAL_VOLONTAIRE):
        return "signal volontaire « ?? »"
    for libelle, regex in MOTIFS:
        if regex.search(texte):
            return libelle
    return None


def dernier_message_claude(transcript_path):
    """Premier extrait du dernier message texte de Claude dans la transcription."""
    if not transcript_path:
        return ""
    try:
        with io.open(transcript_path, "r", encoding="utf-8") as f:
            lignes = f.readlines()
    except Exception:
        return ""
    for l in reversed(lignes):
        try:
            d = json.loads(l)
        except Exception:
            continue
        if d.get("type") != "assistant":
            continue
        contenu = (d.get("message") or {}).get("content") or []
        if isinstance(contenu, str):
            textes = [contenu]
        else:
            textes = [b.get("text", "") for b in contenu if isinstance(b, dict) and b.get("type") == "text"]
        texte = " ".join(t for t in textes if t).strip()
        if texte:
            return texte[:PRECEDENT_MAX]
    return ""


def acquittement(d):
    try:
        with io.open(os.path.join(d, "acquittement.txt"), "r", encoding="utf-8") as f:
            return f.read().strip()
    except Exception:
        return ""


def etat(d):
    """N sur la fenêtre, total, dernier cas, sessions considérées."""
    sessions = lire_jsonl(os.path.join(d, "sessions.jsonl"))
    journal = lire_jsonl(os.path.join(d, "journal.jsonl"))
    acq = acquittement(d)
    if acq:
        journal = [j for j in journal if j.get("ts", "") > acq]
    ids = []
    for s in sessions:
        sid = s.get("session_id")
        if sid and sid not in ids:
            ids.append(sid)
    fenetre = ids[-FENETRE_SESSIONS:]
    dans_fenetre = [j for j in journal if j.get("session_id") in fenetre]
    dernier = journal[-1] if journal else None
    return {
        "n": len(dans_fenetre),
        "total": len(journal),
        "sessions_fenetre": len(fenetre),
        "dernier": dernier,
        "acquittement": acq,
    }


def ligne_battement(e, d):
    txt = ("[Lisibilité — compteur vivant] %d demande(s) de réexplication sur les %d dernières sessions "
           "(seuil %d) · total depuis acquittement : %d" % (e["n"], e["sessions_fenetre"], SEUIL, e["total"]))
    if e["dernier"]:
        txt += " · dernier cas %s : « %s »" % (e["dernier"].get("ts", "?")[:10], e["dernier"].get("extrait", "")[:80])
    txt += " · journal : %s" % os.path.join(d, "journal.jsonl").replace("\\", "/")
    return txt


def ligne_seuil(e, d):
    return ("🔴 [Lisibilité — SEUIL ATTEINT] %d demandes de réexplication sur les %d dernières sessions (seuil %d). "
            "À faire DANS LA PREMIÈRE RÉPONSE : l'annoncer à Matthieu, relire les cas dans %s, "
            "et proposer le contrôle de sortie (palier 3, fiche feedback_pedagogie_logique_metier). "
            "Acquitter ensuite : écrire l'horodatage ISO dans %s."
            % (e["n"], e["sessions_fenetre"], SEUIL,
               os.path.join(d, "journal.jsonl").replace("\\", "/"),
               os.path.join(d, "acquittement.txt").replace("\\", "/")))


def message_visible(e):
    return ("🗣️ Lisibilité : %d demandes de réexplication sur les %d dernières sessions (seuil %d). "
            "Le contrôle de sortie (palier 3) est dû — Claude doit te le proposer maintenant."
            % (e["n"], e["sessions_fenetre"], SEUIL))


def traiter(payload):
    ev = payload.get("hook_event_name") or ""
    d = dossier()
    out = {}

    if ev == "UserPromptSubmit":
        sid = payload.get("session_id") or "?"
        sessions = lire_jsonl(os.path.join(d, "sessions.jsonl"))
        if sid not in [s.get("session_id") for s in sessions]:
            ajouter_jsonl(os.path.join(d, "sessions.jsonl"),
                          {"session_id": sid, "premiere_vue": maintenant(), "projet": nom_projet(payload.get("cwd"))})
        motif = detecter(payload.get("prompt"))
        if motif:
            ajouter_jsonl(os.path.join(d, "journal.jsonl"), {
                "ts": maintenant(),
                "session_id": sid,
                "projet": nom_projet(payload.get("cwd")),
                "motif": motif,
                "extrait": (payload.get("prompt") or "").strip()[:EXTRAIT_MAX],
                "message_precedent": dernier_message_claude(payload.get("transcript_path")),
            })
        e = etat(d)
        parts = []
        if motif:
            parts.append("[Lisibilité] Demande de réexplication détectée (%s) — journalisée. %d sur les %d dernières sessions, seuil %d."
                         % (motif, e["n"], e["sessions_fenetre"], SEUIL))
        if e["n"] >= SEUIL:
            parts.append(ligne_seuil(e, d))
        if parts:
            out["hookSpecificOutput"] = {"hookEventName": "UserPromptSubmit", "additionalContext": "\n".join(parts)}
        return out

    if ev == "SessionStart":
        e = etat(d)
        parts = [ligne_battement(e, d)]
        if e["n"] >= SEUIL:
            parts.insert(0, ligne_seuil(e, d))
            out["systemMessage"] = message_visible(e)
        out["hookSpecificOutput"] = {"hookEventName": "SessionStart", "additionalContext": "\n".join(parts)}
        return out

    return out


def main():
    try:
        brut = sys.stdin.buffer.read().decode("utf-8", "replace")
        payload = json.loads(brut) if brut.strip() else {}
    except Exception:
        payload = {}
    try:
        out = traiter(payload)
    except Exception as exc:  # jamais bloquer une session pour un compteur
        out = {"systemMessage": "⚠️ lisibilite-compteur.py en erreur : %s" % exc}
    sys.stdout.write(json.dumps(out))
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
