import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:kover/riverpod/providers/tts/edge_tts_cache.dart';
import 'package:kover/riverpod/providers/tts/edge_tts_protocol.dart' as edge;
import 'package:kover/riverpod/providers/tts/tts_engine.dart';
import 'package:kover/utils/logging.dart';
import 'package:path_provider/path_provider.dart';

/// The text, voice name, language, rate and pitch of an utterance.
typedef _Key = (String, String?, String?, double, double);

/// A [TtsEngine] backed by the online voices of Microsoft Edge.
///
/// Synthesizes utterances into MP3 files, some ahead of time, and plays them
/// one at a time. Only
/// use it where [edgeTtsSupported] is true.
class EdgeTtsEngine implements TtsEngine {
  static const _attemptsPerVoice = 2;
  static const _fallbackVoices = 2;
  static const _retryDelay = Duration(milliseconds: 200);

  // The audio session is handled by the audio handler already.
  final AudioPlayer _player = AudioPlayer(handleInterruptions: false);
  final HttpClient _client = HttpClient()..userAgent = edge.edgeUserAgent;
  var _generation = 0;
  List<TtsVoice>? _voices;
  Future<List<TtsVoice>>? _voicesRequest;
  late final _cache = SynthesisCache<_Key>(capacity: 4, synthesize: _audioFor);
  late final Future<Directory> _tempDirectory = getTemporaryDirectory();
  String? _playingPath;

  /// The voice used instead of a requested one that kept failing.
  final _substitutes = <String, String>{};

  /// The voice chosen in the settings for the last utterance.
  String? _chosenVoice;

  @override
  bool get supportsWordBoundaries => false;

  @override
  Future<List<TtsVoice>> voices() async {
    final response = await http
        .get(
          Uri.parse(edge.voicesUrl(DateTime.timestamp())),
          headers: edge.voicesHeaders(),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw HttpException('voice list failed (${response.statusCode})');
    }
    return _voices = edge.parseVoices(response.body);
  }

  @override
  void prefetch(TtsUtterance utterance) => _cache.obtain(_key(utterance));

  _Key _key(TtsUtterance u) {
    // A newly chosen voice is tried again instead of its stand-ins.
    if (u.voiceName != _chosenVoice) {
      _chosenVoice = u.voiceName;
      _substitutes.clear();
    }
    return (u.text, u.voiceName, u.language, u.rate, u.pitch);
  }

  @override
  Stream<TtsEvent> speak(TtsUtterance utterance) async* {
    final generation = ++_generation;
    try {
      final key = _key(utterance);
      final reused = _cache.contains(key);
      var synthesis = _cache.obtain(key);
      var audio = await synthesis.audio;
      if (generation != _generation) return;
      if (audio == null && reused) {
        // The prefetched request failed, so try again.
        _cache.remove(key, synthesis);
        synthesis = _cache.obtain(key);
        audio = await synthesis.audio;
        if (generation != _generation) return;
      }
      if (audio == null) {
        _cache.remove(key, synthesis);
        yield const TtsError(message: 'no audio received');
        return;
      }

      final directory = await _tempDirectory;
      final file = File('${directory.path}/tts_edge_$generation.mp3');
      await file.writeAsBytes(audio);
      if (generation != _generation) {
        unawaited(_delete(file.path));
        return;
      }

      await _player.setFilePath(file.path);
      if (generation != _generation) return;
      if (_playingPath case final previous?) unawaited(_delete(previous));
      _playingPath = file.path;

      yield const TtsStarted();
      // Completes when the audio ends, or when it is paused or stopped.
      await _player.play();
      if (generation != _generation) return;

      if (_player.processingState == ProcessingState.completed) {
        _cache.remove(key, synthesis);
        // Keeps the player from restarting the audio on a later play.
        await _player.pause();
        yield const TtsDone();
      } else {
        yield const TtsError(message: 'playback stopped');
      }
    } catch (error, stacktrace) {
      if (generation != _generation) return;
      log.error('edge tts failed', error: error, stacktrace: stacktrace);
      yield TtsError(message: '$error');
    }
  }

  static Future<void> _delete(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }

