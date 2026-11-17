---
name: save
description: Save session to memory
---

# Session Save

## Codex Compatibility
When running this skill in Codex, translate Claude Code-only primitives before acting: `AskUserQuestion` -> chat/request_user_input, `TodoWrite` -> `update_plan`, `Task`/`TaskCreate`/`TeamCreate`/`SendMessage` -> `spawn_agent`/`send_input`/`wait_agent` when available and allowed, and `EnterPlanMode`/`ExitPlanMode` -> a concise chat plan plus explicit approval.
Resolve `Read`/`Write`/`Edit`/`Bash`/`WebSearch`/`WebFetch` to Codex file/shell/web tools, and map `~/.claude/...` paths to `~/.agents/...` or `~/.codex/...` unless the task explicitly targets Claude Code.

## Cursor Compatibility
When running this skill in Cursor Agent, translate Claude Code-only primitives before acting: `AskUserQuestion` -> `AskQuestion`; `TodoWrite` -> Cursor `TodoWrite` or an equivalent checklist; `Task`/`TaskCreate`/`TeamCreate`/`SendMessage`/multi-agent flows -> Cursor `Task` (subagents), parallel Tasks, or `run_in_background` when allowed (`TeamCreate`/`SendMessage` may have no exact match); `EnterPlanMode`/`ExitPlanMode` -> Plan mode (`SwitchMode` / `CreatePlan`) plus explicit user approval.
Resolve `Read`/`Write`/`Edit`/`StrReplace`/`Bash`/web/search/MCP via Cursor Composer or Agent equivalents. MCP names written as `mcp__server__tool` typically map to `call_mcp_tool` with configured server identifiers. Map `~/.claude/...` to `~/.cursor/skills/`, `.cursor/skills/`, and `.cursor/rules/` unless the task explicitly targets Claude Code.


Persist session context to Serena MCP memory for cross-session continuity.

<essential_principles>

## Core Requirements

- All persistence uses Serena MCP tools exclusively (no agent-specific tools)
- Always check existing memories before writing to avoid overwriting valuable context
- Session checkpoint keys must include date: `session_YYYY-MM-DD_<description>`
- Pattern and learning memories use: `pattern_<topic>`
- Report what was saved as a structured summary to the user

</essential_principles>

## Phase 1: Session Analysis

1. Review what was accomplished this session:
   - Files created or modified
   - Decisions made and their rationale
   - Problems encountered and solutions found
   - Tasks completed and tasks remaining
2. Identify what is worth persisting:
   - **Session state**: Current progress, next steps, blockers
   - **Learnings**: Reusable patterns, solutions to problems
   - **Plans**: Active plans or updated plans
   - **TODOs**: Outstanding work items

## Phase 2: Memory Inventory

3. Call `list_memories` to see existing memories
4. Identify which existing memories need updates vs. new memories to create

## Phase 3: Persist Session Checkpoint

5. Call `write_memory` with key `session_YYYY-MM-DD_<summary>`:

```
## Session: YYYY-MM-DD — <summary>

Agent: <Claude Code | Cursor | Codex> (<model>, if known)

### Accomplished
- [what was done]

### Decisions Made
- [product decision]: [rationale]
- (<Agent>) [tooling decision]: [rationale]

### Files Changed
- [file path]: [what changed]

### Pending / Next Steps
- [what remains to be done]

### Blockers (if any)
- [blocker description]
```

`Agent:` names the agent running this skill; add the model only when the agent reports it. Serena memory belongs to the project, not the agent, so Claude Code, Cursor and Codex all read the same checkpoints. A **tooling decision** (which browser / MCP / IDE tool to use, a model-specific workaround) binds only the agent that made it: prefix it with `(<Agent>)`, e.g. `(Cursor) browser QA runs through Cursor's built-in browser`. A **product decision** (spec, design, API contract, naming) binds every agent: write it without a prefix.

## Phase 4: Persist Learnings (if any)

6. For each reusable pattern discovered, call `write_memory` with key `pattern_<topic>`:

```
## Pattern: <name>

**Context**: [when this applies]
**Solution**: [the pattern/approach]
**Example**: [concrete example]
**When to Use**: [trigger conditions]
```

7. For each persistent TODO, call `write_memory` with key `todo_<description>`:

```
## TODO: <description>

**Priority**: [high/medium/low]
**Context**: [why this matters]
**Acceptance Criteria**: [how to know it's done]
```

## Phase 5: Validation

8. Verify: session checkpoint created, learnings persisted, no critical context lost

## Phase 6: Save Report

Report to the user:

```
## Session Saved

### Memories Written
| Key | Purpose |
|-----|---------|
| session_YYYY-MM-DD_xxx | Session checkpoint |
| pattern_xxx | [if any] |
| todo_xxx | [if any] |

### Next Session
Run `/load` to restore this context.
```

## Memory Naming Conventions

See `references/memory-conventions.md` for the complete naming reference.

Quick summary:

| Prefix | Purpose | Example |
|--------|---------|---------|
| `CRITICAL_*` | Must-read rules | `CRITICAL_activation_rule` |
| `session_YYYY-MM-DD_*` | Session checkpoints | `session_2026-02-09_auth-flow` |
| `plan_*` | Active plans | `plan_dark-mode` |
| `pattern_*` | Reusable patterns | `pattern_supabase-rls` |
| `discovery_*` | Brainstorming results | `discovery_api-options` |
| `todo_*` | Persistent TODOs | `todo_fix-login` |

## Success Criteria

- [ ] Session accomplishments analyzed
- [ ] Existing memories checked (no accidental overwrites)
- [ ] Session checkpoint memory written with date-stamped key
- [ ] `Agent:` line written; every tooling decision carries its `(<Agent>)` prefix
- [ ] Learnings/patterns persisted (if any discovered)
- [ ] Save report presented to user
