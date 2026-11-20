# Records: resuming and repeating a walkthrough

Every walkthrough is recorded in a folder of its own under `~/.config/agentic-mac-os/walkthroughs/` (this skill's folder; it is not committed anywhere).

| Command | What it does |
| --- | --- |
| `$DW start --name <name>` | starts a walkthrough and names its record (without a name: the start time) |
| `$DW record <name>` | names or renames the record later and takes the pages already shown |
| `$DW records` | lists the records |
| `$DW resume <name>` | takes a paused walkthrough up again, in the same record |

## What a record holds

| In the record | Written by | For |
| --- | --- | --- |
| `journal.md` | `dw`, as you work: sections (`step`), narration (`say`), commands and their results (`term run` / `term check`), questions with their answers, feedback buttons | repeating the walkthrough step by step |
| `pages/NN-title.md`, `handbook.md` | `dw explain`: each page, and all of them in reading order | reading again, sharing with other people |
| `notes/NNN-title.md` | `dw note`: each note, in the order shown | showing the same notes beside the same code in a repeat |
| `progress.json` | the HUD, as the reader marks blocks | what was marked as read on each page, the notes understood, the achievements. `dw resume` gives it back to the HUD, so the marks are there again; `dw explain --progress` prints it |
| `README.md` | you | starting a repeat or a resume without the old conversation |
| `tools/`, input files | you | the helper scripts and inputs a repeat needs. Nothing secret: tokens and env files stay out |

## The README you write

Write it while the reasons are fresh, before finishing or pausing:

- the starting state (branch, data, running services) and how to get there
- the chapters in order, with what each one proves
- what the walkthrough changes and how to put it back
- when paused: the resume point (the last step done, the next page, drafts not shown yet), and the user's preferences learned in this run

## Resume a paused walkthrough

1. `$DW resume <name>` instead of `$DW start`. It starts the HUD, keeps recording into the same record and puts its pages back in the explainer under their numbers, so the next page continues the count and the user can page back to the earlier day. The pages are not news: the panel comes back open or closed, as the user left it.
2. Read the record's `README.md` for the resume point.
3. Show one page first: where it stopped, today's order, what is being prepared.
4. Redo the preparation while the user reads it (a pause puts the environment back).
5. Check each page or note drafted earlier against the code before showing it.

## Repeat a recorded walkthrough

1. `$DW start --name <new name>`.
2. Read the old record's `README.md` and `journal.md`.
3. Compare each page with how things are now: code moves on, so correct a page before showing it.
4. Perform the journal's steps in order. The journal says what happened, including what failed: follow the path that worked.
