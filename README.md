# at Clean Mac OS X

1. パスワード無しでsudoを実行可能にする(setup.sh内でsudoを使用するので)  

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

2. kick `setup.sh`

```sh
$ cd ~
$ git clone git@github.com:ryota-murakami/dotfiles.git
$ cd dotfiles
$ ./setup.sh
```

3. <a href="https://gist.github.com/ryota-murakami/3f20f65462be18bf757a" target="_blank">Manually Tasks</a>

# Infomation

**`setup.sh`でやっていること**

- ホームディレクトリ`~`に`~/dotfiles/`内の`.`から始まるファイルのシンボリックリンクを作成
- `Brewfile`に書いてあるパッケージを全てインストール
- fish shellの初期化(ターミナルを再起動するとbashからfish shellに切り替わる)
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

ATOMはBrewfileからインストールされるがPackageを手動で入れる必要がある。  
お気に入りのPackageは<a href="https://atom.io/" target="_blank">https://atom.io/</a>からATOMアカウントに紐付けてスターを付けて管理する事が出来る。  

- スターを付けたPackageをローカルにインストール

```
$ apm stars --install
```
> アカウントにログインするため、APIトークンの認証が発生する。メッセージに沿って対応すればOK。
