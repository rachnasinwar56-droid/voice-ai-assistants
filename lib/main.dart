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
// HOME
// ============================================================

class SiriHome extends StatefulWidget {
  const SiriHome({super.key});

  @override
  State<SiriHome> createState() => _SiriHomeState();
}

class _SiriHomeState extends State<SiriHome> {
  late final GeminiApiService _gemini;

  final TextEditingController _textController =
      TextEditingController();

  final ScrollController _scrollController =
      ScrollController();

  final FlutterTts _tts = FlutterTts();

  final stt.SpeechToText _speech =
      stt.SpeechToText();

  bool _thinking = false;
  bool _isListening = false;
  bool _speechAvailable = false;
  bool _ttsEnabled = true;

  String _status = 'Ready';

  final List<ChatMessage> _messages = [];

  // ==========================================================
  // GEMINI API KEY
  // ==========================================================

  static const String geminiApiKey =
      String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  // ==========================================================
  // SIRI IMAGE
  // ==========================================================

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
      await _tts.setSpeechVolume(1.0);
      await _tts.setPitch(1.0);

      await _tts.awaitSpeakCompletion(true);

      if (Platform.isAndroid) {
        try {
          await _tts.setQueueMode(1);
        } catch (_) {}
      }
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

          if (status == 'notListening') {
            setState(() {
              _isListening = false;

              if (!_thinking) {
                _status = 'Ready';
              }
            });
          }
        },
        onError: (error) {
          debugPrint('Speech error: $error');

          if (!mounted) return;

          setState(() {
            _isListening = false;
            _status = 'Voice error';
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
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();

    _tts.stop();
    _speech.stop();

    super.dispose();
  }

  // ==========================================================
  // SNACKBAR
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
  // MICROPHONE PERMISSION
  // ==========================================================

  Future<bool> _requestMicrophonePermission() async {
    final status =
        await Permission.microphone.request();

    if (!status.isGranted) {
      _showMessage(
        'Microphone permission is required.',
      );

      return false;
    }

    return true;
  }

  // ==========================================================
  // START VOICE INPUT
  // ==========================================================

  Future<void> _startListening() async {
    final permission =
        await _requestMicrophonePermission();

    if (!permission) return;

    if (!_speechAvailable) {
      await _initializeSpeech();
    }

    if (!_speechAvailable) {
      _showMessage(
        'Speech recognition is not available on this device.',
      );
      return;
    }

    if (_isListening) {
      await _stopListening();
      return;
    }

    try {
      await _tts.stop();

      setState(() {
        _isListening = true;
        _status = 'Listening...';
      });

      await _speech.listen(
        onResult: (result) {
          if (!mounted) return;

          setState(() {
            _textController.text =
                result.recognizedWords;

            _textController.selection =
                TextSelection.fromPosition(
              TextPosition(
                offset:
                    _textController.text.length,
              ),
            );
          });

          if (result.finalResult) {
            _stopListening();

            final text =
                result.recognizedWords.trim();

            if (text.isNotEmpty) {
              _sendText(text);
            }
          }
        },
        listenFor: const Duration(
          seconds: 30,
        ),
        pauseFor: const Duration(
          seconds: 4,
        ),
        partialResults: true,
        listenMode: stt.ListenMode.confirmation,
        cancelOnError: true,
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isListening = false;
        _status = 'Ready';
      });

      _showMessage(
        'Voice input error: $e',
      );
    }
  }

  // ==========================================================
  // STOP LISTENING
  // ==========================================================

  Future<void> _stopListening() async {
    try {
      await _speech.stop();
    } catch (_) {}

    if (!mounted) return;

    setState(() {
      _isListening = false;

      if (!_thinking) {
        _status = 'Ready';
      }
    });
  }

  // ==========================================================
  // SEND TEXT
  // ==========================================================

  Future<void> _sendText(
    [String? providedText]
  ) async {
    final text =
        (providedText ?? _textController.text).trim();

    if (text.isEmpty) return;

    if (geminiApiKey.isEmpty) {
      _showMessage(
        'GEMINI_API_KEY missing.',
      );
      return;
    }

    await _tts.stop();

    if (_isListening) {
      await _stopListening();
    }

    setState(() {
      _messages.add(
        ChatMessage(
          role: MessageRole.user,
          text: text,
        ),
      );

      _thinking = true;
      _status = 'Thinking...';
    });

    _textController.clear();

    _scrollToBottom();

    try {
      final reply =
          await _gemini.sendMessage(text);

      if (!mounted) return;

      setState(() {
        _thinking = false;

        _messages.add(
          ChatMessage(
            role: MessageRole.assistant,
            text: reply,
          ),
        );

        _status = 'Ready';
      });

      _scrollToBottom();

      // Siri बोलेगी
      if (_ttsEnabled) {
        await _speak(reply);
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _thinking = false;
        _status = 'Error';
      });

      _showMessage(
        'Gemini Error: $e',
      );
    }
  }

  // ==========================================================
  // TTS SPEAK
  // ==========================================================

  Future<void> _speak(String text) async {
    if (text.trim().isEmpty) return;

    try {
      await _tts.stop();

      // Hindi / Hinglish के लिए Hindi voice try करें
      try {
        await _tts.setLanguage('hi-IN');
      } catch (_) {
        await _tts.setLanguage('en-US');
      }

      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS error: $e');
    }
  }

  // ==========================================================
  // TTS STOP
  // ==========================================================

  Future<void> _stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  // ==========================================================
  // OPEN OVERLAY SETTINGS
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
        'Unable to open Notification Settings.',
      );
    }
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
            icon: const Icon(
              Icons.volume_off,
            ),
          ),

          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'mic':
                  await _requestMicrophonePermission();
                  break;

                case 'tts':
                  setState(() {
                    _ttsEnabled = !_ttsEnabled;
                  });

                  _showMessage(
                    _ttsEnabled
                        ? 'Siri voice enabled'
                        : 'Siri voice disabled',
                  );

                  break;

                case 'overlay':
                  await _openOverlaySettings();
                  break;

                case 'notifications':
                  await _openNotificationSettings();
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'mic',
                child: Row(
                  children: [
                    Icon(Icons.mic),
                    SizedBox(width: 10),
                    Text(
                      'Microphone Permission',
                    ),
                  ],
                ),
              ),

              PopupMenuItem(
                value: 'tts',
                child: Row(
                  children: [
                    const Icon(Icons.record_voice_over),
                    const SizedBox(width: 10),
                    Text(
                      _ttsEnabled
                          ? 'Disable Siri Voice'
                          : 'Enable Siri Voice',
                    ),
                  ],
                ),
              ),

              const PopupMenuItem(
                value: 'overlay',
                child: Row(
                  children: [
                    Icon(Icons.layers),
                    SizedBox(width: 10),
                    Text('Overlay Settings'),
                  ],
                ),
              ),

              const PopupMenuItem(
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
                      return _buildMessage(
                        _messages[index],
                      );
                    },
                  ),
          ),

          if (_thinking)
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 8,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Siri is thinking...',
                  ),
                ],
              ),
            ),

          _buildInput(),
        ],
      ),
    );
  }

  // ==========================================================
  // STATUS
  // ==========================================================

  Widget _buildStatus() {
    final hasKey =
        geminiApiKey.isNotEmpty;

    final color = hasKey
        ? Colors.green
        : Colors.red;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius:
            BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Text(
              hasKey
                  ? _status
                  : 'API Key Missing',
            ),
          ),

          if (_isListening)
            const Icon(
              Icons.mic,
              color: Colors.redAccent,
              size: 20,
            ),
        ],
      ),
    );
  }

  // ==========================================================
  // EMPTY STATE
  // ==========================================================

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color:
                        Colors.deepPurple.withOpacity(.35),
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
              'Your AI Voice Assistant',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                color: Colors.white70,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Tap the microphone and talk to Siri.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white54,
              ),
            ),

            const SizedBox(height: 25),

            FloatingActionButton.large(
              heroTag: 'emptyMic',
              onPressed: _startListening,
              child: Icon(
                _isListening
                    ? Icons.stop
                    : Icons.mic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