  /// The MP3 of [key], from the requested voice or a fallback.
  Future<Uint8List?> _audioFor(_Key key, Synthesis synthesis) async {
    final (text, voiceName, language, rate, pitch) = key;
    final requested = voiceName ?? await _voiceFor(language);
    if (synthesis.cancelled) return null;

    // The service often closes the connection without sending audio, and some
    // voices fail for a while, so a few attempts are made with each voice.
    final tried = <String>{};
    var budget = 1 + _fallbackVoices;
    Future<Uint8List?> tryVoices(Iterable<String> voices) async {
      for (final voice in voices) {
        if (budget == 0) return null;
        if (!tried.add(voice)) continue;
        budget--;
        final ssml = edge.ssml(voice, text, rate, pitch);
        for (var attempt = 0; attempt < _attemptsPerVoice; attempt++) {
          if (attempt > 0) await Future<void>.delayed(_retryDelay);
          if (synthesis.cancelled) return null;
          Uint8List? audio;
          try {
            audio = await _synthesize(ssml, synthesis);
          } catch (error, stacktrace) {
            // A failed connection is retried like a missing response.
            log.error(
              'edge synthesis failed',
              error: error,
              stacktrace: stacktrace,
            );
          }
          if (synthesis.cancelled) return null;
          if (audio != null) {
            if (voice == requested) {
              _substitutes.remove(requested);
            } else {
              _substitutes[requested] = voice;
            }
            return audio;
          }
        }
      }
      return null;
    }

    // A voice that stood in for the requested one keeps reading, so the voice
    // does not change from one sentence to the next.
    final audio = await tryVoices({?_substitutes[requested], requested});
    if (audio != null || synthesis.cancelled) return audio;
    return tryVoices(await _sameLanguageVoices(requested));
  }

  Future<String> _voiceFor(String? language) async {
    if (language == null) return edge.defaultEdgeVoice;

    try {
      final primary = _primary(language);
      final voices = await _cachedVoices();
      return voices
              .firstWhereOrNull((voice) => _primary(voice.locale) == primary)
              ?.name ??
          edge.defaultEdgeVoice;
    } catch (error, stacktrace) {
      log.error('edge voices failed', error: error, stacktrace: stacktrace);
      return edge.defaultEdgeVoice;
    }
  }

  /// The voice list, fetched once for concurrent requests.
  Future<List<TtsVoice>> _cachedVoices() async =>
      _voices ??
      await (_voicesRequest ??= voices().whenComplete(
        () => _voicesRequest = null,
      ));

  /// The other voices in the language of [voice].
  Future<List<String>> _sameLanguageVoices(String voice) async {
    try {
      final voices = await _cachedVoices();
      final locale = voices.firstWhereOrNull((v) => v.name == voice)?.locale;
      if (locale == null) return const [];
      final primary = _primary(locale);
      return [
        for (final v in voices)
          if (v.name != voice && _primary(v.locale) == primary) v.name,
      ];
    } catch (error, stacktrace) {
      log.error('edge voices failed', error: error, stacktrace: stacktrace);
      return const [];
    }
  }

  static String _primary(String locale) =>
      locale.split(RegExp('[-_]')).first.toLowerCase();

  /// The MP3 of [ssml], or null when the server closed without sending a
  /// complete response.
  Future<Uint8List?> _synthesize(String ssml, Synthesis synthesis) async {
    final socket = await WebSocket.connect(
      edge.socketUrl(DateTime.timestamp()),
      headers: edge.socketHeaders(),
      customClient: _client,
    ).timeout(const Duration(seconds: 10));
    if (synthesis.cancelled) {
      unawaited(socket.close());
      return null;
    }
    synthesis.onCancel = () => unawaited(socket.close());

    try {
      socket
        ..add(edge.configMessage(edge.jsDate(DateTime.timestamp())))
        ..add(
          edge.ssmlMessage(
            edge.randomHex(),
            edge.jsDate(DateTime.timestamp()),
            ssml,
          ),
        );

      final audio = BytesBuilder(copy: false);
      var ended = false;
      await for (final frame in socket.timeout(const Duration(seconds: 30))) {
        if (frame is String) {
          if (edge.textPath(frame) == 'turn.end') {
            ended = true;
            break;
          }
        } else if (frame is List<int>) {
          final data = edge.audioData(Uint8List.fromList(frame));
          if (data != null) audio.add(data);
        }
      }
      return ended && audio.length > 0 ? audio.takeBytes() : null;
    } finally {
      synthesis.onCancel = null;
      unawaited(socket.close());
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    await _player.stop();
  }

  Future<void> dispose() async {
    await stop();
    _cache.clear();
    if (_playingPath case final path?) unawaited(_delete(path));
    await _player.dispose();
    _client.close(force: true);
  }
}
