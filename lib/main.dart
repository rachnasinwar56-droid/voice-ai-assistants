import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SiriApp());
}

// ============================================================
// APP
// ============================================================

class SiriApp extends StatelessWidget {
  const SiriApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Siri AI',
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
// MESSAGE MODEL
// ============================================================

enum MessageRole {
  user,
  assistant,
}

class ChatMessage {
  final MessageRole role;
  final String text;

  const ChatMessage({
    required this.role,
    required this.text,
  });
}

// ============================================================
// GEMINI SERVICE
// ============================================================

class GeminiApiService {
  final String apiKey;

  GeminiApiService({
    required this.apiKey,
  });

  static const String model = 'gemini-3.1-flash-lite';

  Future<String> sendMessage(String prompt) async {
    if (apiKey.trim().isEmpty) {
      throw Exception('Gemini API key is missing.');
    }

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/'
      'models/$model:generateContent?key=$apiKey',
    );

    final body = {
      'system_instruction': {
        'parts': [
          {
            'text': '''
You are Siri, a helpful personal AI assistant.

Rules:
- Your name is Siri.
- Understand Hindi, English and Hinglish.
- Reply in the same language as the user.
- Keep normal answers concise.
- Be friendly and conversational.
- If the user asks a technical question, explain clearly.
- Never claim that you performed an action on the phone unless
  the application actually performed that action.
'''
          }
        ]
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {
              'text': prompt,
            }
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.7,
        'maxOutputTokens': 1024,
      },
    };

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      String errorMessage =
          'Gemini API error: HTTP ${response.statusCode}';

      try {
        final data = jsonDecode(response.body);

        final message = data['error']?['message'];

        if (message != null) {
          errorMessage = message.toString();
        }
      } catch (_) {}

      throw Exception(errorMessage);
    }

    final data = jsonDecode(response.body);

    final candidates = data['candidates'];

    if (candidates is! List || candidates.isEmpty) {
      throw Exception('Gemini returned no response.');
    }

    final content = candidates[0]['content'];

    if (content == null) {
      throw Exception('Gemini response content is empty.');
    }

    final parts = content['parts'];

    if (parts is! List || parts.isEmpty) {
      throw Exception('Gemini response parts are empty.');
    }

    final buffer = StringBuffer();

    for (final part in parts) {
      final text = part['text'];

      if (text is String) {
        buffer.write(text);
      }
    }

    final result = buffer.toString().trim();

    if (result.isEmpty) {
      throw Exception('Gemini returned an empty response.');
    }

    return result;
  }
}

// ============================================================
// SIRI HOME
// ============================================================

class SiriHome extends StatefulWidget {
  const SiriHome({super.key});

  @override
  State<SiriHome> createState() => _SiriHomeState();
}

class _SiriHomeState extends State<SiriHome> {
  // ----------------------------------------------------------
  // API KEY
  // ----------------------------------------------------------

  static const String geminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  // ----------------------------------------------------------
  // SERVICES
  // ----------------------------------------------------------

  late final GeminiApiService _gemini;

  final stt.SpeechToText _speech = stt.SpeechToText();

  final FlutterTts _tts = FlutterTts();

  // ----------------------------------------------------------
  // CONTROLLERS
  // ----------------------------------------------------------

  final TextEditingController _textController =
      TextEditingController();

  final ScrollController _scrollController =
      ScrollController();

  // ----------------------------------------------------------
  // STATE
  // ----------------------------------------------------------

  final List<ChatMessage> _messages = [];

  bool _thinking = false;

  bool _speechAvailable = false;

  bool _isListening = false;

  bool _isSpeaking = false;

  String _statusText = 'Ready';

  String _recognizedText = '';

  // ----------------------------------------------------------
  // SIRI IMAGE
  // ----------------------------------------------------------

