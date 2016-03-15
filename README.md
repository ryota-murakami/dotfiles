## Installation

```sh
$ cd ~
$ git clone git@github.com:ryota-murakami/dotfiles.git
$ cd dotfiles
$ ./install.sh
```

ホームディレクトリに`dotfiles`内の`.`から始まるファイルのシンボリックリンクが作成される

## Brewfile

<a href="https://github.com/ryota-murakami/dotfiles/blob/master/Brewfile" target="_new">dotfiles/Brewfile</a>

homebrewで導入したパッケージを記録するファイル。  
Gemfile,package.jsonのようなもの。

```sh
# Brewfileにあるパッケージをインストール
$ sudo brew brewdle
```

## fish shell

常用のshellはfish。  
<a href="http://megane-blog.com/2014/12/15/1461" target="_blank">fishシェルがとても素晴らしかったので、お伝えします。</a>  

インストールはbrewで、以下のスクリプトでデフォルトのshellに設定される。  

- <a href="https://github.com/ryota-murakami/dotfiles/blob/master/scrips/fish_init.sh" target="_blank">dotfiles/scrips/fish_init.sh</a>

## .vimrc
vimの設定と使っているパッケージが記載されている。  
Vimプラグインのパッケージマネージャである**NeoBundle**を使用しており、  
以下の手順でNeoBundleの導入とパッケージのインストールを行う。

#### NeoBundleのインストール

```sh
$ mkdir -p ~/dotfiles/.vim/bundle
$ git clone git://github.com/Shougo/neobundle.vim ~/dotfiles/.vim/bundle/neobundle.vim
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
