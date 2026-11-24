import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:kover/riverpod/providers/tts/tts_engine.dart';
import 'package:kover/utils/logging.dart';
import 'package:kover/utils/safe_platform.dart';
import 'package:path_provider/path_provider.dart';

/// A [TtsEngine] backed by the platform's text-to-speech engine.
///
/// Speaks one utterance per call and completes it when the platform reports
/// the speech as finished.
class NativeTtsEngine implements TtsEngine {
  final FlutterTts _tts = FlutterTts();
  var _configured = false;
  var _generation = 0;
  List<TtsVoice>? _voices;
  AudioPlayer? _silence;

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

    await _startSilence();

    // `focus` makes Android request audio focus, other platforms ignore it.
    final result = await _tts.speak(utterance.text, focus: true);
    if (generation != _generation) return;

    yield result == 1
        ? const TtsDone()
        : const TtsError(message: 'speech engine failed');
  }

  /// iOS only lists as Now Playing an app that plays audio through a player,
  /// not one that uses the speech synthesizer, so a silent clip loops while
  /// speaking to make the media session controls appear.
  Future<void> _startSilence() async {
    if (!SafePlatform.isIOS) return;
    try {
      var player = _silence;
      if (player == null) {
        // The audio session is handled by the audio handler already.
        player = _silence = AudioPlayer(handleInterruptions: false);
        final directory = await getTemporaryDirectory();
        final file = File('${directory.path}/tts_silence.wav');
        await file.writeAsBytes(_silentWav());
        await player.setFilePath(file.path);
        await player.setLoopMode(LoopMode.one);
      }
      // Completes only once paused.
      if (!player.playing) unawaited(player.play());
    } catch (error, stacktrace) {
      log.error('tts silence failed', error: error, stacktrace: stacktrace);
    }
  }

  /// One second of 8 kHz mono 16-bit PCM silence.
  static Uint8List _silentWav() {
    const dataSize = 16000;
    final bytes = Uint8List(44 + dataSize);
    final header = ByteData.sublistView(bytes);
    bytes.setAll(0, 'RIFF'.codeUnits);
    header.setUint32(4, 36 + dataSize, Endian.little);
    bytes.setAll(8, 'WAVEfmt '.codeUnits);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, 1, Endian.little); // mono
    header.setUint32(24, 8000, Endian.little);
    header.setUint32(28, 16000, Endian.little); // byte rate
    header.setUint16(32, 2, Endian.little); // block align
    header.setUint16(34, 16, Endian.little);
    bytes.setAll(36, 'data'.codeUnits);
    header.setUint32(40, dataSize, Endian.little);
    return bytes;
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
    final silence = _silence;
    if (silence != null && silence.playing) {
      try {
        await silence.pause();
      } catch (error, stacktrace) {
        log.error('tts silence failed', error: error, stacktrace: stacktrace);
      }
    }
  }

  /// flutter_tts treats 0.5 as the normal speed on Android, iOS, macOS and
  /// Windows, and 1.0 on the web.
  static double _platformRate(double rate) =>
      SafePlatform.isWeb ? rate : (rate * 0.5).clamp(0.0, 1.0);
}
