import 'package:flutter/material.dart';
import 'discord_bot.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Discord Bot Controller',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5865F2),
          brightness: Brightness.dark,
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
  // Bot instance
  DiscordBot? _bot;
  bool _botRunning = false;

  // UI State
  final List<String> _logs = [];
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _webhookController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int _tabIndex = 0;

  // Custom commands (user-defined)
  final List<Map<String, String>> _customCommands = [];
  // Lua Editor
  final TextEditingController _luaScriptController = TextEditingController(text: '''
-- Lua Script Example
function on_message(msg)
  if msg.content == "!ping" then
    discord.send(msg.channel_id, "Pong from Lua! 🌙")
  elseif msg.content == "!hello" then
    discord.send(msg.channel_id, "Hello " .. msg.author .. "!")
  end
end
''');
  // JavaScript Editor
  final TextEditingController _jsScriptController = TextEditingController(text: '''
// JavaScript Script Example
function onMessage(msg) {
  if (msg.content === "!jsping") {
    discord.send(msg.channel_id, "Pong from JavaScript! \u2728");
  }
}
''');
  final TextEditingController _cmdResponseController = TextEditingController();
  final TextEditingController _cmdNameController = TextEditingController();

  // Background Audio
  final AudioPlayer _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _initAudioSession();
    WakelockPlus.enable(); // Keep screen on (optional, but good for stability)
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _tokenController.text = prefs.getString('bot_token') ?? '';
      _webhookController.text = prefs.getString('webhook_url') ?? '';
      final savedScript = prefs.getString('lua_script');
      if (savedScript != null && savedScript.isNotEmpty) {
        _luaScriptController.text = savedScript;
      }
      final savedJs = prefs.getString('js_script');
      if (savedJs != null && savedJs.isNotEmpty) {
        _jsScriptController.text = savedJs;
      }
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bot_token', _tokenController.text.trim());
    await prefs.setString('webhook_url', _webhookController.text.trim());
    await prefs.setString('lua_script', _luaScriptController.text);
    await prefs.setString('js_script', _jsScriptController.text);
  }

  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    // Enable MixWithOthers to allow Youtube/Spotify to play alongside
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        flags: AndroidAudioFlags.none,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ));

    // Preload silence track (10 min silence)
    try {
      await _player.setUrl('https://github.com/anars/blank-audio/raw/master/10-minutes-of-silence.mp3');
      await _player.setLoopMode(LoopMode.all);
    } catch (e) {
      debugPrint("Audio Init Error: $e");
    }
  }

  Future<void> _startBackgroundAudio() async {
    try {
      if (!_player.playing) {
        await _player.play();
      }
    } catch (e) {
      _addLog('[Audio] Error: $e');
    }
  }

  Future<void> _stopBackgroundAudio() async {
    try {
      if (_player.playing) {
        await _player.pause();
      }
    } catch (e) {
      _addLog('[Audio] Stop Error: $e');
    }
  }

  @override
  void dispose() {
    _bot?.stop();
    _player.dispose();
    _tokenController.dispose();
    _webhookController.dispose();
    _scrollController.dispose();
    _cmdNameController.dispose();
    _cmdResponseController.dispose();
    _luaScriptController.dispose();
    _jsScriptController.dispose();
    super.dispose();
  }
  void _addLog(String message) {
    if (!mounted) return;
    setState(() {
      _logs.add(message);
      if (_logs.length > 500) _logs.removeAt(0);
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

  void _startBot() {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      _addLog('[Error] Tokenを入力してください');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tokenを入力してください')),
      );
      return;
    }

    _bot = DiscordBot(
      token: token,
      webhookUrl: _webhookController.text.trim(),
      onLog: _addLog,
      onStatusChanged: (running) {
        if (mounted) setState(() => _botRunning = running);
      },
    );

    // Register custom commands
    for (final cmd in _customCommands) {
      final name = cmd['name']!;
      final response = cmd['response']!;
      _bot!.registerCommand(name, (msg) async {
        await _bot!.sendMessage(msg['channel_id'], response);
      });
    }

    _bot!.start();
    _saveSettings();
    _startBackgroundAudio();
    
    // Auto-load scripts on start
    _applyLuaScript();
    _applyJsScript();
  }

  void _applyLuaScript() {
    if (_bot != null && _bot!.isRunning) {
      _bot!.loadLuaScript(_luaScriptController.text);
      _addLog('[Lua] Script updated and applied.');
      _saveSettings();
    } else {
      _addLog('[Lua] Bot is not running. Start bot first.');
    }
  }

  void _applyJsScript() {
    if (_bot != null && _bot!.isRunning) {
      _bot!.loadJsScript(_jsScriptController.text);
      _addLog('[JS] Script updated and applied.');
      _saveSettings();
    } else {
      _addLog('[JS] Bot is not running. Start bot first.');
    }
  }

  void _stopBot() {
    _bot?.stop();
    _stopBackgroundAudio();
    setState(() => _botRunning = false);
  }

  void _addCustomCommand() {
    final name = _cmdNameController.text.trim().toLowerCase();
    final response = _cmdResponseController.text.trim();
    if (name.isEmpty || response.isEmpty) return;

    setState(() {
      _customCommands.add({'name': name, 'response': response});
    });

    // If bot is running, register it now
    if (_bot != null && _bot!.isRunning) {
      _bot!.registerCommand(name, (msg) async {
        await _bot!.sendMessage(msg['channel_id'], response);
      });
    }

    _addLog('[System] コマンド追加: !$name → $response');
    _cmdNameController.clear();
    _cmdResponseController.clear();
  }

  void _removeCustomCommand(int index) {
    final cmd = _customCommands[index];
    setState(() {
      _customCommands.removeAt(index);
    });
    _addLog('[System] コマンド削除: !${cmd['name']}');
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          leading: const Padding(
            padding: EdgeInsets.all(12.0),
            child: Icon(Icons.smart_toy, color: Color(0xFF5865F2)),
          ),
          title: const Text('Discord Bot'),
          backgroundColor: Theme.of(context).colorScheme.surface,
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Control', icon: Icon(Icons.gamepad)),
              Tab(text: 'Lua', icon: Icon(Icons.code)),
              Tab(text: 'JavaScript', icon: Icon(Icons.javascript)),
              Tab(text: 'Logs', icon: Icon(Icons.terminal)),
            ],
            labelColor: Color(0xFF5865F2),
            unselectedLabelColor: Colors.grey,
            indicatorColor: Color(0xFF5865F2),
          ),
        ),
        body: TabBarView(
          children: [
            _buildControlTab(),
            _buildLuaTab(),
            _buildJsTab(),
            _buildLogsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildLuaTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF2B2D31),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade800),
              ),
              padding: const EdgeInsets.all(8),
              child: TextField(
                controller: _luaScriptController,
                maxLines: null,
                expands: true,
                style: const TextStyle(fontFamily: 'monospace', color: Colors.white),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Write Lua code here...',
                  hintStyle: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _applyLuaScript,
              icon: const Icon(Icons.save),
              label: const Text('Apply Script'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5865F2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJsTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF2B2D31),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade800),
              ),
              padding: const EdgeInsets.all(8),
              child: TextField(
                controller: _jsScriptController,
                maxLines: null,
                expands: true,
                style: const TextStyle(fontFamily: 'monospace', color: Colors.white),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Write JavaScript code here...',
                  hintStyle: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _applyJsScript,
              icon: const Icon(Icons.javascript),
              label: const Text('Apply JS Script'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade700,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status indicator
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _botRunning 
                ? const Color(0xFF57F287).withOpacity(0.15) 
                : const Color(0xFFED4245).withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _botRunning 
                  ? const Color(0xFF57F287).withOpacity(0.5) 
                  : const Color(0xFFED4245).withOpacity(0.3),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  _botRunning ? Icons.check_circle : Icons.power_settings_new,
                  size: 48,
                  color: _botRunning ? const Color(0xFF57F287) : const Color(0xFFED4245),
                ),
                const SizedBox(height: 8),
                Text(
                  _botRunning ? 'Bot is Online' : 'Bot is Offline',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _botRunning ? const Color(0xFF57F287) : const Color(0xFFED4245),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _botRunning ? 'Running on this device' : 'Tap Start to go online',
                  style: TextStyle(color: Colors.grey.shade400),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Token input
          TextField(
            controller: _tokenController,
            decoration: const InputDecoration(
              labelText: 'Bot Token',
              hintText: 'Discord Botのトークンを貼り付け',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.key),
            ),
            obscureText: true,
            enabled: !_botRunning,
          ),
          const SizedBox(height: 12),

          // Webhook URL input (optional)
          TextField(
            controller: _webhookController,
            decoration: const InputDecoration(
              labelText: 'Webhook URL (任意)',
              hintText: 'ログ送信用 Webhook URL',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.webhook),
            ),
            enabled: !_botRunning,
          ),
          const SizedBox(height: 16),

          // Start/Stop buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _botRunning ? null : _startBot,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Bot'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF57F287),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _botRunning ? _stopBot : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop Bot'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFED4245),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Built-in commands info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF5865F2).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📋 GG.py Commands', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                _commandRow('/send', 'メッセージ送信 (Everyone設定可)'),
                _commandRow('/spam', 'スパムパネル表示 (ボタンで開始)'),
                const SizedBox(height: 8),
                Text(
                  '※ Discordのスラッシュコマンドメニューから実行してください',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _commandRow(String cmd, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF5865F2).withOpacity(0.3),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(cmd, style: const TextStyle(fontFamily: 'Consolas', fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Text(desc, style: TextStyle(color: Colors.grey.shade400)),
        ],
      ),
    );
  }

  Widget _buildCommandsView() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('➕ Add Custom Command', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(width: 4),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _cmdNameController,
                  decoration: const InputDecoration(
                    labelText: 'Command Name',
                    hintText: 'e.g. help',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _cmdResponseController,
            decoration: const InputDecoration(
              labelText: 'Bot Response',
              hintText: 'e.g. Here is a list of commands...',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _addCustomCommand,
            icon: const Icon(Icons.add),
            label: const Text('Add Command'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5865F2),
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          Text('Custom Commands (${_customCommands.length})', 
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Expanded(
            child: _customCommands.isEmpty
              ? Center(
                  child: Text(
                    'No custom commands yet.\nAdd one above!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                )
              : ListView.builder(
                  itemCount: _customCommands.length,
                  itemBuilder: (context, index) {
                    final cmd = _customCommands[index];
                    return Card(
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF5865F2).withOpacity(0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('!${cmd['name']}', style: const TextStyle(fontFamily: 'Consolas', fontWeight: FontWeight.bold)),
                        ),
                        title: Text(cmd['response']!, maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Color(0xFFED4245)),
                          onPressed: () => _removeCustomCommand(index),
                        ),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('📜 Logs', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _logs.clear()),
                icon: const Icon(Icons.delete_sweep, size: 18),
                label: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(8),
              child: _logs.isEmpty
                ? Center(
                    child: Text(
                      'No logs yet.\nStart the bot to see activity.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      Color logColor = Colors.greenAccent;
                      if (log.contains('[Error]') || log.contains('error') || log.contains('Failed')) {
                        logColor = const Color(0xFFED4245);
                      } else if (log.contains('[Bot]')) {
                        logColor = const Color(0xFF5865F2);
                      } else if (log.contains('[MSG]')) {
                        logColor = const Color(0xFFFEE75C);
                      } else if (log.contains('[System]')) {
                        logColor = Colors.cyanAccent;
                      }
                      return SelectableText(
                        log,
                        style: TextStyle(
                          color: logColor,
                          fontFamily: 'Consolas',
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
