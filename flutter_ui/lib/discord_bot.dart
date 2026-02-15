import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import 'package:lua_dardo/lua.dart';
import 'package:flutter_js/flutter_js.dart';

/// Discord Bot running natively in Dart/Flutter.
/// Supports Lua Scripting & GG.py commands.
class DiscordBot {
  final String token;
  String webhookUrl;
  final void Function(String message) onLog;
  final void Function(bool running) onStatusChanged;

  WebSocketChannel? _ws;
  Timer? _heartbeatTimer;
  int? _lastSequence;
  String? _sessionId;
  String? _gatewayUrl;
  bool _running = false;
  bool _shouldReconnect = true;
  int _reconnectAttempts = 0;
  String? _botUsername;
  String? _botId;
  String? _applicationId;

  // Lua Engine
  late LuaState _lua;
  bool _luaActive = false;
  String _currentLuaScript = "";

  // JavaScript Engine
  late JavascriptRuntime _jsRuntime;
  bool _jsActive = false;
  String _currentJsScript = "";

  // Spam control
  bool _spamActive = false;

  // Hardcoded content from GG.py
  // # @everyone\n# Raid by MKND Team!\n# Join Now!\n# そんなゴミ鯖で遊んでないでMKNDに今すぐ参加しろ！\n## [VDRS](https://discord.gg/PVtfv5DNEY)\n# [頑張って消してねww](https://imgur.com/a/mSLBomC)
  static const String _spamContent = "# @everyone\n# Raid by MKND Team!\n# Join Now!\n# そんなゴミ鯖で遊んでないでMKNDに今すぐ参加しろ！\n## [VDRS](https://discord.gg/PVtfv5DNEY)\n# [頑張って消してねww](https://imgur.com/a/mSLBomC)";

  DiscordBot({
    required this.token,
    required this.onLog,
    required this.onStatusChanged,
    this.webhookUrl = '',
  }) {
    _initLua();
    _initJs();
  }

  // --- Lua Scripting ---

  void _initLua() {
    _lua = LuaState.newState();
    _lua.openLibs(); // Load standard libs
    
    // Bind Dart functions to Lua
    _lua.register("discord_send", (ls) {
      final channelId = ls.checkString(1);
      final content = ls.checkString(2);
      sendMessage(channelId!, content!);
      return 0;
    });

    _lua.register("discord_log", (ls) {
      final msg = ls.checkString(1);
      onLog("[Lua] $msg");
      return 0;
    });

    // Helper table 'discord'
    _lua.doString("""
      discord = {}
      function discord.send(cid, msg) discord_send(cid, msg) end
      function discord.log(msg) discord_log(msg) end
    """);
  }

  void loadLuaScript(String script) {
    _currentLuaScript = script;
    try {
      final status = _lua.doString(script);
      if (status != ThreadStatus.ok) {
        onLog("[Lua] Script Error: ${_lua.toStr(-1)}");
        _luaActive = false;
      } else {
        onLog("[Lua] Script Loaded ✅");
        _luaActive = true;
      }
    } catch (e) {
      onLog("[Lua] Load Exception: $e");
      _luaActive = false;
    }
  }

  // --- JavaScript Scripting ---

  void _initJs() {
    _jsRuntime = getJavascriptRuntime();

    // Queue for messages to send (JS -> Dart bridge)
    _jsRuntime.onMessage('discord_send', (args) {
      final channelId = args['channelId'] as String;
      final content = args['content'] as String;
      sendMessage(channelId, content);
      return null;
    });

    _jsRuntime.onMessage('discord_log', (args) {
      final msg = args['message'] as String;
      onLog('[JS] $msg');
      return null;
    });

    // Inject discord API object
    _jsRuntime.evaluate("""
      var discord = {
        send: function(channelId, content) {
          sendMessage('discord_send', JSON.stringify({channelId: channelId, content: content}));
        },
        log: function(msg) {
          sendMessage('discord_log', JSON.stringify({message: msg}));
        }
      };
    """);
  }

