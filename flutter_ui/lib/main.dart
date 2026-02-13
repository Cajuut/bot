import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Discord Bot Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5865F2),
          brightness: Brightness.dark, // Discord style is usually dark
        ),
        useMaterial3: true,
      ),
      home: const BotControlPage(),
    );
  }
}

class BotControlPage extends StatefulWidget {
  const BotControlPage({super.key});

  @override
  State<BotControlPage> createState() => _BotControlPageState();
}

class _BotControlPageState extends State<BotControlPage> {
  // Process Management
  Process? _process;
  String _currentMode = 'Node'; // 'Node' or 'Python'
  
  // Remote Connection
  IO.Socket? _socket;
  final TextEditingController _ipController = TextEditingController(text: 'localhost');
  
  // UI State
  final List<String> _logs = [];
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int _tabIndex = 0;
  
  bool get _isLocalRunning => _process != null;
  bool get _isRemoteConnected => _socket != null && _socket!.connected;

  @override
  void initState() {
    super.initState();
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
       _ipController.text = '192.168.1.100'; 
    }
    _loadCode();
  }

  @override
  void dispose() {
    _process?.kill();
    _socket?.disconnect();
    _tokenController.dispose();
    _ipController.dispose();
    _codeController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _getScriptPath() {
    if (_currentMode == 'Node') {
      final devPath = r'C:\Users\mikan\.gemini\antigravity\scratch\discord_bot_project\node_bot\index.js';
      return File(devPath).existsSync() ? devPath : 'node_bot/index.js';
    } else {
      final devPath = r'C:\Users\mikan\.gemini\antigravity\scratch\discord_bot_project\python_bot\bot.py';
      return File(devPath).existsSync() ? devPath : 'python_bot/bot.py';
    }
  }

  Future<void> _loadCode() async {
    try {
      final path = _getScriptPath();
      final file = File(path);
      if (await file.exists()) {
        final content = await file.readAsString();
        setState(() {
          _codeController.text = content;
        });
      }
    } catch (e) {
      _addLog('Failed to load code: $e');
    }
  }

  Future<void> _saveCode() async {
    try {
      final path = _getScriptPath();
      final file = File(path);
      await file.writeAsString(_codeController.text);
      _addLog('Code saved to $path');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Code saved successfully!')),
      );
    } catch (e) {
      _addLog('Failed to save code: $e');
    }
  }

  void _addLog(String message) {
    if (!mounted) return;
    setState(() {
      _logs.add(message);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // --- Local Bot Logic ---

  void _sendRemoteStop() {
    if (_socket != null && _socket!.connected) {
       _socket!.emit('command', 'stop');
    }
  }

  Future<void> _startLocalBot() async {
    if (_isLocalRunning) return;
    
    try {
      _addLog('Starting local $_currentMode bot...');
      
      String executable = _currentMode == 'Node' ? 'node' : 'python';
      String scriptPath = _getScriptPath();

      _process = await Process.start(
        executable, 
        [scriptPath],
        runInShell: true,
      );

      _addLog('$_currentMode process started (PID: ${_process!.pid})');

      _process!.stdout.transform(utf8.decoder).listen((data) => _addLog('[STDOUT] $data'));
      _process!.stderr.transform(utf8.decoder).listen((data) => _addLog('[STDERR] $data'));
      _process!.exitCode.then((code) {
        _addLog('Process exited with code $code');
        if (mounted) setState(() => _process = null);
      });
      
      setState(() {});
      
      String port = _currentMode == 'Node' ? '3000' : '3001';
      _connectToRemote('http://localhost:$port');
      
    } catch (e) {
      _addLog('Failed to start $_currentMode: $e');
      setState(() => _process = null);
    }
  }

  void _stopLocalBot() {
    if (_process != null) {
      final pid = _process!.pid;
      _addLog('Forcing stop for process tree (PID: $pid)...');
      
      if (Platform.isWindows) {
        // Force kill the process and all its children
        Process.run('taskkill', ['/F', '/T', '/PID', pid.toString()]);
      } else {
        _process!.kill(ProcessSignal.sigterm);
      }
      
      // Also send socket kill command as backup
      _sendRemoteStop();
      
      _process = null;
      setState(() {});
    }
  }

  // --- Remote Bot Logic (iOS/Android) ---

  void _connectRemote() {
    String ip = _ipController.text.trim();
    if (ip.isEmpty) return;
    if (!ip.startsWith('http')) {
      String port = _currentMode == 'Node' ? '3000' : '3001';
      ip = 'http://$ip:$port';
    }
    _connectToRemote(ip);
  }

  void _connectToRemote(String url) {
    if (_socket != null && _socket!.connected) {
      _socket!.disconnect();
    }
    _addLog('Connecting to $url...');
    try {
      _socket = IO.io(url, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': false,
      });
      _socket!.connect();
      _socket!.onConnect((_) {
        _addLog('Connected to Bot Server!');
        setState(() {});
      });
      _socket!.onDisconnect((_) {
        _addLog('Disconnected from Bot Server');
        if (mounted) setState(() {});
      });
      _socket!.on('log', (data) => _addLog(data.toString()));
      _socket!.onError((data) => _addLog('Socket Error: $data'));
    } catch (e) {
      _addLog('Connection failed: $e');
    }
  }

  void _disconnectRemote() {
    _socket?.disconnect();
    _socket = null;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: const Icon(Icons.smart_toy, color: Color(0xFF5865F2)),
          title: const Text('Discord Bot Controller'),
          backgroundColor: Theme.of(context).colorScheme.surface,
          actions: [
            if (_isRemoteConnected)
               IconButton(icon: const Icon(Icons.link_off, color: Colors.green), onPressed: _disconnectRemote)
          ],
          bottom: TabBar(
            onTap: (index) {
              setState(() => _tabIndex = index);
              if (index == 1) _loadCode();
            },
            tabs: const [
              Tab(icon: Icon(Icons.dashboard), text: 'Control'),
              Tab(icon: Icon(Icons.code), text: 'Editor'),
            ],
          ),
        ),
        body: IndexedStack(
          index: _tabIndex,
          children: [
            _buildControlView(isDesktop),
            _buildEditorView(),
          ],
        ),
      ),
    );
  }

  Widget _buildControlView(bool isDesktop) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isDesktop && !_isLocalRunning)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'Node', label: Text('Node.js'), icon: Icon(Icons.javascript)),
                  ButtonSegment(value: 'Python', label: Text('Python'), icon: Icon(Icons.code)),
                ],
                selected: {_currentMode},
                onSelectionChanged: (val) {
                  setState(() => _currentMode = val.first);
                  _loadCode();
                },
              ),
            ),
          if (isDesktop) ...[
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLocalRunning ? null : _startLocalBot,
                    icon: const Icon(Icons.play_arrow),
                    label: Text('Start $_currentMode Bot'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5865F2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLocalRunning ? _stopLocalBot : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop Bot'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade100,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
          ],
          Text(isDesktop ? 'Remote Monitor' : 'Remote Connection', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ipController,
                  decoration: const InputDecoration(
                    labelText: 'IP Address',
                    border: OutlineInputBorder(),
                    hintText: 'localhost',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isRemoteConnected ? _disconnectRemote : _connectRemote,
                child: Text(_isRemoteConnected ? 'Disconnect' : 'Connect'),
              ),
            ],
          ),
          if (_isRemoteConnected)
             Padding(
               padding: const EdgeInsets.only(top: 8.0),
               child: ElevatedButton.icon(
                  onPressed: _sendRemoteStop,
                  icon: const Icon(Icons.power_settings_new),
                  label: const Text('Remote Stop Bot'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade100),
               ),
             ),
          const SizedBox(height: 16),
          const Text('Logs:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.all(8),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _logs.length,
                itemBuilder: (context, index) => SelectableText(
                  _logs[index],
                  style: const TextStyle(color: Colors.greenAccent, fontFamily: 'Consolas', fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorView() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Editing: $_currentMode Script', style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _saveCode,
                icon: const Icon(Icons.save),
                label: const Text('Save Code'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TextField(
              controller: _codeController,
              maxLines: null,
              expands: true,
              style: const TextStyle(fontFamily: 'Consolas', fontSize: 13),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                fillColor: Color(0xFFF5F5F5),
                filled: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
