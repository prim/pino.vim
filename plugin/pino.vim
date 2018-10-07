
if exists('g:pino_loaded')
    finish
endif
let g:pino_loaded = 1

command! -nargs=0 PinoInitProject :call pino#init_project()
command! -nargs=1 PinoGoto :call pino#goto('<args>')
command! -nargs=1 PinoGrep :call pino#search('<args>')
command! -nargs=1 PinoCode :call pino#search_code('<args>')
command! -nargs=1 PinoFile :call pino#find_file('<args>')

nnoremap <leader>gg :execute 'PinoGoto '.expand('<cword>')<cr>
nnoremap <leader>gc :execute 'PinoCode '.expand('<cword>')<cr>

let s:opt = {}
let s:ctx = {}

call asyncomplete#register_source({
    \ 'name':'pino',
    \ 'whitelist': ['*'],
    \ 'completor': function('pino#completor'),
    \ 'refresh_pattern': '\(\k\+$\|\.$\|>$\|:$\)',
    \ })
