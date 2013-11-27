if !has('python')
    echo "Error: Required vim compiled with +python"
    finish
endif

" Archetype variables
let s:archetype_id=system("date")
let s:archetype_base_path=getcwd()

python << EOF
import threading
import socket as _socket
try:
    import json
except ImportError:
    import simplejson as json


# Socket host
HOST = ''
# Socket port
PORT = 9898

# This flag is set to true or false to activate or desactivate Archetype
use_archetype = False

# Socket communication: This socket is going to sending and receiving messages
# from the web server
socket_communication = None


def _parse_tabs(tabs):
    tab_list = tabs.split("\n")
    tab_structure = []
    current_tab = None
    for tab_line in tab_list:
        if not tab_line:
            continue
        if tab_line.startswith("Tab"):
            # it's a tab
            current_tab = {'name': tab_line, 'splits': [], 'active': None}
            tab_structure.append(current_tab)
        else:
            # it's a file
            active = False
            if tab_line.startswith(">"):
                active = True
            tab_line = tab_line[4:]
            current_tab['splits'].append(tab_line)
            current_tab['active'] = tab_line
    return tab_structure


def _get_tab_list():
    tabs = vim.eval("s:tab_list")
    return _parse_tabs(tabs)


def _get_json_data():
    data = {
        'id': vim.eval("s:archetype_id"),
        'base_path': vim.eval("s:archetype_base_path"),
        'tabs': _get_tab_list(),
        'current_file_name': vim.eval("expand('%:t')"),
        'current_file_path': vim.eval("expand('%:p')"),
    }
    return json.dumps(data)


class SocketListenerThread(threading.Thread):

    socket = None

    def __init__(self, host, port):
        threading.Thread.__init__(self)
        self.socket = _socket.socket(_socket.AF_INET, _socket.SOCK_STREAM)
        self.socket.connect((host, port))
        self.socket.send(json.dumps({'id': vim.eval("s:archetype_id"), 'connection_type': 'listener_socket'}))

    def send_update(self, msg):
        self.socket.send(msg)

    def run(self):
        socket = self.socket
        while True:
            data = socket.recv(1024)
            if not data:
                break
            vim.command(data)
        self.close()
        print "listener closed"

    def close(self):
        self.socket.close()


EOF


function ActivateArchetype()
python << EOF
global use_archetype
use_archetype = True
EOF
call UpdateArchetype()
:endfunction

function DeactivateArchetype()
python << EOF
global use_archetype
use_archetype = False
EOF
:endfunction

function UpdateArchetype()
" Open tabs
redir => s:tab_list
:silent tabs
redir END
python << EOF
global use_archetype
if use_archetype:
    def send_data_to_socket():
        global socket_communication
        if not socket_communication: # or not socket_communication.socket.is_alive():
            try:
                socket_communication = SocketListenerThread(HOST, PORT)
                socket_communication.start()
            except Exception:
                socket_communication = None
                print 'Archetype server is unreacheable. Make sure that is running.'

        if socket_communication:
            socket_communication.send_update(_get_json_data())
    send_data_to_socket()
EOF
:endfunction

function CloseArchetype()
python << EOF
global use_archetype
if use_archetype:
    global socket_communication
    socket_communication.close()
    socket_communication.join()
EOF
:endfunction


command Archetype call ActivateArchetype()
command DeactivateArchetype call DeactivateArchetype()


augroup archetype
    autocmd!
    " When open vim
    autocmd BufEnter * : call UpdateArchetype()

    " Edit a new file (File does not exist yet)
    "autocmd BufNewFile * : call UpdateArchetype()
    " Edit and existing file
    autocmd BufNew * : call UpdateArchetype()
    " When save
    autocmd BufWrite * : call UpdateArchetype()
    " When close
    autocmd VimLeave * : call CloseArchetype()
