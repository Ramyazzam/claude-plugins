#!/usr/bin/env bash
# living-docs / SessionStart hook — surfaces current project state by printing
# the most recent entry from the changelog (notes file), so every session opens
# with up-to-date context.
#
# Configure per-repo via .claude/livingdocs.json (all optional):
#   { "notesFile": "CHANGELOG.md",   // else auto-detects conversation_notes.md / CHANGELOG.md / NOTES.md
#     "entryHeading": "## " }         // top-level entry heading; stops at the 2nd one
set -uo pipefail

root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
cd "$root" 2>/dev/null || exit 0

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
# Entries are prepended newest-first; print the intro through the latest entry
# block (stop at the 2nd top-level entry heading).
awk -v h="$heading" 'BEGIN{c=0} $0 ~ h {c++} c>=2{exit} {print}' "$root/$notes_rel"
echo
echo "(Full history in $notes_rel.)"
exit 0
