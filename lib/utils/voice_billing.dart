import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'logger.dart';
import 'voice_parser.dart';

/// The phone's speech service (Google), used by the cart's mic button.
/// It only hears; [VoiceParser] (voice_parser.dart) turns the words into
/// bill lines, and the cart asks before adding them.
///
/// One tap of the mic is one order: the phone stops after each pause, so
/// listening restarts by itself and every piece is kept ([VoiceTranscript]).
/// The order ends when the mic is tapped again, or after a stretch with
/// nothing said.
class VoiceBilling {
  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;

  // the current order
  bool _active = false;
  bool _stopping = false;
  bool _cycleOpen = false;
  bool _heardThisCycle = false;
  bool _useTamil = false;
  DateTime _started = DateTime.now();
  VoiceTranscript _transcript = VoiceTranscript();
  void Function(String text)? _onText;
  void Function(String text, List<List<String>> guesses)? _onEnd;

  Future<bool> initialize() async {
    if (_initialized) return true;
    _initialized = await _speech.initialize(
      onError: (error) {
        Logger.info('VoiceBilling error: ${error.errorMsg}');
        _cycleEnded();
      },
      onStatus: (status) {
        Logger.info('VoiceBilling status: $status');
        if (status == SpeechToText.doneStatus) _cycleEnded();
      },
    );
    return _initialized;
  }

  bool get isActive => _active;

  /// Whether the phone can hear Tamil. Google voice typing needs the Tamil
  /// language added; without it the phone hears Tamil as English, or nothing.
  Future<bool> hasTamil() async {
    if (!await initialize()) return false;
    try {
      final locales = await _speech.locales();
      return locales.any((l) => l.localeId.toLowerCase().startsWith('ta'));
    } catch (e) {
      Logger.error('VoiceBilling.hasTamil', e);
      return true; // could not tell: let it try
    }
  }

  /// Starts an order. [onText] gets everything heard so far (to show while
  /// speaking); [onEnd] gets the whole order once, when listening ends.
  Future<bool> startOrder({
    required bool useTamil,
    required void Function(String text) onText,
    required void Function(String text, List<List<String>> guesses) onEnd,
  }) async {
    if (!await initialize()) return false;
    _active = true;
    _stopping = false;
    _useTamil = useTamil;
    _started = DateTime.now();
    _transcript = VoiceTranscript();
    _onText = onText;
    _onEnd = onEnd;
    await _listenCycle();
    return true;
  }

  Future<void> _listenCycle() async {
    _cycleOpen = true;
    _heardThisCycle = false;
    await _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        final words = result.recognizedWords;
        if (words.trim().isNotEmpty) _heardThisCycle = true;
        if (result.finalResult) {
          Logger.info('Voice (${_useTamil ? "ta" : "en"}) piece: "$words"');
          // the phone's other guesses (up to 10) help find the product
          _transcript.finalResult(
            words,
            alternates: [for (final a in result.alternates.skip(1)) a.recognizedWords],
          );
        } else {
          _transcript.partial(words);
        }
        _onText?.call(_transcript.text);
      },
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 4),
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        cancelOnError: true,
        partialResults: true,
        localeId: _useTamil ? 'ta_IN' : 'en_IN',
      ),
    );
  }

  /// One stretch of listening ended (pause, error or stop): listen again
  /// if something was said, otherwise the order is complete.
  void _cycleEnded() {
    if (!_active || !_cycleOpen) return;
    _cycleOpen = false;
    final tooLong = DateTime.now().difference(_started) > const Duration(minutes: 3);
    if (_stopping || !_heardThisCycle || tooLong) {
      _finishOrder();
      return;
    }
    // the phone needs a moment before it can listen again
    Future.delayed(const Duration(milliseconds: 250), () {
      if (_active && !_stopping) {
        _listenCycle().catchError((Object e) {
          Logger.error('VoiceBilling.restart', e);
          _finishOrder();
        });
      } else if (_active) {
        _finishOrder();
      }
    });
  }

  void _finishOrder() {
    if (!_active) return;
    _active = false;
    _transcript.flush();
    final text = _transcript.text;
    Logger.info('Voice order: "$text"');
    final end = _onEnd;
    _onEnd = null;
    _onText = null;
    end?.call(text, _transcript.guesses);
  }

  /// The mic tapped again: keep what was said and end the order.
  Future<void> stop() async {
    if (!_active) return;
    _stopping = true;
    await _speech.stop();
    // the phone normally reports "done"; do not wait for it forever
    Future.delayed(const Duration(milliseconds: 1500), _finishOrder);
  }

  void dispose() {
    _active = false;
    _onEnd = null;
    _onText = null;
    _speech.cancel();
  }
}

/// Remembers which product the shop picked for spoken words ("மேரி" → the
/// ₹10 Marie Light), so the same words find it first next time. Kept on
/// this phone only.
class VoiceMemory {
  static const _key = 'voice_learned_v1';
  static const _max = 400;

  static Future<Map<String, String>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return {};
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (e) {
      Logger.error('VoiceMemory.load', e);
      return {};
    }
  }

  static Future<void> remember(Map<String, String> picks) async {
    if (picks.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final all = await load();
      for (final e in picks.entries) {
        all.remove(e.key); // newest last
        all[e.key] = e.value;
      }
      while (all.length > _max) {
        all.remove(all.keys.first);
      }
      await prefs.setString(_key, jsonEncode(all));
    } catch (e) {
      Logger.error('VoiceMemory.remember', e);
    }
  }
}

/// Words the phone keeps mis-hearing, taught by the shop: what it hears →
/// what was meant ("குரு" → "bru"). Filled when a heard text is corrected
/// with "Remember" ticked, or by hand. Kept on this phone only.
class VoiceWords {
  static const _key = 'voice_words_v1';

  static Future<Map<String, String>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return {};
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (e) {
      Logger.error('VoiceWords.load', e);
      return {};
    }
  }

  static Future<void> save(Map<String, String> words) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(words));
    } catch (e) {
      Logger.error('VoiceWords.save', e);
    }
  }

  static Future<void> add(Map<String, String> words) async {
    if (words.isEmpty) return;
    final all = await load();
    for (final e in words.entries) {
      final heard = e.key.trim().toLowerCase();
      final meant = e.value.trim();
      if (heard.isEmpty || meant.isEmpty || heard == meant.toLowerCase()) continue;
      all[heard] = meant;
    }
    await save(all);
  }
}
