# The Mirror redraws the conversation; it does not relay the terminal

The Mirror has to look like Claude Code's terminal. A terminal multiplexer can hand over the terminal's real screen and accept keys for it (herdr's `terminal session observe` and `pane send-text` were measured: frames with the cursor position, a key echoed in about 13 ms), which would be exact and would never drift. We decided against it on 2026-11-22: a skill must work wherever its Session's terminal runs, and that route works only inside one multiplexer. Instead the Bridge reports each Row as Claude Code hands it to its own terminal UI, and the Mirror draws it in its own code, by the rules of the Checked release.

## Considered options

- **Relay the terminal through a multiplexer** (herdr, tmux): exact and maintenance-free, but the skill would depend on where the terminal runs.
- **Start the Session through a wrapper of our own that copies the terminal's bytes**: no third-party dependency, but a skill is invoked inside a Session that is already running.
- **Redraw from what the Bridge reports** (chosen): works in any terminal and wraps to the Mirror's own width.

## Consequences

- The look can drift with every Claude Code release. `docs/claude-code-tui/` records the rules and the release they were read from; a new release is checked against them before the Mirror is trusted again.
- Claude Code's code is read to learn the rules and never copied: the repository holds our own drawing code and our own description of the rules.
- What the terminal draws without telling the Bridge (its own menus and dialogs) is not in the Mirror.
