# Records: resuming and repeating a walkthrough

Every walkthrough is recorded in a folder of its own under `~/.config/desktop-walkthrough/walkthroughs/` (this skill's folder; it is not committed anywhere).

| Command | What it does |
| --- | --- |
| `$DW start --name <name>` | starts a walkthrough and names its record (without a name: the start time) |
| `$DW record <name>` | names or renames the record later and takes the pages already shown; a page it cannot save now (another dw is writing the record) is named and `dw record` fails: run it again, the pages saved are skipped. It also fails, and says which, for a page the panel has no source for any more and for an index entry without a page number |
| `$DW records` | lists the records |
| `$DW resume <name>` | takes a paused walkthrough up again, in the same record |
| `$DW handout [<name>]` | writes the record's pages as one HTML file to share, `handout.html` (SKILL.md, Handout). Without a name: the running walkthrough's record, else the last one started, resumed or named (`dw end` keeps that), else the one whose journal changed last |

## What a record holds

| In the record | Written by | For |
| --- | --- | --- |
| `journal.md` | `dw`, as you work: sections (`step`), narration (`say`), commands and their results (`term run` / `term check`), questions with their answers, feedback buttons | repeating the walkthrough step by step |
| `pages/NN-title.md`, `handbook.md` | `dw explain`: each page as written (both audiences' blocks), and all of them in reading order. A title longer than 200 bytes is cut in the file name only; the page keeps its whole title. `handbook.md` is rewritten in place, so its owner, permissions and ACL stay as you set them; one dw cannot write keeps what it held, and dw says it was not rebuilt | reading again; `handbook.md` is the raw text, not the file to share |
| `pages/sections.tsv` | `dw explain`: per page its number, its section and the title given with `--title` (tab-separated). dw replaces it by a rename and keeps its permission bits; one that is a link, a pipe or a folder is not dw's: a save and an export stop and say so, and a resume brings the pages back without their sections | listing the pages the same way on resume and in a Handout |
| `pages/.dw-lock` | `dw explain` while it changes the record's pages, and `dw handout` while it copies them: the system's advisory lock on it, held by that dw | two writers at once never delete each other's page, and an export reads the pages as one moment held them; the lock ends with its holder, however dw ends. A page shown while another dw holds it is not recorded: dw says so and gives the command that records that page (`dw explain <its Markdown> --page N`) |
| `pages/cleared-<time>/` | `dw explain --clear`: the pages shown before the clear, with their sections (a second clear within the same second gets `cleared-<time>-1/`). Every page and sections.tsv is copied and compared before anything leaves the record: a clear that cannot archive them removes nothing, in the panel either. One that cannot empty `sections.tsv` afterwards says where the pages are and leaves the panel as it was; clearing again clears the panel. dw never deletes these folders, nor the panel's own copies of the cleared pages (`explain/cleared/` in dw's state folder): `dw doctor` says how many there are | keeping them; resume, the handbook and a Handout hold only the pages shown since |
| `handout.html` | `dw handout`: every page as one checked, self-contained file | sharing with people who did not watch |
| `notes/NNN-title.md` | `dw note`: each note, in the order shown | showing the same notes beside the same code in a repeat |
| `progress.json` | the HUD, as the reader marks blocks | what was marked as read on each page, the notes understood, the achievements. `dw resume` gives it back to the HUD, so the marks are there again; `dw explain --progress` prints it |
| `README.md` | you | starting a repeat or a resume without the old conversation |
| `tools/`, input files | you | the helper scripts and inputs a repeat needs. Nothing secret: tokens and env files stay out |

## The README you write

`dw start` creates it with a header (what the folder holds, how to repeat) that ends in a marker comment: append below the marker, never replace the file. Write it while the reasons are fresh, before finishing or pausing:

- the starting state (branch, data, running services) and how to get there
- the chapters in order, with what each one proves
- what the walkthrough changes and how to put it back
- when paused: the resume point (the last step done, the next page, drafts not shown yet), and the user's preferences learned in this run

## Resume a paused walkthrough

1. `$DW resume <name>` instead of `$DW start`. It starts the HUD, keeps recording into the same record and puts its pages back in the explainer under their numbers, so the next page continues the count and the user can page back to the earlier day. The pages are not news: the panel comes back open or closed, as the user left it. A page whose audience markers broke keeps its number and shows a stand-in headed 「解説 N」 that says so: fix the record's page and show it again with `$DW explain <file> --page N`.
2. Read the record's `README.md` for the resume point.
3. Show one page first: where it stopped, today's order, what is being prepared.
4. Redo the preparation while the user reads it (a pause puts the environment back).
5. Check each page or note drafted earlier against the code before showing it.

## Repeat a recorded walkthrough

1. `$DW start --name <new name>`.
2. Read the old record's `README.md` and `journal.md`.
3. Compare each page with how things are now: code moves on, so correct a page before showing it.
4. Perform the journal's steps in order. The journal says what happened, including what failed: follow the path that worked.
