#!/usr/bin/env bash
# living-docs / SessionStart hook — surfaces current project state.
#
# Priority (first match wins):
#   1. `.agent-memory/sessions/YYYY-MM-DD.md` for today — pick up from today's work
#   2. The most recent file in `.agent-memory/sessions/` — pick up from last session
#   3. `.agent-memory/index.md` — the curated table of contents
#   4. Legacy: most recent entry in CHANGELOG.md / conversation_notes.md / NOTES.md
#
# Goal: every Claude Code session opens with "where we left off" already on
# screen. Deterministic, no LLM, no network.
#
# Configure per-repo via .claude/livingdocs.json (all optional):
#   { "notesFile": "CHANGELOG.md",   // legacy path only
#     "entryHeading": "## " }         // legacy: heading style for the chunker
set -uo pipefail

root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
cd "$root" 2>/dev/null || exit 0

# --- Modern path: .agent-memory/ -------------------------------------------
if [ -d "$root/.agent-memory" ]; then
  today="$(date +%F)"
  today_file="$root/.agent-memory/sessions/$today.md"
  if [ -f "$today_file" ]; then
    echo "## Project state — picking up today's session ($today)"
    echo
    cat "$today_file"
    echo
    echo "(Full session history in .agent-memory/sessions/. Decisions: .agent-memory/decisions/.)"
    exit 0
  fi

  # Most recent prior session
  latest=""
  if [ -d "$root/.agent-memory/sessions" ]; then
    latest="$(ls -1t "$root/.agent-memory/sessions"/*.md 2>/dev/null | head -1 || true)"
  fi
  if [ -n "$latest" ] && [ -f "$latest" ]; then
    echo "## Project state — last session ($(basename "$latest" .md))"
    echo
    cat "$latest"
    echo
    echo "(Full session history in .agent-memory/sessions/. Decisions: .agent-memory/decisions/.)"
    exit 0
  fi

  # Fallback: index.md
  if [ -f "$root/.agent-memory/index.md" ]; then
    echo "## Project state — .agent-memory/ is set up; no session entries yet"
    echo
    cat "$root/.agent-memory/index.md"
    echo
    echo "(Add session entries to .agent-memory/sessions/YYYY-MM-DD.md.)"
    exit 0
  fi
fi

# --- Legacy path: project-root notes file ----------------------------------
notes_rel=""
heading='^## '
cfg="$root/.claude/livingdocs.json"
if [ -f "$cfg" ] && command -v jq >/dev/null 2>&1; then
  notes_rel="$(jq -r '.notesFile // empty' "$cfg" 2>/dev/null)"
  v="$(jq -r '.entryHeading // empty' "$cfg" 2>/dev/null)"
  [ -n "$v" ] && heading="^$(printf '%s' "$v" | sed 's/[.[\*^$]/\\&/g')"
fi
if [ -z "$notes_rel" ]; then
  for cand in conversation_notes.md CHANGELOG.md NOTES.md; do
    [ -f "$root/$cand" ] && { notes_rel="$cand"; break; }
  done
fi
[ -n "$notes_rel" ] && [ -f "$root/$notes_rel" ] || exit 0

echo "## Project state — most recent $notes_rel entry"
echo
awk -v h="$heading" 'BEGIN{c=0} $0 ~ h {c++} c>=2{exit} {print}' "$root/$notes_rel"
echo
echo "(Full history in $notes_rel.)"
exit 0
