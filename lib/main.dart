import 'dart:convert';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SiriApp());
}

// ============================================================
// SIRI APP ENTRY POINT
// ============================================================

class SiriApp extends StatelessWidget {
  const SiriApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Siri',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF080808),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const SiriHome(),
    );
  }
}

// ============================================================
// SIRI HOME SCREEN
// ============================================================

class SiriHome extends StatefulWidget {
  const SiriHome({super.key});

  @override
  State<SiriHome> createState() => _SiriHomeState();
}

class _SiriHomeState extends State<SiriHome> {
  late final GeminiApiService _gemini;

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _thinking = false;
  final List<ChatMessage> _messages = [];

  static const String siriPhotoUrl =
      'https://upload.wikimedia.org/wikipedia/commons/thumb/d/d3/Siri_logo.svg/512px-Siri_logo.svg.png';

  static const String geminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  @override
  void initState() {
    super.initState();
    _gemini = GeminiApiService(
      apiKey: geminiApiKey,
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    if (geminiApiKey.isEmpty) {
      _showMessage(
        'GEMINI_API_KEY missing.\n'
        'GitHub Actions Secrets में GEMINI_API_KEY सेट करें।',
      );
      return;
    }

    setState(() {
      _messages.add(
        ChatMessage(
          role: MessageRole.user,
          text: text,
        ),
      );
      _thinking = true;
    });

    _textController.clear();
    _scrollToBottom();

    try {
      final reply = await _gemini.sendMessage(text);
      if (!mounted) return;
      setState(() {
        _thinking = false;
        _messages.add(
          ChatMessage(
            role: MessageRole.assistant,
            text: reply,
          ),
        );
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _thinking = false;
      });
      _showMessage('Error: $e');
    }
  }

  Future<void> _requestMicrophone() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      _showMessage('Microphone permission required.');
    } else {
      _showMessage('Microphone permission granted!');
    }
  }

  Future<void> _requestCallPermission() async {
    final status = await Permission.phone.request();
    if (!status.isGranted) {
      _showMessage('Phone permission was not granted.');
    }
  }

  Future<void> _requestSmsPermission() async {
    final status = await Permission.sms.request();
    if (!status.isGranted) {
      _showMessage('SMS permission was not granted.');
    }
  }

  Future<void> _openOverlaySettings() async {
    if (!Platform.isAndroid) return;
    try {
      const intent = AndroidIntent(
        action: 'android.settings.action.MANAGE_OVERLAY_PERMISSION',
      );
      await intent.launch();
    } catch (e) {
      _showMessage('Unable to open Overlay Settings.');
    }
  }

  Future<void> _openNotificationSettings() async {
    if (!Platform.isAndroid) return;
    try {
      const intent = AndroidIntent(
        action: 'android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS',
      );
      await intent.launch();
    } catch (e) {
      _showMessage('Unable to open Notification Settings.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        titleSpacing: 8,
        leading: Padding(
          padding: const EdgeInsets.all(7),
          child: ClipOval(
            child: Image.network(
              siriPhotoUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) {
                return Container(
                  color: Colors.deepPurple,
                  child: const Icon(
                    Icons.auto_awesome,
                    color: Colors.white,
                  ),
                );
              },
            ),
          ),
        ),
        title: const Text(
          'Siri',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 21,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'mic':
                  await _requestMicrophone();
                  break;
                case 'phone':
                  await _requestCallPermission();
                  break;
                case 'sms':
                  await _requestSmsPermission();
                  break;
                case 'overlay':
                  await _openOverlaySettings();
                  break;
                case 'notifications':
                  await _openNotificationSettings();
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'mic',
                child: Row(
                  children: [
                    Icon(Icons.mic),
                    SizedBox(width: 10),
                    Text('Microphone Permission'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'phone',
                child: Row(
                  children: [
                    Icon(Icons.phone),
                    SizedBox(width: 10),
                    Text('Call Permission'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'sms',
                child: Row(
                  children: [
                    Icon(Icons.sms),
                    SizedBox(width: 10),
                    Text('SMS Permission'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'overlay',
                child: Row(
                  children: [
                    Icon(Icons.layers),
                    SizedBox(width: 10),
                    Text('Overlay Settings'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'notifications',
                child: Row(
                  children: [
                    Icon(Icons.notifications),
                    SizedBox(width: 10),
                    Text('Notification Access'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatus(),
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (_, index) {
                      return _buildMessage(_messages[index]);
                    },
                  ),
          ),
          if (_thinking)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('Siri is thinking...'),
                ],
              ),
            ),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildStatus() {
    final bool hasKey = geminiApiKey.isNotEmpty;
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: hasKey
            ? Colors.green.withOpacity(.12)
            : Colors.red.withOpacity(.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasKey ? Colors.green : Colors.red,
            ),
          ),
          const SizedBox(width: 10),
          Text(hasKey ? 'Ready' : 'API Key Missing'),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepPurple.withOpacity(.35),
                    blurRadius: 35,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.network(
                  siriPhotoUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) {
                    return Container(
                      color: Colors.deepPurple,
                      child: const Icon(
                        Icons.auto_awesome,
                        size: 60,
                        color: Colors.white,
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 25),
            const Text(
              'Siri',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Your AI Assistant',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Type any message below to chat with Siri.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessage(ChatMessage message) {
    final isUser = message.role == MessageRole.user;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 330),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: isUser ? Colors.deepPurple : Colors.white.withOpacity(.08),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          message.text,
          style: const TextStyle(
            fontSize: 16,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildInput() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendText(),
                decoration: InputDecoration(
                  hintText: 'Ask Siri anything...',
                  filled: true,
                  fillColor: Colors.white.withOpacity(.08),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FloatingActionButton(
              heroTag: 'send',
              mini: true,
              onPressed: _sendText,
              child: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// CHAT MESSAGE MODEL
// ============================================================

enum MessageRole { user, assistant }

class ChatMessage {
  final MessageRole role;
  final String text;

  ChatMessage({
    required this.role,
    required this.text,
  });
}

// ============================================================
// DYNAMIC GEMINI API SERVICE WITH AUTO MODEL DETECTION
// ============================================================

class GeminiApiService {
  final String apiKey;
  String? _activeModel;

  GeminiApiService({
    required this.apiKey,
  });

  Future<String> _getWorkingModel() async {
    if (_activeModel != null) return _activeModel!;

    try {
      final listUrl = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey',
      );
      final response = await http.get(listUrl);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List models = data['models'] ?? [];

        final availableModels = models
            .where((m) {
              final methods = List<String>.from(m['supportedGenerationMethods'] ?? []);
              return methods.contains('generateContent');
            })
            .map((m) => (m['name'] as String).replaceAll('models/', ''))
            .toList();

        if (availableModels.isNotEmpty) {
          _activeModel = availableModels.firstWhere(
            (m) => m.contains('flash'),
            orElse: () => availableModels.first,
          );
          return _activeModel!;
        }
      }
    } catch (_) {}

    _activeModel = 'gemini-1.5-flash-latest';
    return _activeModel!;
  }

  Future<String> sendMessage(String prompt) async {
    if (apiKey.isEmpty) {
      throw Exception('Gemini API key missing.');
    }

    final model = await _getWorkingModel();
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
    );

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ]
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
      return text ?? 'No response generated.';
    } else {
      final errorData = jsonDecode(response.body);
      final msg = errorData['error']?['message'] ?? 'API Error';
      throw Exception('($msg)');
    }
  }
}
