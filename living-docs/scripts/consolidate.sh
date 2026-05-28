#!/usr/bin/env bash
# living-docs / consolidate — OPT-IN narrative fill via LLM.
#
# Reads .agent-memory/sessions/YYYY-MM-DD.md (today by default, or pass a
# date as $1) and rewrites the LLM-NARRATIVE block from today's git context
# (commits + file changes). The AUTO-DERIVED block and any hand-written
# content outside the LLM-NARRATIVE markers are preserved.
#
# Auth (first match wins):
#   1. `claude -p` if the Claude Code CLI is on PATH — uses your existing
#      Claude Code auth, zero config.
#   2. $ANTHROPIC_API_KEY — direct Anthropic API call (claude-haiku-4-5).
#   3. $OPENAI_API_KEY (or $LIVING_DOCS_LLM_API_KEY) — OpenAI-compatible.
#      Override model with $LIVING_DOCS_LLM_MODEL, endpoint with
#      $LIVING_DOCS_LLM_BASE_URL.
#
# This is the only script in the plugin that touches the network or an LLM.
# It is NEVER auto-invoked by hooks — run it on demand:
#   bash "$CLAUDE_PLUGIN_ROOT/scripts/consolidate.sh"           # today
#   bash "$CLAUDE_PLUGIN_ROOT/scripts/consolidate.sh 2026-05-28"
set -uo pipefail

date="${1:-$(date +%F)}"
root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -z "$root" ] && { echo "consolidate: not in a git repo and CLAUDE_PROJECT_DIR unset" >&2; exit 1; }

sess_file="$root/.agent-memory/sessions/$date.md"
if [ ! -f "$sess_file" ]; then
  echo "consolidate: no session file at $sess_file (run a Stop first to create the skeleton)" >&2
  exit 1
fi

# --- Gather context --------------------------------------------------------
cd "$root" 2>/dev/null || exit 1
commits="$(git log --since="$date 00:00:00" --until="$date 23:59:59" \
  --pretty=format:'%h %s%n%b%n---' 2>/dev/null || true)"
files_changed="$(git log --since="$date 00:00:00" --until="$date 23:59:59" \
  --name-status --pretty=format:'commit:%h' 2>/dev/null || true)"
uncommitted="$({ git diff --name-only HEAD 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } | sort -u)"

# Per-commit short diffs (truncated) for richer context
diffs="$(git log --since="$date 00:00:00" --until="$date 23:59:59" \
  --pretty=format:'=== commit %h: %s ===' -p --stat-width=120 -U2 2>/dev/null \
  | head -c 12000 || true)"

if [ -z "$commits" ] && [ -z "$uncommitted" ]; then
  echo "consolidate: no commits or uncommitted work for $date — nothing to summarise" >&2
  exit 0
fi

# --- Build the prompt ------------------------------------------------------
prompt="$(cat <<EOF
You are filling in the narrative for a developer's daily session log.

Project: $(basename "$root")
Date: $date
Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null)

Today's commits on this branch (message and body):
$commits

File-level changes per commit:
$files_changed

Uncommitted in working tree:
$uncommitted

Per-commit diffs (truncated to 12k chars):
$diffs

Write two short markdown sections — and ONLY those sections, with no preamble or closing remarks. Use this exact structure:

### What we did

(2–5 concrete bullets. Reference file/feature/function names where it helps. No fluff; describe the actual changes.)

### Why it matters

(1–2 short paragraphs. The motivation — what problem this addresses, what it unlocks, what risk it removes. If the intent isn't clear from the diffs, write exactly one line: "_(intent unclear from diffs alone — add the narrative manually)_".)
EOF
)"

# --- Pick LLM provider -----------------------------------------------------
response=""
if command -v claude >/dev/null 2>&1; then
  # Use Claude Code CLI in non-interactive mode — leverages existing auth.
  response="$(printf '%s' "$prompt" | claude -p 2>/dev/null || true)"
fi

if [ -z "$response" ] && [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  model="${LIVING_DOCS_LLM_MODEL:-claude-haiku-4-5-20251001}"
  body="$(jq -n --arg model "$model" --arg prompt "$prompt" \
    '{model: $model, max_tokens: 1024, messages: [{role:"user", content: $prompt}]}')"
  response="$(curl -sS https://api.anthropic.com/v1/messages \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    --data "$body" 2>/dev/null | jq -r '.content[0].text // empty')"
fi

if [ -z "$response" ] && { [ -n "${OPENAI_API_KEY:-}" ] || [ -n "${LIVING_DOCS_LLM_API_KEY:-}" ]; }; then
  base="${LIVING_DOCS_LLM_BASE_URL:-${OPENAI_BASE_URL:-https://api.openai.com/v1}}"
  key="${OPENAI_API_KEY:-$LIVING_DOCS_LLM_API_KEY}"
  model="${LIVING_DOCS_LLM_MODEL:-gpt-4o-mini}"
  body="$(jq -n --arg model "$model" --arg prompt "$prompt" \
    '{model: $model, messages: [{role:"user", content: $prompt}]}')"
  response="$(curl -sS "$base/chat/completions" \
    -H "Authorization: Bearer $key" \
    -H "Content-Type: application/json" \
    --data "$body" 2>/dev/null | jq -r '.choices[0].message.content // empty')"
fi

if [ -z "$response" ]; then
  cat >&2 <<MSG
consolidate: no LLM available. Set one of:
  - Install Claude Code CLI ('claude' on PATH) — uses your existing auth
  - export ANTHROPIC_API_KEY=...
  - export OPENAI_API_KEY=... (or LIVING_DOCS_LLM_API_KEY for OpenAI-compat)
MSG
  exit 1
fi

# --- Splice into the session file -----------------------------------------
# Replace contents between LLM-NARRATIVE:START and :END markers. If the
# markers don't exist (older session file), insert a fresh block right after
# the top-level heading.
tmp="$(mktemp)"
if grep -q '<!-- LLM-NARRATIVE:START' "$sess_file"; then
  awk -v body="$response" '
    BEGIN { skip = 0; replaced = 0 }
    /<!-- LLM-NARRATIVE:START/ {
      print
      print body
      skip = 1
      replaced = 1
      next
    }
    /<!-- LLM-NARRATIVE:END/ { skip = 0; print; next }
    skip == 0 { print }
    END { if (!replaced) exit 2 }
  ' "$sess_file" > "$tmp"
else
  awk -v body="$response" -v emitted=0 '
    { print }
    !emitted && /^# / {
      print ""
      print "<!-- LLM-NARRATIVE:START — `consolidate.sh` rewrites between these markers. Edit OUTSIDE to keep your changes. -->"
      print body
      print "<!-- LLM-NARRATIVE:END -->"
      emitted = 1
    }
  ' "$sess_file" > "$tmp"
fi
mv "$tmp" "$sess_file"

echo "consolidate: rewrote LLM-NARRATIVE block in $sess_file" >&2
exit 0
