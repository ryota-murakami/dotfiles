---
name: save-my-skill
description: |
  Save a personal agent skill into ~/dotfiles/skills (overwriting the dotfiles copy with the edited one), commit it with the dotfiles commit message rules, ending in :green_apple:, and push it.
  Use when: the user asks to back up, save, sync, commit or push one of their own skills to dotfiles, or after editing a personal skill they want kept.
  Keywords: save my skill, save skill to dotfiles, back up skill, commit skill, push skill, スキルをdotfilesに保存, スキルをバックアップ, スキルをコミット, スキルをpush, 個人スキルを更新.
argument-hint: "[skill name ... | status]"
---

# Save My Skill

Personal skills live in `~/dotfiles/skills/<name>/` (source of truth, a public GitHub repo) and are installed with `npx skills add ~/dotfiles/skills --skill <name> -g -y`, which copies them to `~/.agents/skills/<name>` and links `~/.claude/skills/<name>`. A skill under active development may instead be a link: `~/.agents/skills/<name>` pointing at the dotfiles folder, so edits are live. Edits happen in either place; this skill brings them back into dotfiles, commits and pushes.

`SAVE=~/.claude/skills/save-my-skill/scripts/save.sh`

## Steps

1. **Pick the skills.** Use the names given. With no name or `status`, run `$SAVE status` and save the skills it lists that the user (or this session) edited; ask if it is unclear which ones.
2. **Save each one**: `$SAVE <name> [SOURCE_DIR]` (pass `SOURCE_DIR` when the edited copy is somewhere other than the agent homes). Act on its last line:
   - `SAVED`: the installed copy overwrote the dotfiles copy.
   - `DOTFILES`: the edit was made in dotfiles; commit it, then refresh the install (step 6).
   - `LINKED`: the install is a link to the dotfiles folder; commit it, with no copy and no refresh.
   - `UNCHANGED`: both copies match; commit only if git still shows changes for the skill.
   - `CONFLICT` (exit 3): both copies changed differently since the last commit. Nothing was copied. Show the diff and ask which side to keep; never merge by guessing.
   - `CHECK FAILED` (exit 4): the skill's own `scripts/check` failed (its output is above). Fix the skill and save again; commit only after a passing run.
3. **Review before committing.** Read `git -C ~/dotfiles diff -- skills/<name>` (and `git status` for new files). Stop and ask if `save.sh` printed a possible secret or address, or if the diff holds credentials, personal data or generated artifacts (built binaries, logs, caches). The repo is public and the commit is pushed without another prompt, so this review is the last gate.
4. **New skill**: add `- [<name>](skills/<name>/SKILL.md)` to the "Available skills" list in `~/dotfiles/README.md`, in alphabetical order.
5. **Commit only what belongs to the skill.** `git add -- skills/<name>` (plus `README.md` only when every change in it is this skill's list line; otherwise ask). Never stage the user's other changes. One commit per skill, with the message rules below.
6. **Refresh the install** when the dotfiles copy is newer than the installed one (`DOTFILES`, or a conflict resolved toward dotfiles), or when the skill is new: `DISABLE_TELEMETRY=1 DO_NOT_TRACK=1 npx --yes skills add ~/dotfiles/skills --skill <name> -g -y`. Skip it for `LINKED`: that command would replace the link with a copy. If the skill folder has `.claude-plugin/`, tell the user to run `/reload-plugins`.
7. **Push**, once, after the last skill's commit passed the message check below.
   - List what the push will publish: `git -C ~/dotfiles log @{u}..HEAD --format='%h %s'`. When every line is a `[skills] … :green_apple:` commit, run `git -C ~/dotfiles push`. When the list holds any other commit, name it and ask first: it is the user's own unpublished work.
   - Confirm with `git -C ~/dotfiles status -sb`: the branch line must no longer say `ahead`.
   - A rejected push is never forced. Report what the remote has that the local branch lacks (`git -C ~/dotfiles fetch`, then `git -C ~/dotfiles log HEAD..@{u} --oneline`) and ask.
   - A push refused for the account (403) means the active `gh` account is not the owner of the remote: push with the owner's token, `GH_TOKEN="$(gh auth token --user <owner in the remote URL>)" git -C ~/dotfiles push`.
   - Report each commit's hash and subject, and that it was pushed.

## Commit message rules (strict)

```
[skills] <summary> :green_apple:

- <what changed and why, one bullet per change>
```

- Subject: `[skills]`, a space, an English lowercase imperative summary (`add`, `update`, `fix`, `remove` …) naming the skill, a space, and `:green_apple:` as the very last characters. No other emoji code, no trailing period, at most about 72 characters before `:green_apple:`.
- Body: a blank line, then `- ` bullets in English describing the actual changes. No `Co-Authored-By` or other trailers.
- Pass the message with `git commit -F <file>` or several `-m` arguments so the emoji code is not altered by the shell.
- After committing, check: `git -C ~/dotfiles log -1 --format=%s | grep -q ' :green_apple:$'`. If it fails, fix it with `git commit --amend` before anything else.

Example: `[skills] update desktop-walkthrough to relaunch the hud after an agent restart :green_apple:`
