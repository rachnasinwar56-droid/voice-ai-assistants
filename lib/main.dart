import 'dart:convert';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SiriApp());
}

// ============================================================
// SIRI APP
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
// HOME
// ============================================================

class SiriHome extends StatefulWidget {
  const SiriHome({super.key});

  @override
  State<SiriHome> createState() => _SiriHomeState();
}

class _SiriHomeState extends State<SiriHome> {
  // ----------------------------------------------------------
  // SERVICES
  // ----------------------------------------------------------

  late final GeminiApiService _gemini;

  final SpeechToText _speech = SpeechToText();

  final FlutterTts _tts = FlutterTts();

  // ----------------------------------------------------------
  // CONTROLLERS
  // ----------------------------------------------------------

  final TextEditingController _textController =
      TextEditingController();

  final ScrollController _scrollController =
      ScrollController();

  // ----------------------------------------------------------
  // STATES
  // ----------------------------------------------------------

  bool _thinking = false;

  bool _isListening = false;

  bool _speechAvailable = false;

  bool _isSpeaking = false;

  // ----------------------------------------------------------
  // CHAT
  // ----------------------------------------------------------

  final List<ChatMessage> _messages = [];

  // ----------------------------------------------------------
  // SIRI PHOTO
  // ----------------------------------------------------------

  static const String siriPhotoUrl =
      'https://upload.wikimedia.org/wikipedia/commons/thumb/d/d3/Siri_logo.svg/512px-Siri_logo.svg.png';

  // ----------------------------------------------------------
  // GEMINI API KEY
  //
  // GitHub Actions:
  //
  // flutter build apk --release \
  // --dart-define=GEMINI_API_KEY=${{ secrets.GEMINI_API_KEY }}
  // ----------------------------------------------------------

  static const String geminiApiKey =
      String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  // ----------------------------------------------------------
  // INIT
  // ----------------------------------------------------------

  @override
  void initState() {
    super.initState();

    _gemini = GeminiApiService(
      apiKey: geminiApiKey,
    );

    _initializeSpeech();

    _initializeTts();
  }

  // ==========================================================
  // INITIALIZE SPEECH
  // ==========================================================

