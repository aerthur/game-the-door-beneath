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
LOG_PREFIX="[agent]"

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
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $LOG_PREFIX $*"; }

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
gh label create "agent-retry" --repo "$REPO" --color "f9d0c4" \
  --description "Aucun commit à la 1ère tentative — 2ème essai au prochain cycle" 2>/dev/null || true
gh label create "agent-fix" --repo "$REPO" --color "d93f0b" \
  --description "Bug trouvé en test — à corriger par l'agent sur la branche" 2>/dev/null || true

# ── Restart : réinitialise une issue pour la refaire depuis zéro ──
handle_restart_issues() {
  local RESTART_LIST COUNT

  RESTART_LIST=$(gh issue list \
    --repo "$REPO" \
    --state open \
    --label "agent-restart" \
    --json number,title,labels \
    --limit 5 2>/dev/null || echo "[]")

  [ "$RESTART_LIST" = "[]" ] || [ -z "$RESTART_LIST" ] && return 0

  COUNT=$(echo "$RESTART_LIST" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
  log "[$COUNT issue(s) marquées agent-restart]"

  for i in $(seq 0 $((COUNT - 1))); do
    local NUM TITLE SLUG OLD_BRANCH

    NUM=$(echo "$RESTART_LIST"   | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$i]['number'])")
    TITLE=$(echo "$RESTART_LIST" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$i]['title'])")

    # agent-skip est prioritaire sur agent-restart — on ignore sans toucher à rien
    HAS_SKIP=$(echo "$RESTART_LIST" | python3 -c "
import sys,json
d=json.load(sys.stdin)[$i]
labels=[l['name'] for l in d.get('labels',[])]
print('true' if 'agent-skip' in labels else 'false')
")
    if [ "$HAS_SKIP" = "true" ]; then
      log "Issue #$NUM ignorée — agent-skip est prioritaire sur agent-restart."
      gh issue edit "$NUM" --repo "$REPO" --remove-label "agent-restart" 2>/dev/null || true
      continue
    fi

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

# ── Fix : corrige un bug signalé sur une branche feature existante ──
handle_fix_issues() {
  local FIX_LIST COUNT

  FIX_LIST=$(gh issue list \
    --repo "$REPO" \
    --state open \
    --label "agent-fix" \
    --json number,title \
    --limit 5 2>/dev/null || echo "[]")

  [ "$FIX_LIST" = "[]" ] || [ -z "$FIX_LIST" ] && return 0

  COUNT=$(echo "$FIX_LIST" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
  log "[$COUNT issue(s) marquées agent-fix]"

  for i in $(seq 0 $((COUNT - 1))); do
    local NUM TITLE SLUG FIX_BRANCH

    NUM=$(echo "$FIX_LIST"   | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$i]['number'])")
    TITLE=$(echo "$FIX_LIST" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$i]['title'])")

    SLUG=$(echo "$TITLE" \
      | tr '[:upper:]' '[:lower:]' \
      | sed 's/\[f\]//gi' \
      | sed 's/[^a-z0-9]/-/g' \
      | sed 's/--*/-/g' \
      | sed 's/^-\|-$//g' \
      | cut -c1-40)
    FIX_BRANCH="feature/${NUM}-${SLUG}"

    cd "$REPO_DIR"
    git fetch origin 2>/dev/null || true

    if ! git ls-remote --exit-code --heads origin "$FIX_BRANCH" > /dev/null 2>&1; then
      log "Branche $FIX_BRANCH introuvable pour #$NUM — agent-fix ignoré"
      gh issue comment "$NUM" --repo "$REPO" \
        --body "⚠️ Branche \`$FIX_BRANCH\` introuvable — impossible de corriger automatiquement. Vérification manuelle nécessaire." 2>/dev/null || true
      gh issue edit "$NUM" --repo "$REPO" --remove-label "agent-fix" 2>/dev/null || true
      continue
    fi

    # Récupérer les derniers commentaires pour contexte du bug
    local BUG_CONTEXT
    BUG_CONTEXT=$(gh issue view "$NUM" --repo "$REPO" --json comments \
      -q '.comments[-5:] | map("**" + .author.login + "** :\n" + .body) | join("\n\n---\n\n")' \
      2>/dev/null || echo "")
    if [ -z "$BUG_CONTEXT" ]; then
      log "⚠️ Aucun commentaire récupéré pour #$NUM — Claude travaillera sans contexte de bug"
      BUG_CONTEXT="Pas de commentaires disponibles. Analyse le code de la branche pour détecter le problème."
    else
      log "Contexte bug récupéré (${#BUG_CONTEXT} caractères)"
    fi

    log "════════════════════════════════════════"
    log "Fix bug #$NUM — $TITLE (branche: $FIX_BRANCH)"
    log "Checkout + pull $FIX_BRANCH..."
    git checkout "$FIX_BRANCH"
    git pull origin "$FIX_BRANCH" 2>/dev/null || true
    log "Branche prête — $(git log --oneline -1)"

    gh issue comment "$NUM" --repo "$REPO" \
      --body "🔧 **Correction en cours** — Agent Claude Code prend en charge le bug signalé." 2>/dev/null || true

    tg "*🔧 Correction bug*
\`#$NUM\` — $TITLE
Branche : \`$FIX_BRANCH\`"

    local FIX_PROMPT="Tu es un développeur de jeux vidéo travaillant sur 'The Door Beneath', roguelite en lanes (Godot 4.6, GDScript 2.0).

Lis d'abord CLAUDE.md pour comprendre l'architecture.

## Issue #${NUM} : ${TITLE}

Un bug a été signalé pendant les tests. Voici le contexte des derniers commentaires de l'issue :

${BUG_CONTEXT}

## Instructions
1. Lis CLAUDE.md
2. git status et git log --oneline -5 pour comprendre l'état de la branche
3. Analyse précisément le bug décrit dans les commentaires ci-dessus
4. Corrige le bug sans casser les autres fonctionnalités
5. Lance les tests unitaires : godot --headless --script addons/gut/gut_cmdln.gd -gconfig=.gutconfig.json
   - Tous les tests doivent passer. Si certains échouent, corrige jusqu'à ce qu'ils passent tous.
6. git commit : fix(#${NUM}): description courte du correctif

Ne lance pas Godot en mode jeu. Commit à la fin."

    local FIX_LOG="/tmp/claude-fix-${NUM}.log"
    local FIX_START
    FIX_START=$(date +%s)
    log "Lancement Claude Code (log: $FIX_LOG)..."

    set +e
    claude --dangerously-skip-permissions -p "$FIX_PROMPT" \
      --allowedTools "Read,Write,Edit,Bash(git *),Bash(ls *),Bash(find *),Bash(godot *),Glob,Grep" \
      2>&1 | tee "$FIX_LOG"
    local FIX_EXIT=${PIPESTATUS[0]}
    set -e

    local FIX_DURATION=$(( $(date +%s) - FIX_START ))
    log "Fix terminé (exit: $FIX_EXIT, durée: ${FIX_DURATION}s)"

    if [ "$FIX_EXIT" -ne 0 ]; then
      if is_token_error "$FIX_LOG"; then
        log "Tokens épuisés pendant fix #$NUM — arrêt"
        tg "*⏸ Tokens épuisés (fix bug)*
Issue \`#$NUM\` — $TITLE
Reprise automatique à la prochaine exécution."
        git checkout "$MAIN_BRANCH" 2>/dev/null || true
        return 2
      fi
      log "Erreur lors du fix #$NUM (exit $FIX_EXIT)"
      gh issue comment "$NUM" --repo "$REPO" \
        --body "❌ L'agent a rencontré une erreur lors de la correction (exit $FIX_EXIT). Vérification manuelle nécessaire." 2>/dev/null || true
      tg "*❌ Erreur fix bug*
\`#$NUM\` — $TITLE
Exit code : \`$FIX_EXIT\`"
      git checkout "$MAIN_BRANCH" 2>/dev/null || true
      continue
    fi

    local COMMITS_AHEAD
    COMMITS_AHEAD=$(git rev-list --count "origin/$FIX_BRANCH..HEAD" 2>/dev/null || echo "0")

    if [ "$COMMITS_AHEAD" != "0" ]; then
      log "Push $COMMITS_AHEAD commit(s) sur $FIX_BRANCH..."
      git push origin "$FIX_BRANCH"
      log "Push OK"
      gh issue edit "$NUM" --repo "$REPO" --remove-label "agent-fix" 2>/dev/null || true
      gh issue comment "$NUM" --repo "$REPO" \
        --body "✅ **Bug corrigé** — $COMMITS_AHEAD commit(s) poussé(s) sur \`$FIX_BRANCH\`. Retester !" 2>/dev/null || true
      tg "*✅ Bug corrigé*
\`#$NUM\` — $TITLE
$COMMITS_AHEAD commit(s) → \`$FIX_BRANCH\`
Retester !"
    else
      log "Aucun commit après fix #$NUM"
      gh issue comment "$NUM" --repo "$REPO" \
        --body "⚠️ L'agent n'a rien commité pour ce correctif. Vérification manuelle nécessaire." 2>/dev/null || true
      gh issue edit "$NUM" --repo "$REPO" --remove-label "agent-fix" 2>/dev/null || true
    fi

    git checkout "$MAIN_BRANCH" 2>/dev/null || true
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
  ISSUE_CLAIMED=false  # reset global pour éviter le carry-over entre issues
  ISSUE_NUM=""
  ISSUE_TITLE=""
  BRANCH=""

  # ── Reprise ou nouvelle issue ? ──────────────────────────────
  if [ -f "$STATE_FILE" ]; then
    ISSUE_NUM=$(state_read issue_num)
    ISSUE_TITLE=$(state_read issue_title)
    BRANCH=$(state_read branch)
    LAST_STEP=$(state_read step)
    log "Reprise — issue #$ISSUE_NUM '$ISSUE_TITLE' — étape: $LAST_STEP"

    ISSUE_INFO=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json state,labels 2>/dev/null || echo "{}")
    ISSUE_STATE=$(echo "$ISSUE_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('state','UNKNOWN'))")
    ISSUE_LABELS=$(echo "$ISSUE_INFO" | python3 -c "import sys,json; print(','.join(l['name'] for l in json.load(sys.stdin).get('labels',[])))")

    if [ "$ISSUE_STATE" != "OPEN" ]; then
      log "Issue #$ISSUE_NUM fermée — abandon"
      state_clear
      return 0  # continuer avec la suivante
    fi
    if echo "$ISSUE_LABELS" | grep -q "agent-skip"; then
      log "Issue #$ISSUE_NUM a le label agent-skip — abandon de la reprise"
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
        # Vérifier que l'issue n'a pas été marquée agent-skip entre-temps
        PENDING_LABELS=$(gh issue view "$PENDING_NUM" --repo "$REPO" --json labels \
          -q '[.labels[].name] | join(",")' 2>/dev/null || echo "")
        if echo "$PENDING_LABELS" | grep -q "agent-skip"; then
          log "Issue #$PENDING_NUM ignorée depuis PENDING_RESTART_FILE — label agent-skip présent."
          PENDING_NUM=""
        fi
      fi
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
        # Ignorer si déjà traitée dans cette session (évite re-pick dû au lag GitHub Search)
        if echo " $ISSUES_PROCESSED_THIS_SESSION " | grep -q " $CANDIDATE_NUM "; then
          log "Issue #$CANDIDATE_NUM déjà traitée cette session — ignorée"
          continue
        fi
        SELECTED="$i"
        ISSUE_NUM="$CANDIDATE_NUM"
        ISSUE_TITLE="$CANDIDATE_TITLE"
        ISSUE_BODY="$CANDIDATE_BODY"
        break
      fi
    done

    if [ -z "$SELECTED" ]; then
      if [ -n "$ISSUES_PROCESSED_THIS_SESSION" ]; then
        log "Aucune issue restante (bloquées par dépendances ou déjà traitées cette session)."
      else
        log "Toutes les issues disponibles sont bloquées par des dépendances non mergées."
      fi
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
      log "════════════════════════════════════════"
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
  if [ "$LAST_STEP" = "branch_created" ] || [ "$LAST_STEP" = "claude_interrupted" ] || [ "$LAST_STEP" = "claude_running" ]; then
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
6. Lance les tests unitaires : godot --headless --script addons/gut/gut_cmdln.gd -gconfig=.gutconfig.json
   - Tous les tests doivent passer. Si certains échouent, corrige le code jusqu'à ce qu'ils passent tous.
   - Enrichis ou crée les tests unitaires couvrant la logique de la feature implémentée (dans test/unit/).
7. Mets à jour CLAUDE.md pour refléter les changements apportés (nouvelles fonctions publiques, systèmes, conventions, champs de données).
8. git commit : feat(#${ISSUE_NUM}): description courte (inclure les tests et la doc dans le même commit ou en commits séparés)

Ne lance pas Godot en mode jeu. Commit à la fin."

    local CLAUDE_LOG="/tmp/claude-output-${ISSUE_NUM}.log"
    state_write "claude_running"
    local CLAUDE_START
    CLAUDE_START=$(date +%s)
    log "Lancement Claude Code..."

    set +e
    claude --dangerously-skip-permissions -p "$PROMPT" \
      --allowedTools "Read,Write,Edit,Bash(git *),Bash(ls *),Bash(find *),Bash(godot *),Glob,Grep" \
      2>&1 | tee "$CLAUDE_LOG"
    CLAUDE_EXIT=${PIPESTATUS[0]}
    set -e

    local CLAUDE_DURATION=$(( $(date +%s) - CLAUDE_START ))
    log "Claude terminé (exit: $CLAUDE_EXIT, durée: ${CLAUDE_DURATION}s)"

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
    log "Commits en avance sur $MAIN_BRANCH : $COMMITS_AHEAD"
    if [ "$COMMITS_AHEAD" = "0" ]; then
      # Si une PR existe déjà, la feature est déjà implémentée → agent-done direct
      EXISTING_PR_CHECK=$(gh pr list --repo "$REPO" --head "$BRANCH" --json url -q '.[0].url' 2>/dev/null || echo "")
      if [ -n "$EXISTING_PR_CHECK" ]; then
        log "Aucun commit mais PR existante ($EXISTING_PR_CHECK) — issue déjà traitée"
        gh label create "agent-done" --repo "$REPO" --color "0075ca" \
          --description "Traité par agent Claude Code" 2>/dev/null || true
        gh issue edit "$ISSUE_NUM" --repo "$REPO" \
          --add-label "agent-done" \
          --remove-assignee "@me" 2>/dev/null || true
        gh issue comment "$ISSUE_NUM" --repo "$REPO" \
          --body "✅ Feature déjà implémentée — PR existante : $EXISTING_PR_CHECK. Issue marquée \`agent-done\`." 2>/dev/null || true
        tg "*✅ Issue déjà traitée*
\`#$ISSUE_NUM\` — $ISSUE_TITLE
PR : $EXISTING_PR_CHECK
Marquée \`agent-done\`."
        state_clear
        return 0
      fi

      # Vérifier si c'est déjà la 2ème tentative vide (label agent-retry présent)
      HAS_RETRY=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json labels \
        -q '[.labels[].name] | index("agent-retry") != null' 2>/dev/null || echo "false")

      if [ "$HAS_RETRY" = "true" ]; then
        log "Aucun commit (2ème tentative) — feature skippée définitivement"
        gh label create "agent-skip" --repo "$REPO" --color "e4e669" \
          --description "Skippée par agent (déjà implémentée)" 2>/dev/null || true
        gh issue comment "$ISSUE_NUM" --repo "$REPO" \
          --body "⏭️ L'agent n'a rien commité lors de deux tentatives consécutives. Issue marquée \`agent-skip\` — vérification manuelle recommandée."
        gh issue edit "$ISSUE_NUM" --repo "$REPO" \
          --remove-assignee "@me" \
          --remove-label "agent-retry" \
          --add-label "agent-skip"
        tg "*⏭️ Issue skippée (2ème tentative vide)*
\`#$ISSUE_NUM\` — $ISSUE_TITLE
Label \`agent-skip\` ajouté."
      else
        log "Aucun commit (1ère tentative) — retry au prochain cycle"
        gh issue comment "$ISSUE_NUM" --repo "$REPO" \
          --body "⚠️ L'agent n'a rien commité (interruption ou feature déjà là ?). Nouvelle tentative au prochain cycle. Si ce n'est pas souhaité, ajoutez \`agent-skip\` manuellement."
        gh issue edit "$ISSUE_NUM" --repo "$REPO" \
          --remove-assignee "@me" \
          --add-label "agent-retry"
        tg "*⚠️ Issue sans commit — retry prévu*
\`#$ISSUE_NUM\` — $ISSUE_TITLE
Prochaine tentative au prochain cycle."
      fi
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
PAUSE_FILE="$REPO_DIR/.agent_paused"

# ── Pause manuelle ────────────────────────────────────────────────
if [ -f "$PAUSE_FILE" ]; then
  PAUSE_MSG=$(cat "$PAUSE_FILE" 2>/dev/null || echo "")
  log "Agent en pause — $(date '+%Y-%m-%d %H:%M'). ${PAUSE_MSG:+Raison : $PAUSE_MSG}"
  tg "*⏸ Agent en pause*
${PAUSE_MSG:-Pause manuelle active.}
Supprimez \`.agent_paused\` pour reprendre."
  exit 0
fi

log "=== Démarrage agent — max $MAX_ISSUES issues ==="
tg "*🚀 Agent démarré*
Recherche d'issues \`[F]\` à traiter..."

ISSUES_DONE=0
SESSION_START=$(date '+%H:%M')
ISSUES_PROCESSED_THIS_SESSION=""  # liste séparée par espaces pour éviter le re-pick

while [ "$ISSUES_DONE" -lt "$MAX_ISSUES" ]; do
  handle_restart_issues
  handle_fix_issues
  set +e
  process_issue
  EXIT_CODE=$?
  set -e

  case $EXIT_CODE in
    0)  # succès — chercher la suivante
        ISSUES_DONE=$((ISSUES_DONE + 1))
        # Mémoriser l'issue pour éviter le re-pick dans la même session
        [ -n "${ISSUE_NUM:-}" ] && ISSUES_PROCESSED_THIS_SESSION="$ISSUES_PROCESSED_THIS_SESSION $ISSUE_NUM"
        log "Issue traitée ($ISSUES_DONE/$MAX_ISSUES) — recherche de la suivante..."
        log "────────────────────────────────────────"
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
                                                                                                                                                                                                   