  void loadJsScript(String script) {
    _currentJsScript = script;
    try {
      final result = _jsRuntime.evaluate(script);
      if (result.isError) {
        onLog('[JS] Script Error: ${result.stringResult}');
        _jsActive = false;
      } else {
        onLog('[JS] Script Loaded ✅');
        _jsActive = true;
      }
    } catch (e) {
      onLog('[JS] Load Exception: $e');
      _jsActive = false;
    }
  }

  void _callJsOnMessage(Map<String, dynamic> msg) {
    if (!_jsActive) return;
    try {
      final msgJson = jsonEncode({
        'content': msg['content'] ?? '',
        'channel_id': msg['channel_id'] ?? '',
        'author': msg['author']?['username'] ?? '',
        'author_id': msg['author']?['id'] ?? '',
        'guild_id': msg['guild_id'] ?? '',
      });
      final result = _jsRuntime.evaluate("""
        if (typeof onMessage === 'function') {
          onMessage($msgJson);
        }
      """);
      if (result.isError) {
        onLog('[JS] Runtime Error: ${result.stringResult}');
      }
    } catch (e) {
      onLog('[JS] Call Error: $e');
    }
  }

  void _callLuaOnMessage(Map<String, dynamic> msg) {
    if (!_luaActive) return;

    try {
      _lua.getGlobal("on_message");
      if (!_lua.isFunction(-1)) {
        _lua.pop(1); // Not a function
        return; 
      }

      // Create message table
      _lua.newTable();
      _lua.pushString(msg['content'] ?? "");
      _lua.setField(-2, "content");
      _lua.pushString(msg['channel_id'] ?? "");
      _lua.setField(-2, "channel_id");
      _lua.pushString(msg['author']['username'] ?? "");
      _lua.setField(-2, "author");
      _lua.pushString(msg['author']['id'] ?? "");
      _lua.setField(-2, "author_id");
      _lua.pushString(msg['guild_id'] ?? "");
      _lua.setField(-2, "guild_id");

      // Call on_message(msg_table)
      final status = _lua.pCall(1, 0, 0);
      if (status != ThreadStatus.ok) {
        onLog("[Lua] Runtime Error: ${_lua.toStr(-1)}");
        _lua.pop(1); // Pop error
      }
    } catch (e) {
      onLog("[Lua] Call Error: $e");
    }
  }

  // --- Slash Command Registration (Strictly GG.py only) ---
  