  Future<void> _initializeSpeech() async {
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;

          if (status == 'done' ||
              status == 'notListening') {
            setState(() {
              _isListening = false;
            });
          }
        },
        onError: (error) {
          if (!mounted) return;

          setState(() {
            _isListening = false;
          });

          _showMessage(
            'Speech error: ${error.errorMsg}',
          );
        },
      );

      if (!mounted) return;

      setState(() {
        _speechAvailable = available;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _speechAvailable = false;
      });

      _showMessage(
        'Speech recognition unavailable.',
      );
    }
  }

  // ==========================================================
  // INITIALIZE TTS
  // ==========================================================

  Future<void> _initializeTts() async {
    try {
      await _tts.setSpeechRate(0.48);

      await _tts.setVolume(1.0);

      await _tts.setPitch(1.0);

      _tts.setStartHandler(() {
        if (!mounted) return;

        setState(() {
          _isSpeaking = true;
        });
      });

      _tts.setCompletionHandler(() {
        if (!mounted) return;

        setState(() {
          _isSpeaking = false;
        });
      });

      _tts.setCancelHandler(() {
        if (!mounted) return;

        setState(() {
          _isSpeaking = false;
        });
      });

      _tts.setErrorHandler((message) {
        if (!mounted) return;

        setState(() {
          _isSpeaking = false;
        });
      });
    } catch (_) {
      // TTS is optional.
    }
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    _textController.dispose();

    _scrollController.dispose();

    _speech.stop();

    _tts.stop();

    super.dispose();
  }

  // ==========================================================
  // SNACKBAR
  // ==========================================================

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

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
  // SEND TEXT
  // ==========================================================

  Future<void> _sendText() async {
    final text = _textController.text.trim();

    if (text.isEmpty) return;

    await _sendToGemini(text);
  }

  // ==========================================================
  // SEND TO GEMINI
  // ==========================================================

  Future<void> _sendToGemini(String text) async {
    if (geminiApiKey.trim().isEmpty) {
      _showMessage(
        'GEMINI_API_KEY missing.\n'
        'GitHub Actions Secrets में GEMINI_API_KEY add करें.',
      );
      return;
    }

    if (_isListening) {
      await _stopListening();
    }

    await _tts.stop();

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

      // Speak Gemini reply
      await _speak(reply);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _thinking = false;
      });

      _showMessage(
        'Gemini Error: $e',
      );
    }
  }

  // ==========================================================
  // START LISTENING
  // ==========================================================

  Future<void> _startListening() async {
    if (!_speechAvailable) {
      await _initializeSpeech();
    }

    if (!_speechAvailable) {
      _showMessage(
        'Speech recognition is not available on this phone.',
      );
      return;
    }

    final permission =
        await Permission.microphone.request();

    if (!permission.isGranted) {
      _showMessage(
        'Microphone permission required.',
      );
      return;
    }

    await _tts.stop();

    try {
      setState(() {
        _isListening = true;
      });

      await _speech.listen(
        onResult: (result) {
          final recognizedText =
              result.recognizedWords.trim();

          if (recognizedText.isEmpty) return;

          if (!mounted) return;

          setState(() {
            _textController.text = recognizedText;

            _textController.selection =
                TextSelection.fromPosition(
              TextPosition(
                offset:
                    _textController.text.length,
              ),
            );
          });

          // When speech recognition is final,
          // automatically send it to Gemini.
          if (result.finalResult) {
            _stopListening();

            _sendToGemini(recognizedText);
          }
        },
        partialResults: true,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isListening = false;
      });

      _showMessage(
        'Could not start microphone: $e',
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
    });
  }

  // ==========================================================
  // MICROPHONE BUTTON
  // ==========================================================

  Future<void> _toggleMicrophone() async {
    if (_isListening) {
      await _stopListening();
    } else {
      await _startListening();
    }
  }

  // ==========================================================
  // SPEAK
  // ==========================================================

  Future<void> _speak(String text) async {
    if (text.trim().isEmpty) return;

    try {
      await _tts.stop();

      // Detect Hindi Devanagari text.
      final containsHindi =
          RegExp(r'[\u0900-\u097F]')
              .hasMatch(text);

      if (containsHindi) {
        // Indian Hindi voice.
        await _tts.setLanguage('hi-IN');
      } else {
        // Indian English voice.
        await _tts.setLanguage('en-IN');
      }

      await _tts.speak(text);
    } catch (e) {
      // Do not break chat if TTS fails.
    }
  }

  // ==========================================================
  // STOP SPEAKING
  // ==========================================================

  Future<void> _stopSpeaking() async {
    try {
      await _tts.stop();

      if (!mounted) return;

      setState(() {
        _isSpeaking = false;
      });
    } catch (_) {}
  }

  // ==========================================================
  // REQUEST MICROPHONE
  // ==========================================================

  Future<void> _requestMicrophone() async {
    final status =
        await Permission.microphone.request();

    if (!status.isGranted) {
      _showMessage(
        'Microphone permission required.',
      );
    } else {
      _showMessage(
        'Microphone permission granted.',
      );

      if (!_speechAvailable) {
        await _initializeSpeech();
      }
    }
  }

  // ==========================================================
  // PHONE PERMISSION
  // ==========================================================

  Future<void> _requestCallPermission() async {
    final status =
        await Permission.phone.request();

    if (!status.isGranted) {
      _showMessage(
        'Phone permission was not granted.',
      );
    } else {
      _showMessage(
        'Phone permission granted.',
      );
    }
  }

  // ==========================================================
  // SMS PERMISSION
  // ==========================================================

  Future<void> _requestSmsPermission() async {
    final status =
        await Permission.sms.request();

    if (!status.isGranted) {
      _showMessage(
        'SMS permission was not granted.',
      );
    } else {
      _showMessage(
        'SMS permission granted.',
      );
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
    } catch (_) {
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
    } catch (_) {
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
          // Speaker button
          IconButton(
            tooltip: _isSpeaking
                ? 'Stop speaking'
                : 'Voice status',
            onPressed:
                _isSpeaking ? _stopSpeaking : null,
            icon: Icon(
              _isSpeaking
                  ? Icons.volume_up
                  : Icons.volume_off,
            ),
          ),

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
                    controller:
                        _scrollController,

                    padding:
                        const EdgeInsets.all(16),

                    itemCount:
                        _messages.length,

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

          if (_isListening)
            Container(
              margin: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 6,
              ),
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(.12),
                borderRadius:
                    BorderRadius.circular(18),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.mic,
                    color: Colors.red,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Siri is listening...',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

          _buildInput(),
        ],
  
