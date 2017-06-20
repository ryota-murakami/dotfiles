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
- initialize fish shell.(enable re-open terminal)
- initialize git submodule.
  - in order to <a href="https://github.com/ryota-murakami/dotfiles/tree/master/.vim/bundle" target="_blank">neobundle.vim</a>
- グローバルに使用するcomposer packageをインストール
  - グローバルに使用するcomposer packageを<a href="https://github.com/ryota-murakami/dotfiles/blob/master/.composer/composer.json" target="_blank">dotfiles/.composer/composer.json</a>で管理しており、`composer global install`でDownloadされる

## Brewfile

<a href="https://github.com/ryota-murakami/dotfiles/blob/master/Brewfile" target="_new">dotfiles/Brewfile</a>

homebrewで導入したパッケージを記録するファイル。
Gemfile,package.jsonのようなもの。

```sh
# Brewfileにあるパッケージをインストール
$ brew brewdle
```

## .vimrc
vimの設定と使っているパッケージが記載されている。
Vimプラグインのパッケージマネージャである**NeoBundle**を使用しており、
以下の手順でNeoBundleの導入とパッケージのインストールを行う。

#### NeoBundleのインストール

```sh
# インストール
git submodule init

# 更新
$ git submodule update
```

#### プラグインのインストール

`.vimrc`を開きコマンドモードの状態で以下を入力。

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

ブロックに記載されたパッケージがインストールされる。

## Atom

AtomはBrewfileからインストールされるがPackageを手動で入れる必要がある。  
お気に入りのPackageは<a href="https://atom.io/" target="_blank">https://atom.io/</a>からATOMアカウントに紐付けてスターを付けて管理する事が出来る。  

- スターを付けたPackageをローカルにインストール

```
$ apm stars --install
```
> アカウントにログインするため、APIトークンの認証が発生する。メッセージに沿って対応すればOK。
