
if exists('g:pino_loaded')
    finish
endif
let g:pino_loaded = 1

command! -nargs=0 PinoInitOrLoad :call pino#project_init()
command! -nargs=0 PinoReinit :call pino#project_reinit()
command! -nargs=0 PinoSave :call pino#project_save()
command! -nargs=0 PinoList :call pino#list()

command! -nargs=1 PinoCd :call pino#cd('<args>')
command! -nargs=1 PinoGoto :call pino#goto('<args>')
command! -nargs=1 PinoGrep :call pino#search('<args>')
command! -nargs=1 PinoCode :call pino#search_code('<args>')
command! -nargs=1 PinoFile :call pino#find_file('<args>')

nnoremap <leader>gd :execute 'PinoGoto '.expand('<cword>')<cr>
nnoremap <leader>gg :execute 'PinoGrep '.expand('<cword>')<cr>
nnoremap <leader>gc :execute 'PinoCode '.expand('<cword>')<cr>

