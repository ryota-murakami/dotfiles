## Installation

1. パスワード無しでsudoを実行可能にする(install.sh内でsudoを使用するので)  

```sh
$ sudo visudo
Password:

# User privilege specification
root    ALL=(ALL) ALL
%admin  ALL=(ALL) ALL
myuser ALL=(ALL) NOPASSWD: ALL

:wq
```

> 参考:<a href="http://blog.bungu-do.jp/archives/2417" target="_blank">Macのsudoコマンドをパスワードなしで実行する</a>

2. `install.sh`で初期処理を行う。中をちょっと見れば何やってるか分かるヽ(´ー`)ﾉ

```sh
$ cd ~
$ git clone git@github.com:ryota-murakami/dotfiles.git
$ cd dotfiles
$ ./install.sh
```

**`install.sh`でやっていること**

- ホームディレクトリ`~`に`~/dotfiles/`内の`.`から始まるファイルのシンボリックリンクを作成
- `Brewfile`に書いてあるパッケージを全てインストール
- fish shellの初期化(ターミナルを再起動するとbashからfish shellに切り替わる)
- **今出来てない（´＿｀）** rbenvでrubyのインストール/設定
- **今出来てない（´＿｀）** phpbrewでphpのインストール
  - ちなみにnode.jsはbrewでその時の最新版を直接インストールしている
- gemでbundlerをインストール
- グローバルで使用するgemをインストール
  - グローバルで使用するgemを<a href="https://github.com/ryota-murakami/dotfiles/blob/master/Gemfile" target="_blank">dotfiles/Gemfile</a>で管理しており、`bundle install`で導入している
- git submoduleの初期化
  - 現状は<a href="https://github.com/ryota-murakami/dotfiles/tree/master/.vim/bundle" target="_blank">neobundle.vim</a>をsubmoduleで管理している
- グローバルで使用するphp packageをcomposerでインストール
  - グローバルで使用するphp packageを<a href="https://github.com/ryota-murakami/dotfiles/blob/master/.composer/composer.json" target="_blank">dotfiles/.composer/composer.json</a>で管理しており、`composer global install`で導入している

## Brewfile

<a href="https://github.com/ryota-murakami/dotfiles/blob/master/Brewfile" target="_new">dotfiles/Brewfile</a>

homebrewで導入したパッケージを記録するファイル。
Gemfile,package.jsonのようなもの。

```sh
# Brewfileにあるパッケージをインストール
$ brew brewdle
```

## fish shell

常用のshellはfish。
<a href="http://megane-blog.com/2014/12/15/1461" target="_blank">fishシェルがとても素晴らしかったので、お伝えします。</a>

インストールはbrewで、以下のスクリプトでデフォルトのshellに設定される。

- <a href="https://github.com/ryota-murakami/dotfiles/blob/master/scripts/fish_init.sh" target="_blank">dotfiles/scrips/fish_init.sh</a>

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

## .editorconfig

<a href="https://github.com/ryota-murakami/dotfiles/blob/master/.editorconfig" target="_new">dotfiles/.editorconfig</a>

エディタのインデントスタイルや改行コードを統一するツールの設定ファイル。
<a href="http://editorconfig.org/" target="_new">editorconfig</a>

`.bash_profile`に定義している`geneditconf()`をプロジェクトルートで叩くと、
このリポジトリで管理している`.editorconfig`がプロジェクトルートにコピーされる