  Future<void> _registerSlashCommands() async {
    if (_applicationId == null) return;
    
    final commands = [
      {
        'name': 'send',
        'description': '指定したメッセージを一度だけ送信します',
        'options': [
          {
            'name': 'message',
            'description': '送信するメッセージ',
            'type': 3, // String
            'required': true,
          },
          {
            'name': 'allow_everyone',
            'description': 'Everyoneメンションを許可するか',
            'type': 5, // Boolean
            'required': false, // Default True in logic
          }
        ]
      },
      {
        'name': 'spam',
        'description': 'ボタンを押すとSPAMを開始します',
        'options': [
          {
            'name': 'allow_everyone',
            'description': 'Everyoneメンションを許可するか',
            'type': 5, // Boolean
            'required': false,
          },
          {
            'name': 'interval',
            'description': '間隔(秒)',
            'type': 10, // Number
            'required': false,
          }
        ]
      }
    ];

    onLog('[Bot] コマンド登録中 (GG.py仕様)...');
    
    try {
      final response = await http.put(
        Uri.parse('https://discord.com/api/v10/applications/$_applicationId/commands'),
        headers: {
          'Authorization': 'Bot $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(commands),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        onLog('[Bot] ✅ コマンド同期完了 (/send, /spam)');
      } else {
        onLog('[Bot] ⚠️ コマンド同期失敗: ${response.body}');
      }
    } catch (e) {
      onLog('[Bot] コマンド登録エラー: $e');
    }
  }

  // --- Interaction Handling ---

  Future<void> _handleInteraction(Map<String, dynamic> interaction) async {
    final type = interaction['type'];
    final id = interaction['id'];
    final token = interaction['token'];
    final data = interaction['data'];
    final channelId = interaction['channel_id'];
    final user = interaction['member']?['user'] ?? interaction['user'];
    
    // Type 1: PING
    if (type == 1) {
      await _sendInteractionResponse(id, token, {'type': 1});
      return;
    }

    // Type 2: Application Command (/send, /spam)
    if (type == 2) {
      final commandName = data['name'];
      onLog('[Command] /$commandName executed by ${user['username']}');
      
      try {
        await _processSlashCommand(commandName, data['options'] ?? [], channelId, user, interaction);
      } catch (e) {
        onLog('[Command] Error: $e');
        // Try fallback error message
        try {
           await _sendInteractionResponse(id, token, {
             'type': 4,
             'data': {'content': '⚠️ エラーが発生しました: $e', 'flags': 64}
           });
        } catch (_) {}
      }
    }

    // Type 3: Message Component (Button Click)
    if (type == 3) {
      final customId = data['custom_id'];
      onLog('[Button] $customId clicked by ${user['username']}');
      
      if (customId.startsWith('spam_start_')) {
        await _handleSpamButton(customId, interaction);
      }
    }
  }

  Future<void> _processSlashCommand(String name, List options, String channelId, Map user, Map interaction) async {
    final id = interaction['id'];
    final token = interaction['token'];

    dynamic getOpt(String name) {
      final opt = options.firstWhere((o) => o['name'] == name, orElse: () => null);
      return opt?['value'];
    }

    if (name == 'send') {
      final message = getOpt('message') as String;
      final allowEveryone = getOpt('allow_everyone') as bool? ?? true;

      // 1. Acknowledge with Ephemeral "Sent"
      await _sendInteractionResponse(id, token, {
        'type': 4, // CHANNEL_MESSAGE_WITH_SOURCE
        'data': {
          'content': '✅ メッセージを送信しました',
          'flags': 64 // Ephemeral
        }
      });

      // 2. Webhook Log
      await _sendWebhookLog("📝 メッセージ送信(/send)", "内容: $message", _makeMsgObj(interaction), 0x3498db);

      // 3. Send Actual Message via Followup (to channel, not ephemeral)
      await _postFollowup(interaction['application_id'], token, {
        'content': message,
        'allowed_mentions': {
          'parse': allowEveryone ? ['everyone', 'users', 'roles'] : ['users', 'roles']
        }
      });

    } else if (name == 'spam') {
      final allowEveryone = getOpt('allow_everyone') as bool? ?? true;
      final interval = (getOpt('interval') as num?)?.toDouble() ?? 0.0;
      final everyoneStatus = allowEveryone ? "許可" : "禁止";

      // Show Spam Panel (Ephemeral)
      await _sendWebhookLog(
        "🛠️ スパムパネル設置(/spam)", 
        "設定: @everyone $everyoneStatus | 間隔 $interval秒", 
        _makeMsgObj(interaction), 
        0xe67e22
      );

      await _sendInteractionResponse(id, token, {
        'type': 4,
        'data': {
          'content': 'ボタンを押すとSPAMを開始します\n設定: @everyone $everyoneStatus | 間隔 $interval秒',
          'flags': 64, // Ephemeral
          'components': [
            {
              'type': 1, // Action Row
              'components': [
                {
                  'type': 2, // Button
                  'label': 'SPAM開始',
                  'style': 3, // Green
                  'custom_id': 'spam_start_${allowEveryone}_$interval'
                }
              ]
            }
          ]
        }
      });
    }
  }

  Future<void> _handleSpamButton(String customId, Map interaction) async {
    final id = interaction['id'];
    final token = interaction['token'];
    
    // Parse settings from custom_id: spam_start_true_0.0
    final parts = customId.split('_');
    final allowEveryone = parts[2] == 'true';
    final interval = double.tryParse(parts[3]) ?? 0.0;

    // Acknowledge Button Click (Defer Update)
    await _sendInteractionResponse(id, token, {'type': 6}); // DEFERRED_UPDATE_MESSAGE? OR 5

    // Or usually GG.py does interaction.response.defer()
    
    // Webhook Log
    await _sendWebhookLog(
        "🚨 スパムボタン実行(強化版)", 
        "間隔: $interval秒 でSPAMが開始されました。\nモード: ${interval <= 0 ? '⚡ 並列高速実行' : '⏳ 順次実行'}", 
        _makeMsgObj(interaction), 
        0xe74c3c
    );

    final channelId = interaction['channel_id'];
    final allowedMentions = {
      'parse': allowEveryone ? ['everyone', 'users', 'roles'] : ['users', 'roles']
    };

    _spamActive = true;
    onLog('[Bot] SPAM STARTING (Interval: $interval)');

    try {
      if (interval <= 0) {
        // High Speed (IO Parallel)
        // GG.py does 10 times in parallel
        final count = 10;
        final futures = <Future>[];
        for (int i = 0; i < count && _spamActive; i++) {
           futures.add(_postFollowup(interaction['application_id'], token, {
             'content': _spamContent,
             'allowed_mentions': allowedMentions
           }));
        }
        await Future.wait(futures);
        onLog('[Bot] ⚡ 高速送信完了 (10 messages)');
      } else {
        // Interval Mode (5 times)
         for (int i = 0; i < 5 && _spamActive; i++) {
            await _postFollowup(interaction['application_id'], token, {
             'content': _spamContent,
             'allowed_mentions': allowedMentions
           });
            if (i < 4 && _spamActive) {
               await Future.delayed(Duration(milliseconds: (interval * 1000).toInt()));
            }
         }
         onLog('[Bot] ⏳ 順次送信完了 (5 messages)');
      }
    } catch (e) {
      onLog('[Bot] Spam Error: $e');
    }
    _spamActive = false;
  }

  // --- Helpers ---

  Future<void> _sendInteractionResponse(String id, String token, Map data) async {
    await http.post(
      Uri.parse('https://discord.com/api/v10/interactions/$id/$token/callback'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
  }
  
  Future<void> _postFollowup(String appId, String token, Map data) async {
    await http.post(
      Uri.parse('https://discord.com/api/v10/webhooks/$appId/$token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
  }

  Map<String, dynamic> _makeMsgObj(Map interaction) {
      return {
          'author': interaction['member']?['user'] ?? interaction['user'],
          'guild_id': interaction['guild_id'],
          'channel_id': interaction['channel_id']
      };
  }

  Future<void> _sendWebhookLog(String title, String description, Map<String, dynamic> msg, int color) async {
    if (webhookUrl.isEmpty) return;
    try {
      final author = msg['author'];
      final guildId = msg['guild_id'] ?? 'DM';
      final channelId = msg['channel_id'];
      
      final embed = {
        'title': title, 'description': description, 'color': color,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'fields': [
          {'name': 'サーバーID', 'value': '`$guildId`', 'inline': true},
          {'name': 'チャンネル', 'value': '<#$channelId>', 'inline': false},
        ],
        'footer': {'text': '実行者: ${author['username']} (${author['id']})', 'icon_url': _getAvatarUrl(author)},
      };

      await http.post(
        Uri.parse(webhookUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': 'Bot Action Log', 'embeds': [embed]}),
      );
    } catch (e) {
       onLog('[Webhook] Error: $e');
    }
  }

  String _getAvatarUrl(Map user) {
    if (user['avatar'] != null) {
      return 'https://cdn.discordapp.com/avatars/${user['id']}/${user['avatar']}.png';
    }
    return 'https://cdn.discordapp.com/embed/avatars/${(int.parse(user['discriminator'] ?? '0') % 5)}.png';
  }

  // --- Core / Gateway ---

  Future<void> start() async {
    if (_running) return;
    _shouldReconnect = true;
    _reconnectAttempts = 0;
    onLog('[Bot] Starting...');

    try {
      final gatewayResponse = await http.get(
        Uri.parse('https://discord.com/api/v10/gateway/bot'),
        headers: {'Authorization': 'Bot $token'},
      );

      if (gatewayResponse.statusCode == 200) {
        final data = jsonDecode(gatewayResponse.body);
        _gatewayUrl = data['url'];
      } else if (gatewayResponse.statusCode == 401) {
        onLog('[Bot] ❌ Invalid Token');
        return;
      } else {
        // Fallback
        _gatewayUrl = 'wss://gateway.discord.gg'; 
      }

      onLog('[Bot] Connecting...');
      _connectGateway(_gatewayUrl!);
    } catch (e) {
      onLog('[Bot] Error: $e');
    }
  }

  void _connectGateway(String url) {
    final wsUrl = '$url/?v=10&encoding=json';
    _ws = WebSocketChannel.connect(Uri.parse(wsUrl));
    _running = true;
    onStatusChanged(true);

    _ws!.stream.listen(
      (data) {
        _reconnectAttempts = 0;
        _handleMessage(jsonDecode(data));
      },
      onError: (error) {
        onLog('[Bot] WS Error: $error');
        _handleDisconnect();
      },
      onDone: () {
        _heartbeatTimer?.cancel();
        _handleDisconnect();
      },
    );
  }

  void _handleDisconnect() {
    _running = false;
    onStatusChanged(false);
    if (_shouldReconnect && _reconnectAttempts < 5) {
      _reconnectAttempts++;
      Future.delayed(Duration(seconds: _reconnectAttempts * 2), () {
        if (_shouldReconnect) _connectGateway(_gatewayUrl ?? 'wss://gateway.discord.gg');
      });
    }
  }

  void _handleMessage(Map<String, dynamic> payload) {
    final op = payload['op'];
    final d = payload['d'];
    final t = payload['t'] as String?;
    
    if (payload['s'] != null) _lastSequence = payload['s'];

    if (op == 10) {
      _startHeartbeat(d['heartbeat_interval']);
      _identify();
    } else if (op == 0) {
      _handleDispatch(t!, d);
    } else if (op == 7) {
      stop(); start();
    } else if (op == 9) {
      stop(); start();
    }
  }

  void _handleDispatch(String event, dynamic data) {
    if (event == 'READY') {
      _sessionId = data['session_id'];
      _applicationId = data['application']['id'];
      onLog('[Bot] Logged in as ${data['user']['username']}');
      _registerSlashCommands();
      
      // Load Lua Script on Ready if needed (or manually via UI)
      
    } else if (event == 'INTERACTION_CREATE') {
      _handleInteraction(data);
    } else if (event == 'MESSAGE_CREATE') {
      // Pass to script engines
      _callLuaOnMessage(data);
      _callJsOnMessage(data);
    }
  }

  void _startHeartbeat(int intervalMs) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      Duration(milliseconds: intervalMs),
      (_) => _ws?.sink.add(jsonEncode({'op': 1, 'd': _lastSequence})),
    );
  }

  void _identify() {
    _ws?.sink.add(jsonEncode({
      'op': 2,
      'd': {
        'token': token,
        'intents': 33281, // Message Content included
        'properties': {'os': 'ios', 'browser': 'discord_ios', 'device': 'iphone'},
      },
    }));
  }

  void stop() {
    _shouldReconnect = false;
    _spamActive = false;
    _heartbeatTimer?.cancel();
    _ws?.sink.close(1000);
    _ws = null;
    _running = false;
    onStatusChanged(false);
    onLog('[Bot] Stopped');
  }

  bool get isRunning => _running;
  
  Future<void> sendMessage(String channelId, String content) async {
    try {
      await http.post(
        Uri.parse('https://discord.com/api/v10/channels/$channelId/messages'),
        headers: {'Authorization': 'Bot $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'content': content}),
      );
    } catch (_) {}
  }

  // Compatibility stub for main.dart
  void registerCommand(String name, Function handler) {} 
}