  static const String siriPhotoUrl =
      'https://upload.wikimedia.org/wikipedia/commons/thumb/d/d3/Siri_logo.svg/512px-Siri_logo.svg.png';

  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {
    super.initState();

    _gemini = GeminiApiService(
      apiKey: geminiApiKey,
    );

    _initializeTts();
    _initializeSpeech();
  }

  // ==========================================================
  // TTS INITIALIZATION
  // ==========================================================

  Future<void> _initializeTts() async {
    try {
      await _tts.setLanguage('en-US');

      await _tts.setSpeechRate(0.48);

      await _tts.setVolume(1.0);

      await _tts.setPitch(1.0);

      await _tts.awaitSpeakCompletion(true);

      _tts.setStartHandler(() {
        if (!mounted) return;

        setState(() {
          _isSpeaking = true;
          _statusText = 'Speaking...';
        });
      });

      _tts.setCompletionHandler(() {
        if (!mounted) return;

        setState(() {
          _isSpeaking = false;
          _statusText = 'Ready';
        });
      });

      _tts.setCancelHandler(() {
        if (!mounted) return;

        setState(() {
          _isSpeaking = false;
          _statusText = 'Ready';
        });
      });

      _tts.setErrorHandler((message) {
        if (!mounted) return;

        setState(() {
          _isSpeaking = false;
          _statusText = 'TTS Error';
        });
      });
    } catch (e) {
      debugPrint('TTS initialization error: $e');
    }
  }

  // ==========================================================
  // SPEECH INITIALIZATION
  // ==========================================================

