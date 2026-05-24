# ramy-plugins

A small [Claude Code](https://code.claude.com) plugin marketplace.

## Plugins

### living-docs

Self-maintaining project context, driven entirely by deterministic shell hooks — **no LLM, no network at runtime.**

- **SessionStart** (`notes-inventory.sh`) — prints the most recent entry from the repo's notes/changelog file, so every session opens with the current state.
- **Stop** (`notes-autolog.sh`) — regenerates a single idempotent `AUTO-DRAFT` block in the notes file listing the uncommitted files whose paths match a configured pattern (plus optional extracted numeric IDs). The block is *replaced* (never duplicated) on each run and disappears once the work is committed. You enrich it with context + status and delete the markers before committing the real entry.

## Install

```bash
# one-time: register this marketplace
claude plugin marketplace add ramyazzam/claude-plugins

# install + enable the plugin
claude plugin install living-docs@ramy-plugins
```

Or commit the equivalent to a repo's `.claude/settings.json` so it travels to teammates and cloud sessions:

```json
{
  "extraKnownMarketplaces": {
    "ramy-plugins": { "source": { "source": "github", "repo": "ramyazzam/claude-plugins" } }
  },
  "enabledPlugins": { "living-docs@ramy-plugins": true }
}
```

## Per-repo configuration — `.claude/livingdocs.json`

All keys are optional except `contentPattern` (required for the Stop hook's auto-draft):

| Key | Meaning |
| --- | --- |
| `notesFile` | Relative path to the changelog file. If omitted, auto-detects `conversation_notes.md` → `CHANGELOG.md` → `NOTES.md`. The Stop hook creates this file if missing. |
| `contentPattern` | `grep -E` regex matched against changed file paths. **Required** for the Stop hook; without it the auto-draft is a no-op. |
| `imageIdPattern` | Optional `grep -E` regex; trailing digits in matches are extracted, de-duped, and listed beside each file (useful for asset/issue IDs). |
| `entryHeading` | Top-level entry heading marker (default `"## "`). SessionStart prints from the top of the file through the latest entry, stopping at the 2nd heading. |

Example for a TypeScript/JS app:

```json
{
  "notesFile": "CHANGELOG.md",
  "contentPattern": "(^|/)src/.*\\.(ts|tsx|js|jsx)$",
  "imageIdPattern": "ISSUE-[0-9]+",
  "entryHeading": "## "
}
```

Tune `contentPattern` per language (e.g. `\.py$`, `\.go$`, `\.rs$`).

## Requirements

`bash` and `jq` on `PATH` (the hooks read `livingdocs.json` with `jq`). `git` is used to detect uncommitted files.
