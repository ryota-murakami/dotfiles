# Memory Naming Conventions

Standard key prefixes for Serena MCP memories. Consistent naming enables
the `load` skill to discover and prioritize memories automatically.

## Key Format

`<prefix>_<descriptor>` — descriptor uses lowercase, words separated by hyphens.

## Prefix Table

| Prefix | Cardinality | Purpose | Example |
|--------|-------------|---------|---------|
| `CRITICAL_*` | Few | Must-read rules every session must load | `CRITICAL_activation_rule` |
| `session_YYYY-MM-DD_*` | Many | Session checkpoints with progress and next steps | `session_2026-02-09_auth-flow` |
| `plan_*` | Few | Active implementation plans | `plan_dark-mode-implementation` |
| `pattern_*` | Many | Reusable patterns and solutions | `pattern_supabase-rls-setup` |
| `discovery_*` | Many | Brainstorming and research results | `discovery_api-design-options` |
| `todo_*` | Many | Persistent TODOs across sessions | `todo_fix-login-redirect` |

## Session Checkpoint Template

```
## Session: YYYY-MM-DD — <summary>

Agent: <Claude Code | Cursor | Codex> (<model>, if known)

### Accomplished
- [completed work items]

### Decisions Made
- [product decision]: [rationale]
- (<Agent>) [tooling decision]: [rationale]

### Files Changed
- [file path]: [what changed]

### Pending / Next Steps
- [remaining work]

### Blockers (if any)
- [blocker description]
```

## Load Priority Order

The `load` skill reads memories in this order:

1. `CRITICAL_*` (never skip)
2. Cross-referenced memories (from directives found in loaded memories)
3. Latest `session_*` (most recent by date in key name)
4. Active `plan_*` (if relevant to current work)
5. `pattern_*`, `discovery_*`, `todo_*` — on demand only

## Rules

- **Date-stamped keys** (`session_*`): Create new entry per session, never overwrite old ones
- **Agent tag** (`session_*`): `Agent:` line under the title; tooling decisions carry `(<Agent>)`, product decisions stay unprefixed (defined in `SKILL.md` Phase 3)
- **Pattern keys** (`pattern_*`): Update if the pattern evolves, keep topic-specific
- **TODO keys** (`todo_*`): Delete when completed, or note completion in the body
