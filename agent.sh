#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════
# agent.sh — Agent Claude Code pour The Door Beneath
# Lance toutes les 2h via cron. Traite les issues [F] en boucle
# tant qu'il y en a et que les tokens sont disponibles.
# Supporte la reprise automatique en cas d'interruption.
#
# Prérequis :
#   - gh CLI installé et authentifié (gh auth login)
#   - claude CLI installé et authentifié (claude login)
#   - git configuré avec accès au repo
#   - python3 disponible
#
# Cron (toutes les 2h) :
#   0 */2 * * * /home/claude/game-the-door-beneath/agent.sh >> /var/log/claude-agent.log 2>&1
# ══════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Variables d'environnement ──────────────────────────────────────
if [ -f "$HOME/.env-recap" ]; then
  set -a
  source "$HOME/.env-recap"
  set +a
fi

# ── Configuration ─────────────────────────────────────────────────
REPO="aerthur/game-the-door-beneath"
REPO_DIR="/home/claude/game-the-door-beneath"
MAIN_BRANCH="main"
STATE_FILE="$REPO_DIR/.agent_state.json"
PENDING_RESTART_FILE="$REPO_DIR/.agent_restart_pending"
MAX_ISSUES=10   # sécurité : max d'issues par exécution
LOG_PREFIX="[$(date '+%Y-%m-%d %H:%M:%S')] [agent]"

# ── Telegram ──────────────────────────────────────────────────────
# Les variables GAME_TELEGRAM_TOKEN et GAME_TELEGRAM_CHAT_ID
# doivent être définies dans l'environnement du VPC.
TELEGRAM_TOKEN="${GAME_TELEGRAM_TOKEN:-}"
TELEGRAM_CHAT_ID="${GAME_TELEGRAM_CHAT_ID:-}"

