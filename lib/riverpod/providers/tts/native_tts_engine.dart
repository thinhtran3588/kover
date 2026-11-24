import 'package:collection/collection.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:kover/riverpod/providers/tts/tts_engine.dart';
import 'package:kover/utils/safe_platform.dart';

/// A [TtsEngine] backed by the platform's text-to-speech engine.
///
/// Speaks one utterance per call and completes it when the platform reports
/// the speech as finished.
class NativeTtsEngine implements TtsEngine {
  final FlutterTts _tts = FlutterTts();
  var _configured = false;
  var _generation = 0;
  List<TtsVoice>? _voices;

  @override
  bool get supportsWordBoundaries => false;

  @override
  Future<List<TtsVoice>> voices() async {
    final raw = await _tts.getVoices;
    if (raw is! List) return const [];

    return [
      for (final voice in raw)
        if (voice is Map && voice['name'] != null && voice['locale'] != null)
          TtsVoice(
            name: voice['name'].toString(),
            locale: voice['locale'].toString(),
          ),
    ];
  }

  @override
  Stream<TtsEvent> speak(TtsUtterance utterance) async* {
    final generation = ++_generation;

    if (!_configured) {
      await _tts.awaitSpeakCompletion(true);
      _configured = true;
    }

    if (utterance.voiceName != null && utterance.voiceLocale != null) {
      await _tts.setVoice({
        'name': utterance.voiceName!,
        'locale': utterance.voiceLocale!,
      });
    } else if (utterance.language case final language?) {
      // The default voice follows the device language, not the book's.
      final voice = await _voiceFor(language);
      if (voice != null) {
        await _tts.setVoice({'name': voice.name, 'locale': voice.locale});
      }
    }
    await _tts.setSpeechRate(_platformRate(utterance.rate));
    await _tts.setPitch(utterance.pitch);

    if (generation != _generation) return;
    yield const TtsStarted();

    // `focus` makes Android request audio focus, other platforms ignore it.
    final result = await _tts.speak(utterance.text, focus: true);
    if (generation != _generation) return;

    yield result == 1
        ? const TtsDone()
        : const TtsError(message: 'speech engine failed');
  }

  Future<TtsVoice?> _voiceFor(String language) async {
    final primary = _primary(language);
    _voices ??= await voices();
    return _voices!.firstWhereOrNull(
      (voice) => _primary(voice.locale) == primary,
    );
  }

  static String _primary(String locale) =>
      locale.split(RegExp('[-_]')).first.toLowerCase();

  @override
  Future<void> stop() async {
    _generation++;
    await _tts.stop();
  }

  /// flutter_tts treats 0.5 as the normal speed on Android, iOS, macOS and
  /// Windows, and 1.0 on the web.
  static double _platformRate(double rate) =>
      SafePlatform.isWeb ? rate : (rate * 0.5).clamp(0.0, 1.0);
}
