" Pino.vim for the pino language server 

" Python {{{ 

python << PYTHON_END

import vim
import socket 
import json
import traceback
import threading
import Queue

import Queue

pino_socket = None
job_queue = Queue.Queue(maxsize = 128)
vim_queue = Queue.Queue(maxsize = 128)

def loop(job_queue):
    while True:
        args = job_queue.get(block = True)
        handler = args[0]
        if handler == "vim_leave_quit":
            break
        args = args[1:]
        # print "loop -> ", handler, args
        pino_socket = socket_setup()
        message = pino_send_request(pino_socket, *args)
        # print "loop <- ", handler, message, args
        vim_queue.put((handler, message, args))

loop_thread = threading.Thread(target = loop, args = (job_queue, )) 
loop_thread.start()

def pino_leave_vim():
    job_queue.put(("vim_leave_quit", ))

def socket_setup():
    global pino_socket
    try:
        if pino_socket:
            pino_socket.getpeername()
            return pino_socket
        else:
            raise socket.error
    except socket.error:
        ip = vim.eval("g:pino_server_ip")
        port = int(vim.eval("g:pino_server_port"))
        pino_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        pino_socket.connect((ip, port))
        return pino_socket

def pino_request(*args):
    job_queue.put(args)

def pino_send_request(pino_socket, *args):
    action = args[0]
    args = args[1:]
    params = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": action,
        "params": {
            "cwf": vim.eval('expand("%:p")'),
            "cwd": vim.eval('getcwd()'),
            "args": args,
        }
    }

    binary = json.dumps(params).encode("utf8")
    length = len(binary)
    binary = b"Content-Length: %d\r\nContent-Type: application/vscode-jsonrpc; charset=utf8\r\n\r\n%s" % ( length, binary)

    try:
        pino_socket.sendall(binary)
    except socket.error:
        return 

    pino_recv_buffer = ""
    while True:
        data = pino_socket.recv(0xffff)
        if not data:
            # raise socket err
            pino_socket.recv(0xffff)
        pino_recv_buffer += data

        binary = pino_recv_buffer
        begin = 0
        end = len(binary)
        header_ending = b"\r\n\r\n"
        header_ending_l = len(header_ending)

        index = binary[begin:].find(header_ending)
        if index == -1:
            break
        headers = {}
        headers_list = binary[begin:begin + index].split(b"\r\n")
        for header in headers_list:
            i = header.find(b":")
            if i == -1:
                continue
            key = header[:i]
            value = header[i+2:]
            headers[key] = value

        for k, v in headers.items():
            if v.isdigit():
                headers[k] = int(v)

        cl = headers.get(b"Content-Length", 0)
        if begin + index + cl + header_ending_l <= end:
            b = begin + index + header_ending_l
            e = b + cl
            message = json.loads(binary[b:e])
            return message.get("result", "")

def pino_timer():
    while True:
        try:
            handler, message, args = vim_queue.get(block = False)
            # print "pino_timer", handler, message, args
            handler and handler(message, *args)
        except Queue.Empty:
            # print "empty break"
            break

def pino_project_init():
    pino_request(None, "init")

def pino_project_reinit():
    pino_request(None, "reinit")

def pino_project_stat():
    pino_request(None, "stat")

def pino_project_save():
    pino_request(None, "save")

def quick_fix(result, _, __, type_):
    if type_ == 0 and len(result) == 1:
        filename = result[0]["filename"]
        bufnr = vim.Function("bufnr")(filename)
        if bufnr != -1:
            cmd = "buffer %d" % bufnr
        else:
            cmd = "edit! %s" % filename
        try:
            vim.command(cmd)
        except Exception:
            pass
        lnum = result[0]["lnum"]
        # col = result[0]["text"].find(word)
        # vim.command("echom %s" % repr((locals())))
        vim.Function("cursor")(lnum, 1)
        return 
    vim.Function("setqflist")(result)
    vim.command('copen')

def pino_goto(word):
    pino_request(quick_fix, "search_word", word, 0)

def pino_search(word):
    pino_request(quick_fix, "search_word", word, 2)

def pino_search_code(word):
    pino_request(quick_fix, "search_word", word, 1)

def pino_find_file(word):
    pino_request(quick_fix, "search_word", word, 0)

def completion(result, *args):
    l = result
    if l:
        l = l.split("\n")
        items = ",".join([('"%s"' % s) for s in l])
        vim.command("call s:handle_completion([%s])" % items)

def pino_completion(word):
    pino_request(completion, "completion", word, 10)

PYTHON_END
" }}}

" Vim Script {{{
function! pino#project_init()
    execute 'python pino_project_init()'
endfunction 

function!pino#project_reinit()
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

