set fenc=utf-8
scriptencoding utf-8
set nobackup
set noswapfile
set autoread
set hidden
set showcmd

" Visualization
set relativenumber
set number
set cursorline
set virtualedit=onemore
set smartindent
set visualbell
set showmatch
set laststatus=2
set wildmode=list:longest
set nowrap
nnoremap j gj
nnoremap k gk
syntax enable
set lines=55
set columns=180
colorscheme codedark
set background=dark

" Tab
set list listchars=tab:\▸\-
set expandtab
set tabstop=2
set shiftwidth=2
syntax on

" Clipboard
set clipboard+=unnamed
if &term =~ "xterm"
  let &t_SI .= "\e[?2004h"
  let &t_EI .= "\e[?2004l"
  let &pastetoggle = "\e[201~"

  function XTermPasteBegin(ret)
    set paste
    return a:ret
  endfunction

  inoremap <special> <expr> <Esc>[200~ XTermPasteBegin("")
endif

" Search
set hlsearch
set ignorecase
set smartcase
set incsearch
set wrapscan
nmap <Esc><Esc> :nohlsearch<CR><Esc>

" Auto reload vimrc
autocmd! bufwritepost $MYVIMRC source %
autocmd! bufwritepost $MYGVIMRC source %