tg() {
  # Usage : tg "message" [emoji_prefix]
  local msg="${2:-} ${1}"
  if [ -z "$TELEGRAM_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
    log "[Telegram] Variables non configurées — notification ignorée"
    return
  fi
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
    -d chat_id="$TELEGRAM_CHAT_ID" \
    -d parse_mode="Markdown" \
    -d text="$msg" \
    > /dev/null 2>&1 || log "[Telegram] Envoi échoué"
}

# ── Helpers ───────────────────────────────────────────────────────
log() { echo "$LOG_PREFIX $*"; }

state_write() {
  python3 -c "
import json
data = {
  'issue_num':   '$ISSUE_NUM',
  'issue_title': $(echo "$ISSUE_TITLE" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'),
  'branch':      '$BRANCH',
  'step':        '$1',
  'timestamp':   '$(date -Iseconds)'
}
print(json.dumps(data, indent=2))
" > "$STATE_FILE"
}

state_read() {
  python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('$1',''))"
}

state_clear() {
  rm -f "$STATE_FILE"
}

is_token_error() {
  # Détecte les erreurs de quota/token dans le log Claude
  grep -qiE "rate.limit|quota|529|overloaded|token.*exhaust|credit" "$1" 2>/dev/null
}

# ── Créer les labels si besoin ────────────────────────────────────
gh label create "agent-done" --repo "$REPO" --color "0075ca" \
  --description "Traité par agent Claude Code" 2>/dev/null || true
gh label create "agent-restart" --repo "$REPO" --color "e99695" \
  --description "Refaire depuis main (codebase changé)" 2>/dev/null || true

# ── Restart : réinitialise une issue pour la refaire depuis zéro ──
handle_restart_issues() {
  local RESTART_LIST COUNT

  RESTART_LIST=$(gh issue list \
    --repo "$REPO" \
    --state open \
    --label "agent-restart" \
    --json number,title \
    --limit 5 2>/dev/null || echo "[]")

  [ "$RESTART_LIST" = "[]" ] || [ -z "$RESTART_LIST" ] && return 0

  COUNT=$(echo "$RESTART_LIST" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
  log "[$COUNT issue(s) marquées agent-restart]"

  for i in $(seq 0 $((COUNT - 1))); do
    local NUM TITLE SLUG OLD_BRANCH

    NUM=$(echo "$RESTART_LIST"   | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$i]['number'])")
    TITLE=$(echo "$RESTART_LIST" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$i]['title'])")

    SLUG=$(echo "$TITLE" \
      | tr '[:upper:]' '[:lower:]' \
      | sed 's/\[f\]//gi' \
      | sed 's/[^a-z0-9]/-/g' \
      | sed 's/--*/-/g' \
      | sed 's/^-\|-$//g' \
      | cut -c1-40)
    OLD_BRANCH="feature/${NUM}-${SLUG}"

    log "Restart #$NUM — $TITLE (branche: $OLD_BRANCH)"
    cd "$REPO_DIR"
    git fetch origin 2>/dev/null || true

    # Fermer la PR existante si elle existe
    local EXISTING_PR
    EXISTING_PR=$(gh pr list --repo "$REPO" --head "$OLD_BRANCH" --json number -q '.[0].number' 2>/dev/null || echo "")
    if [ -n "$EXISTING_PR" ]; then
      log "Fermeture PR #$EXISTING_PR..."
      gh pr close "$EXISTING_PR" --repo "$REPO" \
        --comment "🔄 Restart demandé — PR annulée, nouvelle implémentation en cours." 2>/dev/null || true
    fi

    # Supprimer la branche distante
    if git ls-remote --exit-code --heads origin "$OLD_BRANCH" > /dev/null 2>&1; then
      log "Suppression branche distante origin/$OLD_BRANCH..."
      git push origin --delete "$OLD_BRANCH" 2>/dev/null || true
    fi

    # Supprimer la branche locale
    if git show-ref --verify --quiet "refs/heads/$OLD_BRANCH"; then
      git checkout "$MAIN_BRANCH" 2>/dev/null || true
      git branch -D "$OLD_BRANCH" 2>/dev/null || true
    fi

    # Vider le state si c'était cette issue en cours
    if [ -f "$STATE_FILE" ]; then
      local SAVED_NUM
      SAVED_NUM=$(state_read issue_num 2>/dev/null || echo "")
      [ "$SAVED_NUM" = "$NUM" ] && state_clear
    fi

    # Réinitialiser l'issue : retirer labels, désassigner
    gh issue edit "$NUM" --repo "$REPO" \
      --remove-label "agent-restart" \
      --remove-label "agent-done" \
      --remove-label "agent-skip" \
      --remove-assignee "@me" 2>/dev/null || true

    gh issue comment "$NUM" --repo "$REPO" \
      --body "🔄 **Restart déclenché** — branche supprimée, l'agent va réimplémenter depuis \`main\` au prochain cycle." 2>/dev/null || true

    tg "*🔄 Restart déclenché*
\`#$NUM\` — $TITLE
Branche \`$OLD_BRANCH\` supprimée. Réimplémentation au prochain cycle."

    # Mémoriser l'issue pour que process_issue() la reprenne directement
    # (évite le délai de propagation de l'index GitHub Search)
    echo "$NUM" >> "$PENDING_RESTART_FILE"
    log "Restart #$NUM préparé — en attente de traitement direct."
  done
}

# ══════════════════════════════════════════════════════════════════
# FONCTION : traiter une issue complète (étape par étape)
# Retourne :
#   0 = succès, on peut enchaîner
#   1 = erreur technique, stop
#   2 = token épuisé, stop
#   3 = aucune issue disponible, stop
# ══════════════════════════════════════════════════════════════════
process_issue() {
  local RESUMING=false
  local LAST_STEP="none"

  # ── Reprise ou nouvelle issue ? ──────────────────────────────
  if [ -f "$STATE_FILE" ]; then
    ISSUE_NUM=$(state_read issue_num)
    ISSUE_TITLE=$(state_read issue_title)
    BRANCH=$(state_read branch)
    LAST_STEP=$(state_read step)
    log "Reprise — issue #$ISSUE_NUM '$ISSUE_TITLE' — étape: $LAST_STEP"

    ISSUE_STATE=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json state -q '.state' 2>/dev/null || echo "UNKNOWN")
    if [ "$ISSUE_STATE" != "OPEN" ]; then
      log "Issue #$ISSUE_NUM fermée — abandon"
      state_clear
      return 0  # continuer avec la suivante
    fi
    RESUMING=true
    ISSUE_BODY=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json body -q '.body' 2>/dev/null || echo "")
  else
    # Nouvelle issue
    cd "$REPO_DIR"
    git fetch origin
    git checkout "$MAIN_BRANCH"
    git pull --ff-only origin "$MAIN_BRANCH"

    # Priorité : issues restartées ce cycle (évite le délai GitHub Search)
    if [ -f "$PENDING_RESTART_FILE" ]; then
      PENDING_NUM=$(head -1 "$PENDING_RESTART_FILE")
      # Retirer cette ligne du fichier
      sed -i '1d' "$PENDING_RESTART_FILE"
      [ ! -s "$PENDING_RESTART_FILE" ] && rm -f "$PENDING_RESTART_FILE"
      if [ -n "$PENDING_NUM" ]; then
        log "Reprise directe de l'issue restartée #$PENDING_NUM (bypass search)"
        ISSUE_NUM="$PENDING_NUM"
        ISSUE_TITLE=$(gh issue view "$PENDING_NUM" --repo "$REPO" --json title -q '.title' 2>/dev/null || echo "Issue #$PENDING_NUM")
        ISSUE_BODY=$(gh issue view  "$PENDING_NUM" --repo "$REPO" --json body  -q '.body'  2>/dev/null || echo "")
        SLUG=$(echo "$ISSUE_TITLE"           | tr '[:upper:]' '[:lower:]'           | sed 's/\[f\]//gi'           | sed 's/[^a-z0-9]/-/g'           | sed 's/--*/-/g'           | sed 's/^-\|-$//g'           | cut -c1-40)
        BRANCH="feature/${ISSUE_NUM}-${SLUG}"
        log "Issue restartée : #$ISSUE_NUM — $ISSUE_TITLE"
        gh issue edit "$ISSUE_NUM" --repo "$REPO" --add-assignee "@me" 2>/dev/null || true
        gh issue comment "$ISSUE_NUM" --repo "$REPO"           --body "🤖 Agent Claude Code reprend cette issue (restart). Réimplémentation depuis \`main\`..."
        tg "*🔄 Restart en cours*
\`#$ISSUE_NUM\` — $ISSUE_TITLE
Branche : \`$BRANCH\`"
        ISSUE_CLAIMED=true
        state_write "issue_claimed"
      fi
    fi

    if [ -z "${ISSUE_NUM:-}" ]; then
    log "Recherche d'une issue [F] non assignée (avec vérification des dépendances)..."

    # Récupère jusqu'à 20 issues pour pouvoir trier par dépendances
    ALL_ISSUES=$(gh issue list \
      --repo "$REPO" \
      --state open \
      --search "[F] in:title no:assignee -label:blocked -label:agent-skip -label:agent-done" \
      --limit 20 \
      --json number,title,body \
      2>/dev/null || echo "[]")

    if [ "$ALL_ISSUES" = "[]" ] || [ -z "$ALL_ISSUES" ]; then
      log "Aucune issue disponible."
      return 3
    fi

    # Trouver la première issue dont toutes les dépendances sont mergées
    SELECTED=""
    COUNT=$(echo "$ALL_ISSUES" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")

    for i in $(seq 0 $((COUNT - 1))); do
      CANDIDATE_NUM=$(echo "$ALL_ISSUES" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$i]['number'])")
      CANDIDATE_TITLE=$(echo "$ALL_ISSUES" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$i]['title'])")
      CANDIDATE_BODY=$(echo "$ALL_ISSUES" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$i]['body'] or '')")

      # Extraire les dépendances (format : "Depends-on: #12" ou "Depends-on: #12, #15")
      DEPS=$(echo "$CANDIDATE_BODY" | grep -oiP '(?<=depends-on:)[^\n]+' | tr ',' '\n' | grep -oP '\d+' || echo "")

      DEPS_OK=true
      for DEP_NUM in $DEPS; do
        # Vérifier si l'issue parente est fermée (= PR mergée ou résolue)
        DEP_STATE=$(gh issue view "$DEP_NUM" --repo "$REPO" --json state -q '.state' 2>/dev/null || echo "OPEN")
        if [ "$DEP_STATE" != "CLOSED" ]; then
          log "Issue #$CANDIDATE_NUM bloquée par #$DEP_NUM (encore ouverte)"
          DEPS_OK=false
          break
        fi
      done

      if [ "$DEPS_OK" = true ]; then
        SELECTED="$i"
        ISSUE_NUM="$CANDIDATE_NUM"
        ISSUE_TITLE="$CANDIDATE_TITLE"
        ISSUE_BODY="$CANDIDATE_BODY"
        break
      fi
    done

    if [ -z "$SELECTED" ]; then
      log "Toutes les issues disponibles sont bloquées par des dépendances non mergées."
      return 3
    fi
    fi  # fin du if [ -z "${ISSUE_NUM:-}" ]

    SLUG=$(echo "$ISSUE_TITLE" \
      | tr '[:upper:]' '[:lower:]' \
      | sed 's/\[f\]//gi' \
      | sed 's/[^a-z0-9]/-/g' \
      | sed 's/--*/-/g' \
      | sed 's/^-\|-$//g' \
      | cut -c1-40)
    BRANCH="feature/${ISSUE_NUM}-${SLUG}"

    if [ "${ISSUE_CLAIMED:-false}" != "true" ]; then
      log "Issue sélectionnée : #$ISSUE_NUM — $ISSUE_TITLE"
      gh issue edit "$ISSUE_NUM" --repo "$REPO" --add-assignee "@me"
      gh issue comment "$ISSUE_NUM" --repo "$REPO" \
        --body "🤖 Agent Claude Code a pris en charge cette issue. Implémentation en cours..."
      tg "*🤖 Nouvelle issue prise en charge*
\`#$ISSUE_NUM\` — $ISSUE_TITLE
Branche : \`$BRANCH\`"
      state_write "issue_claimed"
    fi
  fi

  cd "$REPO_DIR"

  # ── Étape 1 : branche ────────────────────────────────────────
  if [ "$LAST_STEP" = "none" ] || [ "$LAST_STEP" = "issue_claimed" ]; then
    log "Branche : $BRANCH"
    git fetch origin
    git checkout "$MAIN_BRANCH"
    git pull --ff-only origin "$MAIN_BRANCH"
    if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
      git checkout "$BRANCH"
    elif git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
      git checkout -b "$BRANCH" "origin/$BRANCH"
    else
      git checkout -b "$BRANCH"
    fi
    state_write "branch_created"
    LAST_STEP="branch_created"
  fi

  # S'assurer d'être sur la bonne branche
  [ "$(git rev-parse --abbrev-ref HEAD)" != "$BRANCH" ] && git checkout "$BRANCH"

  # ── Étape 2 : Claude Code ────────────────────────────────────
  if [ "$LAST_STEP" = "branch_created" ] || [ "$LAST_STEP" = "claude_interrupted" ]; then
    RESUME_NOTE=""
    [ "$LAST_STEP" = "claude_interrupted" ] && \
      RESUME_NOTE="Note : exécution précédente interrompue. Fais git status pour voir l'état, continue sans écraser ce qui est bien fait."

    PROMPT="Tu es un développeur de jeux vidéo travaillant sur 'The Door Beneath', roguelite en lanes (Godot 4.6, GDScript 2.0).

Lis d'abord CLAUDE.md pour comprendre l'architecture.
$RESUME_NOTE

## Issue #${ISSUE_NUM} : ${ISSUE_TITLE}

${ISSUE_BODY}

## Instructions
1. Lis CLAUDE.md
2. git status pour voir l'état actuel
3. Implémente la feature
4. Respecte le style GDScript existant
5. Pas de syntaxe invalide dans les .tscn
6. git commit : feat(#${ISSUE_NUM}): description courte

Ne lance pas Godot. Commit à la fin."

    local CLAUDE_LOG="/tmp/claude-output-${ISSUE_NUM}.log"
    state_write "claude_running"
    log "Lancement Claude Code..."

    set +e
    claude --dangerously-skip-permissions -p "$PROMPT" \
      --allowedTools "Read,Write,Edit,Bash(git *),Bash(ls *),Bash(find *),Glob,Grep" \
      2>&1 | tee "$CLAUDE_LOG"
    CLAUDE_EXIT=${PIPESTATUS[0]}
    set -e

    log "Claude terminé (exit: $CLAUDE_EXIT)"

    if [ "$CLAUDE_EXIT" -ne 0 ]; then
      if is_token_error "$CLAUDE_LOG"; then
        log "Quota/token épuisé — arrêt, reprise à la prochaine exécution"
        tg "*⏸ Tokens épuisés*
Issue \`#$ISSUE_NUM\` — $ISSUE_TITLE
Reprise automatique à la prochaine exécution (cron 2h)."
        state_write "claude_interrupted"
        return 2
      fi
      log "Erreur Claude (exit $CLAUDE_EXIT) — état sauvegardé"
      tg "*❌ Erreur Claude Code*
Issue \`#$ISSUE_NUM\` — $ISSUE_TITLE
Exit code : \`$CLAUDE_EXIT\`
Log : \`/tmp/claude-output-${ISSUE_NUM}.log\`"
      state_write "claude_interrupted"
      return 1
    fi

    state_write "claude_done"
    LAST_STEP="claude_done"
  fi

  # ── Étape 3 : push ───────────────────────────────────────────
  if [ "$LAST_STEP" = "claude_done" ] || [ "$LAST_STEP" = "push_failed" ]; then
    COMMITS_AHEAD=$(git rev-list --count "origin/$MAIN_BRANCH..HEAD" 2>/dev/null || echo "0")
    if [ "$COMMITS_AHEAD" = "0" ]; then
      log "Aucun commit créé — feature déjà implémentée ou rien à faire"
      gh label create "agent-skip" --repo "$REPO" --color "e4e669" \
        --description "Skippée par agent (déjà implémentée)" 2>/dev/null || true
      gh issue comment "$ISSUE_NUM" --repo "$REPO" \
        --body "⏭️ L'agent n'a rien commité — la feature semble déjà implémentée. Issue marquée \`agent-skip\` pour éviter une boucle. Vérification manuelle recommandée."
      gh issue edit "$ISSUE_NUM" --repo "$REPO" --remove-assignee "@me" --add-label "agent-skip"
      tg "*⏭️ Issue skippée*
\`#$ISSUE_NUM\` — $ISSUE_TITLE
Claude n'a rien commité (déjà implémenté ?). Label \`agent-skip\` ajouté."
      state_clear
      return 0
    fi
    state_write "push_failed"
    log "Push branche $BRANCH..."
    git push -u origin "$BRANCH"
    state_write "pushed"
    LAST_STEP="pushed"
  fi

  # ── Étape 4 : PR ─────────────────────────────────────────────
  if [ "$LAST_STEP" = "pushed" ] || [ "$LAST_STEP" = "pr_failed" ]; then
    EXISTING_PR=$(gh pr list --repo "$REPO" --head "$BRANCH" --json url -q '.[0].url' 2>/dev/null || echo "")
    if [ -n "$EXISTING_PR" ]; then
      PR_URL="$EXISTING_PR"
      log "PR existante : $PR_URL"
    else
      state_write "pr_failed"
      log "Création PR..."
      PR_URL=$(gh pr create \
        --repo "$REPO" \
        --title "feat: $ISSUE_TITLE" \
        --body "## Résumé
Implémentation automatique par agent Claude Code.

Closes #${ISSUE_NUM}

## À vérifier avant merge
- [ ] Tester en jeu (Godot 4.6)
- [ ] Pas de régression sur les salles existantes
- [ ] SPACE/room clear fonctionne toujours

🤖 *Généré automatiquement par agent.sh*" \
        --base "$MAIN_BRANCH" \
        --head "$BRANCH")
    fi
    state_write "pr_created"
    LAST_STEP="pr_created"
  fi

  # ── Étape 5 : finaliser ──────────────────────────────────────
  if [ "$LAST_STEP" = "pr_created" ]; then
    gh issue comment "$ISSUE_NUM" --repo "$REPO" \
      --body "✅ Implémentation terminée !

**Pull Request :** $PR_URL

Tester dans Godot 4.6 puis merger."

    gh label create "agent-done" --repo "$REPO" --color "0075ca" \
      --description "Traité par agent Claude Code" 2>/dev/null || true
    gh issue edit "$ISSUE_NUM" --repo "$REPO" --add-label "agent-done"

    tg "*✅ Feature terminée !*
\`#$ISSUE_NUM\` — $ISSUE_TITLE

*PR :* $PR_URL

À tester dans Godot 4.6, puis merger si c'est bon 👍"

    log "✓ Issue #$ISSUE_NUM traitée → $PR_URL"
    state_clear
    git checkout "$MAIN_BRANCH"
  fi

  return 0
}

# ══════════════════════════════════════════════════════════════════
# BOUCLE PRINCIPALE
# ══════════════════════════════════════════════════════════════════
log "=== Démarrage agent — max $MAX_ISSUES issues ==="
tg "*🚀 Agent démarré*
Recherche d'issues \`[F]\` à traiter..."

ISSUES_DONE=0
SESSION_START=$(date '+%H:%M')

while [ "$ISSUES_DONE" -lt "$MAX_ISSUES" ]; do
  handle_restart_issues
  process_issue
  EXIT_CODE=$?

  case $EXIT_CODE in
    0)  # succès — chercher la suivante
        ISSUES_DONE=$((ISSUES_DONE + 1))
        log "Issue traitée ($ISSUES_DONE/$MAX_ISSUES) — recherche de la suivante..."
        sleep 2
        ;;
    2)  # token épuisé
        log "Tokens épuisés — arrêt propre. Reprise à la prochaine exécution."
        tg "*📊 Rapport de session*
🕐 $SESSION_START → $(date '+%H:%M')
✅ Issues traitées : $ISSUES_DONE
⏸ Arrêt : tokens épuisés — reprise dans ~2h"
        exit 0
        ;;
    3)  # aucune issue disponible
        log "Aucune issue disponible — fin de session ($ISSUES_DONE issues traitées)."
        if [ "$ISSUES_DONE" -gt 0 ]; then
          tg "*📊 Rapport de session*
🕐 $SESSION_START → $(date '+%H:%M')
✅ Issues traitées : $ISSUES_DONE
💤 Aucune autre issue en attente"
        else
          tg "*💤 Aucune issue à traiter*
Prochaine vérification dans 2h."
        fi
        exit 0
        ;;
    *)  # erreur
        log "Erreur — arrêt ($ISSUES_DONE issues traitées)."
        tg "*🔴 Erreur agent*
🕐 $SESSION_START → $(date '+%H:%M')
✅ Issues traitées : $ISSUES_DONE
❌ Arrêt sur erreur — vérifier \`/var/log/claude-agent.log\`"
        exit 1
        ;;
  esac
done

log "Maximum atteint ($MAX_ISSUES issues) — fin de session."
tg "*📊 Rapport de session*
🕐 $SESSION_START → $(date '+%H:%M')
✅ Issues traitées : $ISSUES_DONE/$MAX_ISSUES
🏁 Maximum par session atteint"
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          