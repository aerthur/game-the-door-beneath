#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════
# agent.sh — Agent Claude Code pour The Door Beneath
# Lance toutes les 2h via cron. Cherche les issues GitHub [F]
# non assignées, crée une branche, et demande à Claude de coder.
#
# Prérequis sur le VPC :
#   - gh CLI installé et authentifié (gh auth login)
#   - claude CLI installé et authentifié (claude login)
#   - git configuré avec accès au repo
#
# Installation cron (toutes les 2h) :
#   crontab -e
#   0 */2 * * * /chemin/vers/agent.sh >> /var/log/claude-agent.log 2>&1
# ══════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────
REPO="aerthur/game-the-door-beneath"
REPO_DIR="/home/claude/game-the-door-beneath"
MAIN_BRANCH="main"
LOG_PREFIX="[$(date '+%Y-%m-%d %H:%M:%S')] [agent]"

# ── Helpers ───────────────────────────────────────────────────────
log() { echo "$LOG_PREFIX $*"; }

# ── 1. Aller dans le repo, s'assurer qu'on est à jour ─────────────
log "Démarrage — repo: $REPO"
cd "$REPO_DIR"
git fetch origin
git checkout "$MAIN_BRANCH"
git pull --ff-only origin "$MAIN_BRANCH"

# ── 2. Chercher une issue [F] ouverte et non assignée ────────────
log "Recherche d'issues [F] non assignées..."

# Récupère la première issue [F] sans assignee
ISSUE_JSON=$(gh issue list \
  --repo "$REPO" \
  --state open \
  --search "[F] in:title no:assignee" \
  --limit 1 \
  --json number,title,body \
  2>/dev/null || echo "[]")

# Aucune issue à traiter
if [ "$ISSUE_JSON" = "[]" ] || [ -z "$ISSUE_JSON" ]; then
  log "Aucune issue [F] non assignée trouvée. Fin."
  exit 0
fi

ISSUE_NUM=$(echo "$ISSUE_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['number'])")
ISSUE_TITLE=$(echo "$ISSUE_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['title'])")
ISSUE_BODY=$(echo "$ISSUE_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['body'] or '')")

log "Issue trouvée : #$ISSUE_NUM — $ISSUE_TITLE"

# ── 3. S'assigner l'issue (évite que deux agents la prennent) ─────
gh issue edit "$ISSUE_NUM" --repo "$REPO" --add-assignee "@me"
gh issue comment "$ISSUE_NUM" --repo "$REPO" \
  --body "🤖 Agent Claude Code a pris en charge cette issue. Implémentation en cours..."

# ── 4. Créer la branche feature ───────────────────────────────────
# Transforme le titre en slug (minuscules, espaces → tirets, sans [F])
SLUG=$(echo "$ISSUE_TITLE" \
  | tr '[:upper:]' '[:lower:]' \
  | sed 's/\[f\]//gi' \
  | sed 's/[^a-z0-9]/-/g' \
  | sed 's/--*/-/g' \
  | sed 's/^-\|-$//g' \
  | cut -c1-40)

BRANCH="feature/${ISSUE_NUM}-${SLUG}"
log "Création de la branche : $BRANCH"

git checkout -b "$BRANCH"

# ── 5. Construire le prompt pour Claude Code ──────────────────────
PROMPT="Tu es un développeur de jeux vidéo travaillant sur 'The Door Beneath', un roguelite en lanes développé avec Godot 4.6 et GDScript 2.0.

Le repo est dans le répertoire courant. Lis d'abord le fichier CLAUDE.md à la racine du repo pour comprendre l'architecture complète avant de commencer.

## Issue GitHub #${ISSUE_NUM} à implémenter

**Titre :** ${ISSUE_TITLE}

**Description :**
${ISSUE_BODY}

## Instructions

1. Lis CLAUDE.md en premier pour comprendre le projet
2. Explore les fichiers concernés par la feature
3. Implémente la feature en modifiant les fichiers nécessaires
4. Assure-toi que le code est cohérent avec le style GDScript existant
5. Vérifie qu'il n'y a pas de syntaxe invalide (.tscn ne supporte pas add_theme_font_size_override inline, etc.)
6. Après implémentation, fais un git commit avec un message clair

Le commit message doit suivre ce format :
feat(#${ISSUE_NUM}): description courte de ce qui a été fait

Ne lance pas Godot, ne teste pas en jeu — implémente seulement le code.
Commit à la fin."

# ── 6. Lancer Claude Code en headless ─────────────────────────────
log "Lancement de Claude Code..."
cd "$REPO_DIR"

claude --dangerously-skip-permissions -p "$PROMPT" \
  --allowedTools "Read,Write,Edit,Bash(git *),Bash(ls *),Bash(find *),Glob,Grep" \
  2>&1 | tee /tmp/claude-output-${ISSUE_NUM}.log

CLAUDE_EXIT=${PIPESTATUS[0]}
log "Claude Code terminé (exit: $CLAUDE_EXIT)"

# ── 7. Vérifier qu'il y a des commits à pusher ────────────────────
cd "$REPO_DIR"
COMMITS_AHEAD=$(git rev-list --count "origin/$MAIN_BRANCH..HEAD" 2>/dev/null || echo "0")

if [ "$COMMITS_AHEAD" = "0" ]; then
  log "AVERTISSEMENT : Claude n'a pas créé de commit. Push annulé."
  gh issue comment "$ISSUE_NUM" --repo "$REPO" \
    --body "⚠️ L'agent n'a pas pu créer de commit pour cette issue. Vérification manuelle nécessaire."
  git checkout "$MAIN_BRANCH"
  git branch -D "$BRANCH"
  exit 1
fi

# ── 8. Pusher la branche et ouvrir une PR ────────────────────────
log "Push de la branche $BRANCH..."
git push -u origin "$BRANCH"

log "Création de la Pull Request..."
PR_URL=$(gh pr create \
  --repo "$REPO" \
  --title "feat: $ISSUE_TITLE" \
  --body "## Résumé
Implémentation automatique par agent Claude Code.

Closes #${ISSUE_NUM}

## À vérifier avant merge
- [ ] Tester en jeu (Godot 4.6)
- [ ] Vérifier qu'il n'y a pas de régression sur les salles existantes
- [ ] S'assurer que le SPACE/room clear fonctionne toujours

🤖 *Généré automatiquement par agent.sh*" \
  --base "$MAIN_BRANCH" \
  --head "$BRANCH")

log "PR créée : $PR_URL"

# ── 9. Commenter sur l'issue ──────────────────────────────────────
gh issue comment "$ISSUE_NUM" --repo "$REPO" \
  --body "✅ Implémentation terminée !

**Pull Request :** $PR_URL

Le code est prêt pour review. Tester dans Godot 4.6 puis merger si tout va bien."

# Créer le label s'il n'existe pas, puis l'appliquer
gh label create "agent-done" --repo "$REPO" --color "0075ca" --description "Traité par agent Claude Code" 2>/dev/null || true
gh issue edit "$ISSUE_NUM" --repo "$REPO" --add-label "agent-done"

log "Done. Issue #$ISSUE_NUM traitée → $PR_URL"
git checkout "$MAIN_BRANCH"
