" Pino.vim for the pino language server 

if exists('g:pino_vim_loaded')
    finish
endif
let g:pino_vim_loaded = 1

" Python {{{ 

python << PYTHON_END

import os
import vim
import time
import socket 
import json
import traceback
import threading
import requests
import Queue

init = False
exit = False
pino_socket = None
job_queue = Queue.Queue(maxsize = 128)
vim_queue = Queue.Queue(maxsize = 128)

session = requests.Session()

def log(fmt, *args):
    path = vim.eval("g:pino_log_file")
    with open(path, "a+") as wf:
        msg = "%s %s %s %s\n" % (os.getpid(), time.asctime(), fmt, args)
        wf.write(msg)

log("python importing")

def loop(job_queue):
    while not exit:
        try:
            log("pino thread recv begin", id(globals))
            args = job_queue.get(block = True)
            log("pino thread recv end", args)

            handler = args[0]
            if handler == "vim_leave_quit":
                log("pino thread recv vim_leave_quit")
                break
            args = args[1:]

            result = pino_send_request(*args)
            if result:
                vim_queue.put((handler, result, args))

        except Exception, err:
            log("pino thread loop error", traceback.format_exc())

    log("pino thread loop exit")

def pino_init():
    global init
    if init:
        log("pino init repeat")
        return 
    init = True
    log("pino init")
    global loop_thread
    loop_thread = threading.Thread(target = loop, args = (job_queue, )) 
    loop_thread.start()

def pino_leave_vim():
    log("pino_leave_vim begin")
    global exit
    exit = True
    job_queue.put(("vim_leave_quit", ))
    log("pino_leave_vim end")

def pino_request(*args):
    job_queue.put(args)

def pino_send_request(*args):
    action = args[0]
    args = args[1:]
    params = {
        "method": action,
        "params": {
            "cwf": vim.eval('expand("%:p")'),
            "cwd": vim.eval('getcwd()'),
            "args": args,
        }
    }
    ip = vim.eval("g:pino_server_ip")
    port = vim.eval("g:pino_server_port")
    url = "http://%s:%s" % (ip, port)
    resp = session.post(url, json=params)
    log("resp.content", resp.content)
    return json.loads(resp.content)["result"]

def pino_timer():
    while not exit:
        try:
            handler, result, args = vim_queue.get(block = False)
            log("pino_timer", handler, result, args)
            try:
                handler and handler(result, *args)
            except Exception, err:
                log(traceback.format_exc())
        except Queue.Empty:
            break

def pino_project_init():
    pino_request(None, "Init")

def pino_list():
    pino_request(list_, "List")

def list_(result, *args):
    for name in result:
        print name

def pino_cd(word):
    pino_request(cd, "Cd", word)

def cd(result, *args):
    log("cd result", result, args)
    if result["l"]:
        cmd = "cd %s" % result["l"][0]
        vim.command(cmd)

def pino_project_reinit():
    pino_request(None, "Reinit")

def pino_project_stat():
    pino_request(None, "Stat")

def pino_project_save():
    pino_request(None, "Save")

def quick_fix(result, _, __, type_):
    log("quick_fix begin", result, type_)
    if type_ == 0 and len(result) == 1:
        filename = result[0]["filename"]
        bufnr = vim.Function("bufnr")(filename)
        if bufnr != -1:
            cmd = "buffer %d" % bufnr
        else:
            cmd = "edit! %s" % filename
        try:
            log("quick_fix vim command %s", cmd)
            vim.command(cmd)
        except Exception:
            log(traceback.format_exc())
        lnum = result[0]["lnum"]
        # col = result[0]["text"].find(word)
        # vim.command("echom %s" % repr((locals())))
        vim.Function("cursor")(lnum, 1)
        return 
    vim.Function("setqflist")(result)
    vim.command('copen')

def pino_goto(word):
    pino_request(quick_fix, "SearchWord", word, 0)

def pino_search(word):
    pino_request(quick_fix, "SearchWord", word, 2)

def pino_search_code(word):
    pino_request(quick_fix, "SearchWord", word, 1)

def pino_find_file(word):
    pino_request(quick_fix, "SearchFile", word, 0)

def completion(result, *args):
    l = result
    if l:
        l = l.split("\n")
        items = ",".join([('"%s"' % s) for s in l])
        vim.command("call s:handle_completion([%s])" % items)

def pino_completion(word):
    pino_request(completion, "Completion", word, 10)

PYTHON_END
" }}}

" Vim Script {{{
execute 'python pino_init()'

function! pino#project_where()
    execute 'python pino_project_where()'
endfunction 

function! pino#leave_vim()
    execute 'python pino_leave_vim()'
endfunction 

function! pino#list()
    execute 'python pino_list()'
endfunction 

function! pino#project_init()
    execute 'python pino_project_init()'
endfunction 

function! pino#project_reinit()
    execute 'python pino_project_reinit()'
endfunction 

function! pino#project_save()
    execute 'python pino_project_save()'
endfunction 

function! pino#project_stat()
    execute 'python pino_project_stat()'
endfunction 

function! pino#goto(word)
    execute 'python pino_goto(r"""' . a:word . '""")'
endfunction 

function! pino#search(word)
    execute 'python pino_search(r"""' . a:word . '""")'
endfunction 

function! pino#cd(word)
    execute 'python pino_cd(r"""' . a:word . '""")'
endfunction 

function! pino#search_code(word)
    execute 'python pino_search_code(r"""' . a:word . '""")'
endfunction 

function! pino#find_file(word)
    execute 'python pino_find_file(r"""' . a:word . '""")'
endfunction 

function! pino#completor(opt, ctx) abort
    let s:opt = copy(a:opt)
    let s:ctx = copy(a:ctx)
    execute 'python pino_completion("""' . a:ctx['typed'] . '""")'
endfunction

function! s:handle_completion(items) abort
    let l:incomplete = 0

    let l:col = s:ctx['col']
    let l:typed = s:ctx['typed']
    let l:kw = matchstr(l:typed, '\w\+$')
    let l:kwlen = len(l:kw)
    let l:startcol = l:col - l:kwlen

    call asyncomplete#complete(s:opt['name'], s:ctx, l:startcol, a:items, l:incomplete)
endfunction

let s:timer_tick = 10

function! pino#timer(timer) abort
    call timer_start(s:timer_tick, "pino#timer")
    execute 'python pino_timer()'
endfunction

call timer_start(s:timer_tick, "pino#timer")

autocmd VimLeave * execute 'python pino_leave_vim()'

" }}}

