On Clean Mac OS X
=====================

My Mac OS X setup manual.

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->


- [1. Touch ID for sudo authentication (modern approach)](#1-touch-id-for-sudo-authentication-modern-approach)
- [2. Homebrew permissions (modern approach)](#2-homebrew-permissions-modern-approach)
- [3. Install Homebrew](#3-install-homebrew)
- [4. clone dotfiles](#4-clone-dotfiles)
- [5. Kick `setup.sh`(Homebrew required)](#5-kick-setupshhomebrew-required)
- [6. Install Vim plugins](#7-install-vim-plugins)
- [7. Install Nodebrew](#8-install-nodebrew)
- [Personal agent skills](#personal-agent-skills)
- [Extra. Any Manual Tasks](#extra-any-manual-tasks)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## 1. Touch ID for sudo authentication (modern approach)

Enable Touch ID for sudo commands instead of password-less sudo (more secure approach).

For **macOS Sonoma 14.x and above** (recommended):
```sh
sudo nano /etc/pam.d/sudo_local
# Add this line:
auth sufficient pam_tid.so
```

For **older macOS versions**:
```sh
sudo nano /etc/pam.d/sudo
# Add 'auth sufficient pam_tid.so' as the second line
```

> See: <a href="https://9to5mac.com/2025/03/07/security-bite-stop-typing-your-sudo-password-use-touch-id-instead/" target="_blank">Touch ID for sudo on macOS (2025 Guide)</a>

## 2. Homebrew permissions (modern approach)

Modern Homebrew handles permissions automatically during installation. 

For **Apple Silicon Macs** (M1/M2/M3): Homebrew installs to `/opt/homebrew`  
For **Intel Macs**: Homebrew installs to `/usr/local`

**No manual ownership changes are required** - Homebrew installer sets up proper permissions automatically.

If you encounter permission issues, use:
```sh
brew doctor
# Follow the specific suggestions provided
```

> See: <a href="https://docs.brew.sh/Installation" target="_blank">Official Homebrew Installation Guide</a> | <a href="https://www.nyx.net/~mlu/pages/computing/installing_and_configuring/fixing_ownership_and_permission_of_usr_local_content_for_Homebrew/" target="_blank">Homebrew Permissions Troubleshooting</a>

## 3. Install Homebrew

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

## 4. clone dotfiles

```sh
cd ~
git@github.com:ryota-murakami/dotfiles.git
```

## 5. Kick `setup.sh`([Homebrew](https://github.com/ryota-murakami/dotfiles/blob/master/README.md#3-install-homebrew) required)

```sh
cd dotfiles
./setup.sh
```

**what's doing in `setup.sh`**

- generate dotfile symboliclinks at home directory.
- install all homebrew packages in Brewfile.
- setting fish-shell as a login shell.
  - re-open terminal to activation.
- initialize git submodule.
  - in order to <a href="https://github.com/ryota-murakami/dotfiles/tree/master/.vim/bundle" target="_blank">neobundle.vim</a>.

## 7. Install Vim plugins

open `.vimrc`, execute folllowing.

```sh
:NeoBundleInstall
```

defined installed pulugins at `.vimrc`.
git
```vim
call neobundle#begin(expand('~/.vim/bundle'))
    NeoBundle 'editorconfig/editorconfig-vim'
    ~
call neobundle#end()
```

## 8. Install Nodebrew
nodebrew is not provided by homebrew, therefore you have to setup along to the README. 
https://github.com/hokaccha/nodebrew


## Personal agent skills

List the skills in this checkout:

```sh
npx skills add ~/dotfiles/skills --list
```

Install a skill globally by name. For example, install both the PR workflow and its review dependency:

```sh
npx skills add ~/dotfiles/skills --skill apollousa coderabbit-resolver -g -y
```

To install all personal skills, run:

```sh
npx skills add ~/dotfiles/skills --skill '*' -g -y
```

After editing or pulling changes, repeat the local install command to refresh the installed copies.
To track the GitHub repository instead, install from it once and use the CLI to update:

```sh
npx skills add ryota-murakami/dotfiles --skill apollousa coderabbit-resolver -g -y
npx skills update apollousa coderabbit-resolver -g -y
```

Available skills:

- [agent-home-cleanup](skills/agent-home-cleanup/SKILL.md)
- [apollousa](skills/apollousa/SKILL.md)
- [ci-hardening](skills/ci-hardening/SKILL.md)
- [claude-skill-name-only](skills/claude-skill-name-only/SKILL.md)
- [coderabbit-resolver](skills/coderabbit-resolver/SKILL.md)
- [desktop-walkthrough](skills/desktop-walkthrough/SKILL.md) (also a Claude Code plugin: run `/reload-plugins` after installing)
- [electron-release](skills/electron-release/SKILL.md)
- [github-actions-pnpm-ci](skills/github-actions-pnpm-ci/SKILL.md)
- [laststance-publish-skill](skills/laststance-publish-skill/SKILL.md)
- [load](skills/load/SKILL.md)
- [oss-repo-setup](skills/oss-repo-setup/SKILL.md)
- [save](skills/save/SKILL.md)
- [save-my-skill](skills/save-my-skill/SKILL.md)

## Extra. Any Manual Tasks

- install karabiner-elements
- system prefefences > hidden dock
- System Preferences > Keybord > App Shortcut > Others > type action "Log Out ryota..." > set `cmd + option + q` as shortcut
  - OSX default shortcut `cmd + option + q` of "Log Out ryota..." is conflict my custom editor's "close project" shortcut 
  - See: https://apple.stackexchange.com/questions/210517/disable-shift-cmd-q-for-logout
- Set `Unicode Hex Input` as a input soruce to remove all option key combination
- Remove `cmd + shift + r` shortcut from Be Focus Pro
