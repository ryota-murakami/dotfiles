On Clean Mac OS X
=====================

fllowing, my initial setting manual.

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

## 5. Kick `setup.sh`(Homebrew required)

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

- change `¥` to `\` at OS X system config.
- karabiner-elements.
- system config > hidden dock.
- system config > - to dark OS menu-bar & dock.
- defaults write -g ApplePressAndHoldEnabled -bool false
