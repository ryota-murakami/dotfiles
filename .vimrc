if has('vim_starting')
    set runtimepath+=~/.vim/bundle/neobundle.vim
    call neobundle#begin(expand('~/.vim/bundle'))
        NeoBundle 'editorconfig/editorconfig-vim'
        NeoBundle 'dag/vim-fish'
        NeoBundle 'vim-scripts/grep.vim'
    call neobundle#end()
endif

colorscheme molokai
syntax on
set t_Co=256
set backspace=2
set hlsearch
set number
