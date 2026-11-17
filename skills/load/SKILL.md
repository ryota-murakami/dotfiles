---
name: load
description: Load session from memory
argument-hint: "[project]"
---

# Session Load

## Codex Compatibility
When running this skill in Codex, translate Claude Code-only primitives before acting: `AskUserQuestion` -> chat/request_user_input, `TodoWrite` -> `update_plan`, `Task`/`TaskCreate`/`TeamCreate`/`SendMessage` -> `spawn_agent`/`send_input`/`wait_agent` when available and allowed, and `EnterPlanMode`/`ExitPlanMode` -> a concise chat plan plus explicit approval.
Resolve `Read`/`Write`/`Edit`/`Bash`/`WebSearch`/`WebFetch` to Codex file/shell/web tools, and map `~/.claude/...` paths to `~/.agents/...` or `~/.codex/...` unless the task explicitly targets Claude Code.

## Cursor Compatibility
When running this skill in Cursor Agent, translate Claude Code-only primitives before acting: `AskUserQuestion` -> `AskQuestion`; `TodoWrite` -> Cursor `TodoWrite` or an equivalent checklist; `Task`/`TaskCreate`/`TeamCreate`/`SendMessage`/multi-agent flows -> Cursor `Task` (subagents), parallel Tasks, or `run_in_background` when allowed (`TeamCreate`/`SendMessage` may have no exact match); `EnterPlanMode`/`ExitPlanMode` -> Plan mode (`SwitchMode` / `CreatePlan`) plus explicit user approval.
Resolve `Read`/`Write`/`Edit`/`StrReplace`/`Bash`/web/search/MCP via Cursor Composer or Agent equivalents. MCP names written as `mcp__server__tool` typically map to `call_mcp_tool` with configured server identifiers. Map `~/.claude/...` to `~/.cursor/skills/`, `.cursor/skills/`, and `.cursor/rules/` unless the task explicitly targets Claude Code.


Load project context from Serena MCP memory.

<essential_principles>

- All context loading uses Serena MCP tools exclusively (no agent-specific tools)
- Follow cross-references found in loaded memories ("MUST read", "also read")

</essential_principles>

## Step 1: Discover Memories

1. Call `list_memories` to discover all memory keys

## Step 2: Read Memories

**If memories exist:**

4. Read all `CRITICAL_*` memories
5. Follow cross-references: if any loaded memory says "MUST read", "also read", or "see also" — read those keys
6. Read the most recent `session_*` memory (by date in key name)
7. Compare its `Agent:` line with the agent running now. A decision prefixed with another agent (e.g. `(Cursor) …` read from Claude Code) is that agent's tooling decision: keep it as history and take tooling from the current agent's own project rules (`CLAUDE.md`, `.cursor/rules/`, `AGENTS.md`). A session without an `Agent:` line predates the tag: its tooling decisions may come from another agent, so verify them against those rules before following

**If no memories exist:**

4. Note this is a first session — suggest running `/save` at end of session

## Step 3: Report

Present to the user:

```
## Session Loaded

- **Project**: [name]
- **Memories Loaded**: [count] ([list of keys])
- **Key Context**: [1-2 sentence summary of project state]
- **Previous Session**: [summary from session_* memory, or "None"]
- **Previous Session Agent**: [from its `Agent:` line, or "untagged"] — [if it differs from the current agent: which tooling decisions were left as history]
- **Status**: Ready
```
