At Clean Mac OS X
=====================

fllowing, my initial setting manual.

## 1. Executable `sudo` without password.(using `sudo` into setup.sh)  

```sh
$ sudo visudo
Password:

# User privilege specification
root    ALL=(ALL) ALL
%admin  ALL=(ALL) ALL
myuser ALL=(ALL) NOPASSWD: ALL

:wq
```

> see:<a href="http://blog.bungu-do.jp/archives/2417" target="_blank">http://blog.bungu-do.jp/archives/2417</a>

## 2 privilege

```sh
sudo chown -R root /usr/local
```

## 3. Install Homebrew

```sh
ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
```

## 4. clone dotfiles

```sh
cd ~
git clone https://github.com/ryota-murakami/dotfiles.git
```

## 5. Kick `setup.sh`

```sh
cd dotfiles
./setup.sh
```

**what's doing in `setup.sh`**

- generate dotfile symboliclinks at home directory.
- brew install all `Brewfile` defined packages.
- initialize fish shell.
  - enable re-open terminal.
- initialize git submodule.
  - in order to <a href="https://github.com/ryota-murakami/dotfiles/tree/master/.vim/bundle" target="_blank">neobundle.vim</a>.

## 6. Install composer blobal packages
  - composer blobal packages are managed at <a href="https://github.com/ryota-murakami/dotfiles/blob/master/.composer/composer.json" target="_blank">dotfiles/.composer/composer.json</a>, which will installed after `composer global install`.

## 7. Install Vim plugins

open `.vimrc`, execute folllowing.

```sh
:NeoBundleInstall
```

`.vimrc`の

```vim
call neobundle#begin(expand('~/.vim/bundle'))
    NeoBundle 'editorconfig/editorconfig-vim'
    ~
call neobundle#end()
```


