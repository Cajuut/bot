import os
import sys
import subprocess
import threading
import eventlet
import socket

# Ensure eventlet is patched for SocketIO
eventlet.monkey_patch()

from flask import Flask, request
from flask_socketio import SocketIO, emit

app = Flask(__name__)
# Allow connection from any device
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='eventlet')

# Global state
BOT_PROCESS = None
CURRENT_MODE = 'Node' # 'Node' or 'Python'

# Paths
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
NODE_SCRIPT = os.path.join(BASE_DIR, 'node_bot', 'index.js')
PYTHON_SCRIPT = os.path.join(BASE_DIR, 'python_bot', 'bot.py')

def get_script_path(mode):
    return NODE_SCRIPT if mode == 'Node' else PYTHON_SCRIPT

def get_executable(mode):
    return 'node' if mode == 'Node' else 'python'

def broadcast_log(message):
    print(f"[Manager] {message}")
    socketio.emit('log', message)

def monitor_process(proc):
    global BOT_PROCESS
    while True:
        output = proc.stdout.read(1)
        if output == '' and proc.poll() is not None:
            break
        if output:
            text = output # In Python 3, read might return bytes, handle carefully if needed
            # Simple line reading
            pass
    
    # Better line reader
    for line in iter(proc.stdout.readline, ''):
        socketio.emit('log', line.strip())
        
    broadcast_log("Bot process exited.")
    BOT_PROCESS = None

def stream_logs(process, prefix):
    # Stream stdout
    for line in iter(process.stdout.readline, b''):
        try:
            decoded = line.decode('utf-8').strip()
            if decoded:
                socketio.emit('log', f"[{prefix}] {decoded}")
        except:
            pass
    
    # When process ends
    global BOT_PROCESS
    BOT_PROCESS = None
    broadcast_log(f"{prefix} Process Stopped.")

# --- Socket Events ---

@socketio.on('connect')
def on_connect():
    emit('log', '[System] Connected to Bot Manager')
    emit('status', {'running': BOT_PROCESS is not None, 'mode': CURRENT_MODE})

@socketio.on('start_bot')
def start_bot(data):
    global BOT_PROCESS, CURRENT_MODE
    mode = data.get('mode', 'Node')
    CURRENT_MODE = mode
    
    if BOT_PROCESS is not None:
        emit('log', 'Bot is already running!')
        return

    script_path = get_script_path(mode)
    executable = get_executable(mode)
    
    if not os.path.exists(script_path):
        emit('log', f'Error: Script not found at {script_path}')
        return

    broadcast_log(f"Starting {mode} bot...")
    
    try:
        # Start process with pipes for stdout/stderr
        # On Windows, we need creationflags to prevent popup if running from no-console, 
        # but here we run from console mostly.
        env = os.environ.copy()
        # Force unbuffered output for Python
        env['PYTHONUNBUFFERED'] = '1'
        
        BOT_PROCESS = subprocess.Popen(
            [executable, script_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            cwd=BASE_DIR,
            env=env
        )
        
        # Start a thread to monitor output
        t = threading.Thread(target=stream_logs, args=(BOT_PROCESS, mode))
        t.daemon = True
        t.start()
        
        emit('status', {'running': True, 'mode': mode}, broadcast=True)
        
    except Exception as e:
        broadcast_log(f"Failed to start bot: {e}")

@socketio.on('stop_bot')
def stop_bot():
    global BOT_PROCESS
    if BOT_PROCESS:
        broadcast_log("Stopping bot...")
        # Use taskkill on Windows to ensure tree kill
        if sys.platform == 'win32':
            subprocess.run(['taskkill', '/F', '/T', '/PID', str(BOT_PROCESS.pid)])
        else:
            BOT_PROCESS.terminate()
        
        BOT_PROCESS = None
        emit('status', {'running': False, 'mode': CURRENT_MODE}, broadcast=True)
    else:
        emit('log', 'Bot is not running.')

@socketio.on('get_code')
def get_code(data):
    mode = data.get('mode', 'Node')
    path = get_script_path(mode)
    try:
        if os.path.exists(path):
            with open(path, 'r', encoding='utf-8') as f:
                content = f.read()
            return {'content': content, 'mode': mode}
        else:
            return {'error': 'File not found'}
    except Exception as e:
        return {'error': str(e)}

@socketio.on('save_code')
def save_code(data):
    mode = data.get('mode', 'Node')
    content = data.get('content', '')
    path = get_script_path(mode)
    try:
        with open(path, 'w', encoding='utf-8') as f:
            f.write(content)
        broadcast_log(f"Updated code for {mode}")
        return {'success': True}
    except Exception as e:
        return {'error': str(e)}

@socketio.on('get_ip')
def get_ip_address():
    # Helper to guess local IP
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        emit('ip_info', {'ip': ip})
    except:
        emit('ip_info', {'ip': 'Unknown'})

if __name__ == '__main__':
    # Get local IP for convenience print
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        print(f"Manager Service Running on {ip}:3000")
    except:
        print("Manager Service Running on localhost:3000")
        
    # Run on port 3000 (Replacing the Node bot's direct port)
    socketio.run(app, host='0.0.0.0', port=3000)
