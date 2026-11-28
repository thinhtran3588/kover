import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:kover/riverpod/providers/tts/edge_tts_cache.dart';
import 'package:kover/riverpod/providers/tts/tts_engine.dart';
import 'package:kover/riverpod/providers/tts/vieneu/vieneu_model.dart';
import 'package:kover/riverpod/providers/tts/vieneu/vieneu_synth.dart';
import 'package:kover/riverpod/providers/tts/vieneu/vieneu_worker_stub.dart'
    if (dart.library.ffi) 'package:kover/riverpod/providers/tts/vieneu/vieneu_worker.dart';
import 'package:kover/utils/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The text, voice name and rate of an utterance.
typedef _Key = (String, String?, double);

/// The result of a synthesis: the WAV audio and its timings.
typedef _Result = (Uint8List, VieneuStats);

/// A [TtsEngine] running the VieNeu-TTS v3 Nano model on the device.
///
/// The model runs in a background isolate and synthesizes whole utterances,
/// which are played one at a time. Only use it where [vieneuTtsSupported] is
/// true and the model is downloaded.
class VieneuTtsEngine implements TtsEngine {
  static const _steps = 8;
  static const _sway = -1.0;
  static const _cfg = 3.0;

  // The audio session is handled by the audio handler already.
  final AudioPlayer _player = AudioPlayer(handleInterruptions: false);
  late final _cache = SynthesisCache<_Key>(capacity: 4, synthesize: _audioFor);
  late final Future<Directory> _tempDirectory = getTemporaryDirectory();
  final _pending = <int, Completer<_Result?>>{};
  var _generation = 0;
  var _nextId = 0;
  String? _playingPath;

  Isolate? _isolate;
  ReceivePort? _events;
  Future<SendPort>? _worker;

  @override
  bool get supportsWordBoundaries => false;

  @override
  Future<List<TtsVoice>> voices() async {
    final directory = await vieneuModelDirectory();
    if (!vieneuFilesComplete(directory)) return const [];
    final json = await File(
      p.join(directory.path, 'voices_v3_nano.json'),
    ).readAsString();
    final (_, voices) = parseVieneuVoices(json);
    return [
      for (final voice in voices) TtsVoice(name: voice.name, locale: 'vi-VN'),
    ];
  }

  _Key _key(TtsUtterance u) => (u.text, u.voiceName, u.rate);

  @override
  void prefetch(TtsUtterance utterance) => _cache.obtain(_key(utterance));

  @override
  Stream<TtsEvent> speak(TtsUtterance utterance) async* {
    final generation = ++_generation;
    try {
      final directory = await vieneuModelDirectory();
      if (!vieneuFilesComplete(directory)) {
        yield const TtsError(message: 'voice model not downloaded');
        return;
      }
      final key = _key(utterance);
      final reused = _cache.contains(key);
      var synthesis = _cache.obtain(key);
      var audio = await synthesis.audio;
      if (generation != _generation) return;
      if (audio == null && reused) {
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

      if (!await _load(audio, generation)) return;

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
      log.error('vieneu tts failed', error: error, stacktrace: stacktrace);
      yield TtsError(message: '$error');
    }
  }

  /// Sets [audio] up in the player, false when [generation] is outdated.
  Future<bool> _load(Uint8List audio, int generation) async {
    final directory = await _tempDirectory;
    final file = File('${directory.path}/tts_vieneu_$generation.wav');
    await file.writeAsBytes(audio);
    if (generation != _generation) {
      unawaited(_delete(file.path));
      return false;
    }
    await _player.setFilePath(file.path);
    if (generation != _generation) return false;
    if (_playingPath case final previous?) unawaited(_delete(previous));
    _playingPath = file.path;
    return true;
  }

  static Future<void> _delete(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }

  Future<Uint8List?> _audioFor(_Key key, Synthesis synthesis) async {
    final (text, voice, rate) = key;
    final result = await _synthesize(
      text,
      voice: voice,
      speed: rate,
      steps: _steps,
      sway: _sway,
      synthesis: synthesis,
    );
    return result?.$1;
  }

  /// Synthesizes [text] in the worker; null when cancelled.
  Future<_Result?> _synthesize(
    String text, {
    String? voice,
    required double speed,
    required int steps,
    required double sway,
    Synthesis? synthesis,
  }) async {
    final worker = await _ensureWorker();
    if (synthesis?.cancelled ?? false) return null;
    final id = _nextId++;
    final completer = _pending[id] = Completer();
    synthesis?.onCancel = () => worker.send({'op': 'cancel', 'id': id});
    worker.send({
      'op': 'synth',
      'id': id,
      'text': text,
      'voice': voice,
      'speed': speed,
      'steps': steps,
      'sway': sway,
      'cfg': _cfg,
    });
    final result = await completer.future;
    synthesis?.onCancel = null;
    if (result != null) {
      log.info(
        'vieneu synth',
        attributes: {...result.$2.toMap(), 'reader': 'tts'},
      );
    }
    return result;
  }

  Future<SendPort> _ensureWorker() => _worker ??= _spawn();

  Future<SendPort> _spawn() async {
    final directory = await vieneuModelDirectory();
    final events = _events = ReceivePort();
    final port = Completer<SendPort>();
    final loaded = Completer<void>();
    events.listen((message) {
      if (message is SendPort) {
        port.complete(message);
      } else if (message is Map) {
        _handle(message, loaded);
      }
    });
    _isolate = await Isolate.spawn(vieneuWorkerMain, (
      events.sendPort,
      directory.path,
    ));
    final sendPort = await port.future;
    // Fails when the model cannot be loaded.
    await loaded.future;
    return sendPort;
  }

  void _handle(Map message, Completer<void> loaded) {
    switch (message['op']) {
      case 'loaded':
        log.info(
          'vieneu model loaded',
          attributes: {'ms': message['ms'], 'reader': 'tts'},
        );
        loaded.complete();
      case 'loadError':
        _worker = null;
        loaded.completeError(StateError(message['message'] as String));
      case 'done':
        final wav = (message['wav'] as TransferableTypedData)
            .materialize()
            .asUint8List();
        _pending.remove(message['id'])?.complete((
          wav,
          VieneuStats.fromMap(message['stats'] as Map),
        ));
      case 'cancelled':
        _pending.remove(message['id'])?.complete(null);
      case 'error':
        _pending
            .remove(message['id'])
            ?.completeError(StateError(message['message'] as String));
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
    _isolate?.kill(priority: Isolate.immediate);
    _events?.close();
    for (final pending in _pending.values) {
      pending.complete(null);
    }
    _pending.clear();
  }
}