  Future<void> _initializeSpeech() async {
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          debugPrint('Speech status: $status');

          if (!mounted) return;

          if (status == 'listening') {
            setState(() {
              _isListening = true;
              _statusText = 'Listening...';
            });
          }

          if (status == 'notListening') {
            setState(() {
              _isListening = false;

              if (!_thinking && !_isSpeaking) {
                _statusText = 'Ready';
              }
            });
          }
        },
        onError: (error) {
          debugPrint('Speech error: $error');

          if (!mounted) return;

          setState(() {
            _isListening = false;
            _statusText = 'Voice error';
          });
        },
      );

      if (!mounted) return;

      setState(() {
        _speechAvailable = available;
      });
    } catch (e) {
      debugPrint('Speech initialization error: $e');
    }
  }

  // ==========================================================
  // VOICE INPUT
  // ==========================================================

  Future<void> _startListening() async {
    if (_thinking) return;

    await _stopSpeaking();

    if (!_speechAvailable) {
      await _initializeSpeech();
    }

    if (!_speechAvailable) {
      _showMessage(
        'Voice recognition is not available on this device.',
      );
      return;
    }

    try {
      setState(() {
        _isListening = true;
        _statusText = 'Listening...';
        _recognizedText = '';
      });

      await _speech.listen(
        localeId: 'en_US',
        listenMode: stt.ListenMode.confirmation,
        partialResults: true,
        cancelOnError: true,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        onResult: (result) {
          if (!mounted) return;

          setState(() {
            _recognizedText = result.recognizedWords;

            _textController.text = result.recognizedWords;

            _textController.selection =
                TextSelection.fromPosition(
              TextPosition(
                offset: _textController.text.length,
              ),
            );
          });

          if (result.finalResult) {
            _stopListening();

            final text = result.recognizedWords.trim();

            if (text.isNotEmpty) {
              _sendMessage(text);
            }
          }
        },
      );
    } catch (e) {
      debugPrint('Start listening error: $e');

      if (!mounted) return;

      setState(() {
        _isListening = false;
        _statusText = 'Ready';
      });
    }
  }

  Future<void> _stopListening() async {
    try {
      await _speech.stop();
    } catch (_) {}

    if (!mounted) return;

    setState(() {
      _isListening = false;

      if (!_thinking && !_isSpeaking) {
        _statusText = 'Ready';
      }
    });
  }

  // ==========================================================
  // TTS
  // ==========================================================

  Future<void> _speak(String text) async {
    if (text.trim().isEmpty) return;

    try {
      await _tts.stop();

      // Hindi/Hinglish friendly fallback.
      // Android TTS engine decides the actual voice.
      final hindiAvailable =
          await _tts.isLanguageAvailable('hi-IN');

      if (hindiAvailable == true) {
        await _tts.setLanguage('hi-IN');
      } else {
        await _tts.setLanguage('en-US');
      }

      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS speak error: $e');
    }
  }

  Future<void> _stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {}

    if (!mounted) return;

    setState(() {
      _isSpeaking = false;

      if (!_thinking && !_isListening) {
        _statusText = 'Ready';
      }
    });
  }

  // ==========================================================
  // SEND MESSAGE
  // ==========================================================

  Future<void> _sendMessage(String value) async {
    final text = value.trim();

    if (text.isEmpty) return;

    if (geminiApiKey.isEmpty) {
      _showMessage(
        'GEMINI_API_KEY missing.\n'
        'GitHub Actions Secrets में GEMINI_API_KEY add करो.',
      );
      return;
    }

    await _stopListening();

    setState(() {
      _messages.add(
        ChatMessage(
          role: MessageRole.user,
          text: text,
        ),
      );

      _thinking = true;
      _statusText = 'Thinking...';
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

        _statusText = 'Ready';
      });

      _scrollToBottom();

      // Siri voice reply
      await _speak(reply);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _thinking = false;
        _statusText = 'Error';
      });

      _showMessage(
        e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> _sendText() async {
    await _sendMessage(_textController.text);
  }

  // ==========================================================
  // MICROPHONE PERMISSION
  // ==========================================================

  Future<void> _requestMicrophone() async {
    final status = await Permission.microphone.request();

    if (status.isGranted) {
      await _initializeSpeech();

      _showMessage('Microphone permission granted.');
    } else {
      _showMessage(
        'Microphone permission is required for voice input.',
      );
    }
  }

  // ==========================================================
  // PHONE PERMISSION
  // ==========================================================

  Future<void> _requestPhonePermission() async {
    final status = await Permission.phone.request();

    if (status.isGranted) {
      _showMessage('Phone permission granted.');
    } else {
      _showMessage('Phone permission was not granted.');
    }
  }

  // ==========================================================
  // SMS PERMISSION
  // ==========================================================

  Future<void> _requestSmsPermission() async {
    final status = await Permission.sms.request();

    if (status.isGranted) {
      _showMessage('SMS permission granted.');
    } else {
      _showMessage('SMS permission was not granted.');
    }
  }

  // ==========================================================
  // OVERLAY SETTINGS
  // ==========================================================

  Future<void> _openOverlaySettings() async {
    if (!Platform.isAndroid) return;

    try {
      const intent = AndroidIntent(
        action:
            'android.settings.action.MANAGE_OVERLAY_PERMISSION',
      );

      await intent.launch();
    } catch (e) {
      _showMessage(
        'Unable to open Overlay Settings.',
      );
    }
  }

  // ==========================================================
  // NOTIFICATION SETTINGS
  // ==========================================================

  Future<void> _openNotificationSettings() async {
    if (!Platform.isAndroid) return;

    try {
      const intent = AndroidIntent(
        action:
            'android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS',
      );

      await intent.launch();
    } catch (e) {
      _showMessage(
        'Unable to open Notification Access Settings.',
      );
    }
  }

  // ==========================================================
  // SCROLL
  // ==========================================================

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

  // ==========================================================
  // MESSAGE
  // ==========================================================

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    _speech.stop();
    _tts.stop();

    _textController.dispose();
    _scrollController.dispose();

    super.dispose();
  }

  // ==========================================================
  // BUILD
  // ==========================================================

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
          IconButton(
            tooltip: 'Stop Siri',
            onPressed: _stopSpeaking,
            icon: const Icon(Icons.volume_off),
          ),

          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'mic':
                  await _requestMicrophone();
                  break;

                case 'phone':
                  await _requestPhonePermission();
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
                    Text('Phone Permission'),
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
     
