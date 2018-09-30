On Clean Mac OS X
=====================

My Mac OS X setup manual.

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->


- [1. Executable `sudo` without password.(using `sudo` into setup.sh)](#1-executable-sudo-without-passwordusing-sudo-into-setupsh)
- [2 privilege](#2-privilege)
- [3. Install Homebrew](#3-install-homebrew)
- [4. clone dotfiles](#4-clone-dotfiles)
- [5. Kick `setup.sh`(Homebrew required)](#5-kick-setupshhomebrew-required)
- [6. Setup rbenv](#6-setup-rbenv)
- [7. Install Vim plugins](#7-install-vim-plugins)
- [8. Install Nodebrew](#8-install-nodebrew)
- [Extra. Any Manual Tasks](#extra-any-manual-tasks)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## 1. Executable `sudo` without password.(using `sudo` into setup.sh)  

```sh
$ sudo visudo
Password:

# User privilege specification
root    ALL=(ALL) ALL
%admin  ALL=(ALL) ALL
ryota.murakami ALL=(ALL) NOPASSWD: ALL

:wq
```

> see:<a href="http://blog.bungu-do.jp/archives/2417" target="_blank">http://blog.bungu-do.jp/archives/2417</a>

## 2 privilege

```sh
sudo chown -R ryota.murakami /usr/local
```

## 3. Install Homebrew

```sh
ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
# brew tap Homebrew/brewdler
# brew bundle(start install packages witch is written in Brewfile)
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

## 6. Setup rbenv
Setup rbenv along to README manual.
https://github.com/rbenv/rbenv#homebrew-on-macos

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


## Extra. Any Manual Tasks

- change `¥` to `\` at OS X system config
- install karabiner-elements
- system config > hidden dock
- system config > - to dark OS menu-bar & dock
- terminal.app -> Preference -> Profiles -> Keybord -> ✔︎ Use Option as Meta Key
