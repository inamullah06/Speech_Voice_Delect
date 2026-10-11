import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:avatar_glow/avatar_glow.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SpeechToTextApp());
}

class SpeechToTextApp extends StatefulWidget {
  const SpeechToTextApp({super.key});

  @override
  State<SpeechToTextApp> createState() => _SpeechToTextAppState();
}

class _SpeechToTextAppState extends State<SpeechToTextApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Real-time Voice to Text',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF6366F1),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        fontFamily: GoogleFonts.inter().fontFamily,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF6366F1),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        fontFamily: GoogleFonts.inter().fontFamily,
      ),
      home: SpeechHomeScreen(
        themeMode: _themeMode,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}

class TranscriptItem {
  final String id;
  final String text;
  final DateTime timestamp;
  final double confidence;

  TranscriptItem({
    required this.id,
    required this.text,
    required this.timestamp,
    required this.confidence,
  });
}

class SpeechHomeScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;

  const SpeechHomeScreen({
    super.key,
    required this.themeMode,
    required this.onToggleTheme,
  });

  @override
  State<SpeechHomeScreen> createState() => _SpeechHomeScreenState();
}

class _SpeechHomeScreenState extends State<SpeechHomeScreen>
    with SingleTickerProviderStateMixin {
  final SpeechToText _speech = SpeechToText();
  
  bool _isInitialized = false;
  bool _isListening = false;
  String _liveText = '';
  double _confidence = 0.0;
  double _soundLevel = 0.0;
  String _statusMessage = 'Tap the microphone to start listening';
  
  List<LocaleName> _locales = [];
  String? _currentLocaleId;
  
  final List<TranscriptItem> _history = [];
  final ScrollController _scrollController = ScrollController();
  
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    
    _initSpeech();
  }

  @override
  void dispose() {
    _animController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Initialize Speech Recognition
  Future<void> _initSpeech() async {
    // Request microphone permission first
    PermissionStatus status = await Permission.microphone.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      setState(() {
        _statusMessage = 'Microphone permission denied. Enable in settings.';
      });
    }

    try {
      bool available = await _speech.initialize(
        onStatus: _onSpeechStatus,
        onError: _onSpeechError,
        debugLogging: true,
      );

      if (available) {
        _locales = await _speech.locales();
        var systemLocale = await _speech.systemLocale();
        _currentLocaleId = systemLocale?.localeId ?? (_locales.isNotEmpty ? _locales.first.localeId : 'en_US');

        setState(() {
          _isInitialized = true;
          _statusMessage = 'Ready. Speak clearly into the mic.';
        });
      } else {
        setState(() {
          _statusMessage = 'Speech recognition unavailable on this device.';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Failed to initialize speech engine: $e';
      });
    }
  }

  void _onSpeechStatus(String status) {
    debugPrint('Speech Status: $status');
    if (mounted) {
      setState(() {
        if (status == 'listening') {
          _isListening = true;
          _statusMessage = 'Listening to your voice...';
        } else if (status == 'notListening' || status == 'done') {
          _isListening = false;
          _statusMessage = 'Tap mic to resume real-time detection';
          _saveLiveTranscriptToHistory();
        }
      });
    }
  }

  void _onSpeechError(SpeechRecognitionError error) {
    debugPrint('Speech Error: ${error.errorMsg}');
    if (mounted) {
      setState(() {
        _isListening = false;
        _statusMessage = 'Error: ${error.errorMsg} (${error.permanent ? "permanent" : "temporary"})';
      });
    }
  }

  /// Start real-time speech recognition
  Future<void> _startListening() async {
    if (!_isInitialized) {
      await _initSpeech();
      if (!_isInitialized) return;
    }

    setState(() {
      _liveText = '';
      _confidence = 0.0;
      _soundLevel = 0.0;
    });

    await _speech.listen(
      onResult: _onSpeechResult,
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        cancelOnError: false,
        partialResults: true,
        localeId: _currentLocaleId,
      ),
      onSoundLevelChange: (level) {
        if (mounted) {
          setState(() {
            _soundLevel = level;
          });
        }
      },
    );
  }

  /// Stop listening
  Future<void> _stopListening() async {
    await _speech.stop();
    setState(() {
      _isListening = false;
      _soundLevel = 0.0;
    });
    _saveLiveTranscriptToHistory();
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (mounted) {
      setState(() {
        _liveText = result.recognizedWords;
        if (result.hasConfidenceRating && result.confidence > 0) {
          _confidence = result.confidence;
        }
      });
      _scrollToBottom();
    }
  }

  void _saveLiveTranscriptToHistory() {
    if (_liveText.trim().isNotEmpty) {
      final newItem = TranscriptItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: _liveText.trim(),
        timestamp: DateTime.now(),
        confidence: _confidence,
      );

      setState(() {
        // Avoid duplicate entries if last entry is identical
        if (_history.isEmpty || _history.first.text != newItem.text) {
          _history.insert(0, newItem);
        }
        _liveText = '';
      });
    }
  }

  void _clearAll() {
    setState(() {
      _liveText = '';
      _history.clear();
      _statusMessage = 'Cleared all transcripts';
    });
  }

  void _copyToClipboard(String text) {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
            SizedBox(width: 8),
            Text('Copied text to clipboard!'),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.graphic_eq_rounded, color: primaryColor),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Voice Transcriber',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
                Text(
                  'Real-Time Speech Detection',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              widget.themeMode == ThemeMode.dark
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
            ),
            onPressed: widget.onToggleTheme,
            tooltip: 'Toggle Theme',
          ),
          if (_history.isNotEmpty || _liveText.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _clearAll,
              tooltip: 'Clear All',
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Status & Language selector bar
            _buildControlHeader(isDark, primaryColor),

            // Live Text & Real-time Sound Waveform View
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Live Real-Time Box
                    _buildLiveTranscriptBox(isDark, primaryColor),

                    const SizedBox(height: 16),

                    // Real-Time Audio Waveform Meter
                    if (_isListening) _buildAudioWaveformMeter(primaryColor),

                    const SizedBox(height: 16),

                    // History Header
                    if (_history.isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(Icons.history_rounded, size: 18, color: primaryColor),
                          const SizedBox(width: 6),
                          Text(
                            'Transcript History (${_history.length})',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.grey[300] : Colors.grey[700],
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () {
                              final fullText = _history.map((e) => e.text).join('\n');
                              _copyToClipboard(fullText);
                            },
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            label: const Text('Copy All', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],

                    // History Items
                    ..._history.map((item) => _buildHistoryCard(item, isDark, primaryColor)),
                  ],
                ),
              ),
            ),

            // Bottom Listening Action Bar
            _buildMicActionBar(isDark, primaryColor),
          ],
        ),
      ),
    );
  }

  /// Header widget with status indicator & Locale Selector
  Widget _buildControlHeader(bool isDark, Color primaryColor) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Pulse dot indicator
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isListening
                  ? Colors.redAccent
                  : (_isInitialized ? const Color(0xFF10B981) : Colors.amber),
              boxShadow: _isListening
                  ? [
                      BoxShadow(
                        color: Colors.redAccent.withValues(alpha: 0.6),
                        blurRadius: 8,
                        spreadRadius: 2,
                      )
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _statusMessage,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.grey[300] : Colors.grey[700],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Locale Selector Dropdown
          if (_locales.isNotEmpty)
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _currentLocaleId,
                icon: const Icon(Icons.language_rounded, size: 18),
                dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
                onChanged: _isListening
                    ? null
                    : (String? newLocale) {
                        if (newLocale != null) {
                          setState(() {
                            _currentLocaleId = newLocale;
                          });
                        }
                      },
                items: _locales.map((LocaleName locale) {
                  return DropdownMenuItem<String>(
                    value: locale.localeId,
                    child: Text(
                      locale.name.length > 18
                          ? '${locale.name.substring(0, 18)}...'
                          : locale.name,
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  /// Live Transcript Output Box
  Widget _buildLiveTranscriptBox(bool isDark, Color primaryColor) {
    final hasText = _liveText.isNotEmpty;

    return Container(
      constraints: const BoxConstraints(minHeight: 160),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isListening
              ? primaryColor.withValues(alpha: 0.5)
              : (isDark ? Colors.grey[800]! : Colors.grey[200]!),
          width: _isListening ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: _isListening
                ? primaryColor.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _isListening
                      ? primaryColor.withValues(alpha: 0.15)
                      : (isDark ? Colors.grey[800] : Colors.grey[200]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isListening ? Icons.mic_rounded : Icons.textsms_outlined,
                      size: 14,
                      color: _isListening ? primaryColor : Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isListening ? 'LIVE RECOGNITION' : 'LIVE PREVIEW',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: _isListening ? primaryColor : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (_confidence > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${(_confidence * 100).toStringAsFixed(0)}% accuracy',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.green,
                    ),
                  ),
                ),
              if (hasText) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () => _copyToClipboard(_liveText),
                  tooltip: 'Copy live text',
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          if (hasText)
            SelectableText(
              _liveText,
              style: TextStyle(
                fontSize: 18,
                height: 1.5,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.grey[900],
              ),
            )
          else
            Text(
              _isListening
                  ? 'Listening... Start speaking into your device mic...'
                  : 'Your spoken words will appear here in real-time as you talk.',
              style: TextStyle(
                fontSize: 15,
                fontStyle: FontStyle.italic,
                color: isDark ? Colors.grey[500] : Colors.grey[400],
              ),
            ),
        ],
      ),
    );
  }

  /// Real-time Animated Audio Waveform Meter
  Widget _buildAudioWaveformMeter(Color primaryColor) {
    // soundLevel usually ranges between -10 and 10 or 0 to 10
    final normalizedLevel = ((_soundLevel + 10) / 20).clamp(0.1, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(15, (index) {
          // Dynamic height based on sound level & animation oscillation
          final multiplier = (index % 3 == 0)
              ? 1.2
              : ((index % 2 == 0) ? 0.8 : 1.0);
          final barHeight = (20.0 + (normalizedLevel * 35.0 * multiplier))
              .clamp(8.0, 45.0);

          return AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: 4,
            height: barHeight,
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.4 + (normalizedLevel * 0.6)),
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }

  /// Transcript History Card
  Widget _buildHistoryCard(TranscriptItem item, bool isDark, Color primaryColor) {
    final formattedTime =
        '${item.timestamp.hour.toString().padLeft(2, '0')}:${item.timestamp.minute.toString().padLeft(2, '0')}';
    final wordCount = item.text.split(' ').where((w) => w.isNotEmpty).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                formattedTime,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: primaryColor,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '• $wordCount words',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 16),
                onPressed: () => _copyToClipboard(item.text),
                tooltip: 'Copy',
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 16),
                onPressed: () {
                  setState(() {
                    _history.removeWhere((h) => h.id == item.id);
                  });
                },
                tooltip: 'Remove',
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            item.text,
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  /// Floating Bottom Mic Control Bar
  Widget _buildMicActionBar(bool isDark, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Clear button
          IconButton.filledTonal(
            onPressed: (_history.isNotEmpty || _liveText.isNotEmpty) ? _clearAll : null,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Clear All',
          ),

          // Main Glowing Microphone Floating Button
          AvatarGlow(
            animate: _isListening,
            glowColor: primaryColor,
            duration: const Duration(milliseconds: 1800),
            repeat: true,
            child: SizedBox(
              width: 72,
              height: 72,
              child: FloatingActionButton(
                onPressed: _isListening ? _stopListening : _startListening,
                elevation: 6,
                backgroundColor: _isListening ? Colors.redAccent : primaryColor,
                shape: const CircleBorder(),
                child: Icon(
                  _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                  size: 34,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          // Copy Live/Latest Text
          IconButton.filledTonal(
            onPressed: (_liveText.isNotEmpty || _history.isNotEmpty)
                ? () {
                    final textToCopy = _liveText.isNotEmpty
                        ? _liveText
                        : (_history.isNotEmpty ? _history.first.text : '');
                    _copyToClipboard(textToCopy);
                  }
                : null,
            icon: const Icon(Icons.content_copy_rounded),
            tooltip: 'Copy Text',
          ),
        ],
      ),
    );
  }
}
