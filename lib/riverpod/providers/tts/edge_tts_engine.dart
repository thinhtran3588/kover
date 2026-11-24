import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:kover/riverpod/providers/tts/edge_tts_protocol.dart' as edge;
import 'package:kover/riverpod/providers/tts/tts_engine.dart';
import 'package:kover/utils/logging.dart';
import 'package:path_provider/path_provider.dart';

/// A [TtsEngine] backed by the online voices of Microsoft Edge.
///
/// Synthesizes one utterance at a time into an MP3 file and plays it. Only
/// use it where [edgeTtsSupported] is true.
class EdgeTtsEngine implements TtsEngine {
  static const _attemptsPerVoice = 2;
  static const _fallbackVoices = 2;
  static const _retryDelay = Duration(milliseconds: 200);

  // The audio session is handled by the audio handler already.
  final AudioPlayer _player = AudioPlayer(handleInterruptions: false);
  final HttpClient _client = HttpClient()..userAgent = edge.edgeUserAgent;
  WebSocket? _socket;
  var _generation = 0;
  List<TtsVoice>? _voices;

  /// The voice used instead of a requested one that kept failing.
  final _substitutes = <String, String>{};

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
  Stream<TtsEvent> speak(TtsUtterance utterance) async* {
    final generation = ++_generation;
    try {
      final requested =
          utterance.voiceName ?? await _voiceFor(utterance.language);
      if (generation != _generation) return;
      final candidates = {
        _substitutes[requested] ?? requested,
        ...await _sameLanguageVoices(requested),
      }.take(1 + _fallbackVoices);
      if (generation != _generation) return;

      // The service often closes the connection without sending audio, and
      // some voices fail for a while, so a few attempts are made with each
      // voice of the same language.
      Uint8List? audio;
      for (final voice in candidates) {
        final ssml = edge.ssml(
          voice,
          utterance.text,
          utterance.rate,
          utterance.pitch,
        );
        for (var attempt = 0; attempt < _attemptsPerVoice; attempt++) {
          if (attempt > 0) await Future<void>.delayed(_retryDelay);
          if (generation != _generation) return;
          audio = await _synthesize(ssml, generation);
          if (generation != _generation) return;
          if (audio != null) break;
        }
        if (audio != null) {
          if (voice == requested) {
            _substitutes.remove(requested);
          } else {
            _substitutes[requested] = voice;
          }
          break;
        }
      }
      if (audio == null) {
        yield const TtsError(message: 'no audio received');
        return;
      }

      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/tts_edge_${generation % 2}.mp3');
      await file.writeAsBytes(audio, flush: true);
      if (generation != _generation) return;

      await _player.setFilePath(file.path);
      if (generation != _generation) return;

      yield const TtsStarted();
      // Completes when the audio ends, or when it is paused or stopped.
      await _player.play();
      if (generation != _generation) return;

      if (_player.processingState == ProcessingState.completed) {
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

  Future<String> _voiceFor(String? language) async {
    if (language == null) return edge.defaultEdgeVoice;

    try {
      final primary = _primary(language);
      final voices = _voices ?? await this.voices();
      return voices
              .firstWhereOrNull((voice) => _primary(voice.locale) == primary)
              ?.name ??
          edge.defaultEdgeVoice;
    } catch (error, stacktrace) {
      log.error('edge voices failed', error: error, stacktrace: stacktrace);
      return edge.defaultEdgeVoice;
    }
  }

  /// The other voices in the language of [voice].
  Future<List<String>> _sameLanguageVoices(String voice) async {
    try {
      final voices = _voices ?? await this.voices();
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
  Future<Uint8List?> _synthesize(String ssml, int generation) async {
    final socket = await WebSocket.connect(
      edge.socketUrl(DateTime.timestamp()),
      headers: edge.socketHeaders(),
      customClient: _client,
    ).timeout(const Duration(seconds: 10));
    if (generation != _generation) {
      unawaited(socket.close());
      return null;
    }
    _socket = socket;

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
      if (identical(_socket, socket)) _socket = null;
      unawaited(socket.close());
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    unawaited(_socket?.close());
    await _player.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _player.dispose();
    _client.close(force: true);
  }
}
