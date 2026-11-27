# Desktop Walkthrough

A skill that lets an agent show its work on the user's Mac: it acts in real apps, says what it is doing and explains why, on a HUD that floats over whatever app is in front.

## Language

### Runs

**Session**:
The Claude Code run a walkthrough belongs to. It lives in a terminal; the HUD is its face on the desktop.
_Avoid_: the process, the engine, the real one

**Walkthrough**:
One guided tour of a piece of work, performed by a Session's agent for one user, from its start to a pause or its end.
_Avoid_: demo, tour

**Record**:
What a Walkthrough leaves behind so that it can be resumed or repeated: its pages, its journal and its handbook.

**Handout**:
One file made from a Record's pages, in the Explainer's order and look but without the HUD's controls, for people who did not watch the Walkthrough.
_Avoid_: exported explainer, shared explainer (the Explainer is the panel on screen)

### Surfaces

**HUD**:
Everything the skill shows on screen over the user's apps.

**Status bar**:
The line that says what the agent is doing right now, with the buttons of the other surfaces.
_Avoid_: toolbar

**Explainer**:
The panel of numbered pages that carry the reasoning.

**Note**:
A short explanation shown beside the thing it explains.
_Avoid_: popup, tooltip

**Prompt card**:
The card that asks the user a question and offers its answers.
_Avoid_: dialog, prompt (alone: that word is the user's message, below)

**Mirror**:
The surface that redraws the Session's conversation the way Claude Code's terminal draws it, and takes the user's Prompts.
_Avoid_: copy, clone, chat window

**Key display**:
The keys the agent sends, drawn large in a corner of the screen for a few seconds.
_Avoid_: keycast (that is the command and the file), key logger (it never reads the user's keyboard)

### Inside the Mirror

**Transcript**:
The Session's conversation as an ordered list of Rows.

**Row**:
One unit of the Transcript as the terminal draws it: a Prompt, a block of the agent's reply, a tool call with its result, a notice.
_Avoid_: entry, message, line

**Spinner line**:
The line that shows, while a turn runs, that the agent works, for how long and how much it has written.
_Avoid_: working line, status line (that is the user's own line under the Input box)

**Input box**:
The place in the Mirror where the user writes a Prompt.
_Avoid_: message box, text box, prompt box

**Prompt**:
What the user sends to the Session to start or steer a turn.
_Avoid_: message (every Row is a message of some kind)

### Machinery

**Bridge**:
The part that connects a Session to the HUD: it tells the HUD what the Session shows and hands the user's input to the Session.
_Avoid_: mod, hooks (those are how it is built)

**Checked release**:
The Claude Code release whose terminal the Mirror's drawing was last compared with.
