import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:kover/riverpod/providers/tts/vieneu/vieneu_synth.dart';
import 'package:onnxruntime_plus/onnxruntime_plus.dart';
import 'package:path/path.dart' as p;
import 'package:sea_g2p/sea_g2p.dart';

/// Runs the VieNeu-TTS v3 Nano model in a background isolate.
///
/// Messages to the worker are maps: `{op: 'synth', id, text, voice, speed,
/// steps, sway, cfg}` and `{op: 'cancel', id}`. The worker answers on the port
/// it was spawned with: its own [SendPort] first, then `{op: 'loaded', ms}` or
/// `{op: 'loadError', message}`, and for each synthesis `{op: 'done', id, wav,
/// stats}`, `{op: 'cancelled', id}` or `{op: 'error', id, message}`.
void vieneuWorkerMain((SendPort, String) args) {
  final (events, directory) = args;
  final commands = ReceivePort();
  events.send(commands.sendPort);
  final worker = _Worker(events, directory);
  commands.listen((message) => worker.handle(message as Map));
  worker.load();
}

class _Job {
  final int id;
  final Map message;
  _Job(this.id, this.message);
}

class _Cancelled implements Exception {}

class _Worker {
  final SendPort _events;
  final String _directory;
  final _queue = Queue<_Job>();
  final _cancelled = <int>{};
  var _running = false;
  Future<void>? _loading;

  late final SeaG2p _g2p;
  late final OrtSession _textEncoder;
  late final OrtSession _durationPredictor;
  late final OrtSession _vectorEstimator;
  late final OrtSession _codecDecoder;
  late final Map<String, int> _vocab;
  late final Map<String, VieneuVoice> _voices;
  late final String _defaultVoice;
  late final Float32List _nullSpeaker;
  late final Float32List _nullStyle;
  late final OrtValueTensor _nullContext;
  late final OrtValueTensor _nullMask;
  late final OrtValueTensor _nullSpeakerTensor;
  late final OrtValueTensor _nullStyleTensor;
  final _options = OrtRunOptions();
  final _random = math.Random();

  _Worker(this._events, this._directory);

  String _path(String name) => p.join(_directory, name);

  void load() => _loading ??= _load();

  Future<void> _load() async {
    final watch = Stopwatch()..start();
    try {
      _g2p = SeaG2p.open(_path('sea_g2p.bin'));
      _vocab = parseVieneuVocab(File(_path('config.json')).readAsStringSync());
      final constants = parseNpz(
        File(_path('constants.npz')).readAsBytesSync(),
      );
      _nullSpeaker = constants['null_spk']!;
      _nullStyle = constants['null_style']!;
      final (defaultVoice, voices) = parseVieneuVoices(
        File(_path('voices_v3_nano.json')).readAsStringSync(),
      );
      _defaultVoice = defaultVoice;
      _voices = {for (final voice in voices) voice.name: voice};

      OrtEnv.instance.init();
      final options = OrtSessionOptions()
        ..setIntraOpNumThreads(4)
        ..setInterOpNumThreads(1)
        ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
      OrtSession open(String name) =>
          OrtSession.fromFile(File(_path(name)), options);
      _textEncoder = open('text_encoder.onnx');
      _durationPredictor = open('duration_predictor.onnx');
      _vectorEstimator = open('vector_estimator.onnx');
      _codecDecoder = open('codec_decoder.onnx');

      // The unconditional context does not depend on the text or the voice.
      final nullIds = [_bos, _eos];
      _nullSpeakerTensor = _floats(_nullSpeaker, [1, 192]);
      _nullStyleTensor = _floats(_nullStyle, [1, 50, 256]);
      final ids = _ints(nullIds);
      _nullContext = _runOne(_textEncoder, {
        'ids': ids,
        'style': _nullStyleTensor,
      });
      ids.release();
      _nullMask = _mask(nullIds.length);
      _events.send({'op': 'loaded', 'ms': watch.elapsedMilliseconds});
    } catch (error) {
      _events.send({'op': 'loadError', 'message': '$error'});
    }
  }

  static const _bos = 1;
  static const _eos = 2;

  void handle(Map message) {
    switch (message['op']) {
      case 'synth':
        _queue.add(_Job(message['id'] as int, message));
        unawaited(_drain());
      case 'cancel':
        final id = message['id'] as int;
        if (_queue.any((job) => job.id == id)) {
          _queue.removeWhere((job) => job.id == id);
          _events.send({'op': 'cancelled', 'id': id});
        } else {
          _cancelled.add(id);
        }
    }
  }

  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty) {
        final job = _queue.removeFirst();
        try {
          await (_loading ??= _load());
          final reply = await _synthesize(job);
          _events.send(reply);
        } on _Cancelled {
          _events.send({'op': 'cancelled', 'id': job.id});
        } catch (error) {
          _events.send({'op': 'error', 'id': job.id, 'message': '$error'});
        }
        _cancelled.remove(job.id);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _checkCancelled(int id) async {
    // Lets a cancel message through.
    await Future<void>.delayed(Duration.zero);
    if (_cancelled.contains(id)) throw _Cancelled();
  }

  Future<Map<String, Object?>> _synthesize(_Job job) async {
    final m = job.message;
    final text = m['text'] as String;
    final voice = _voices[m['voice'] as String?] ?? _voices[_defaultVoice]!;
    final speed = (m['speed'] as num).toDouble();
    final steps = m['steps'] as int;
    final sway = (m['sway'] as num).toDouble();
    final cfg = (m['cfg'] as num).toDouble();

    final total = Stopwatch()..start();
    final watch = Stopwatch()..start();
    var stats = VieneuStats(chars: text.length);

    final normalized = _g2p.normalize(text);
    final chunks = normalized.length > vieneuMaxChunkChars
        ? splitForSynthesis(normalized)
        : [text];
    final phonemes = [
      for (final chunk in chunks)
        if (chunk.trim().isNotEmpty) _g2p.phonemize(chunk),
    ];
    stats += VieneuStats(g2pMs: watch.elapsedMilliseconds);

    final speaker = _floats(voice.speaker, [1, 192]);
    final style = _floats(voice.style, [1, 50, 256]);
    final waves = <Float32List>[];
    try {
      for (final ph in phonemes) {
        await _checkCancelled(job.id);
        final (wave, chunkStats) = await _chunk(
          job.id,
          phonemeIds(ph, _vocab),
          speaker,
          style,
          speed: speed,
          steps: steps,
          sway: sway,
          cfg: cfg,
        );
        waves.add(wave);
        stats += chunkStats;
      }
    } finally {
      speaker.release();
      style.release();
    }

    final joined = waves.isEmpty ? Float32List(0) : joinChunks(waves);
    final wav = wavBytes(joined);
    stats += VieneuStats(
      chunks: phonemes.length,
      audioSeconds: joined.length / vieneuSampleRate,
      totalMs: total.elapsedMilliseconds,
    );
    return {
      'op': 'done',
      'id': job.id,
      'wav': TransferableTypedData.fromList([wav]),
      'stats': stats.toMap(),
    };
  }

  Future<(Float32List, VieneuStats)> _chunk(
    int id,
    List<int> idList,
    OrtValueTensor speaker,
    OrtValueTensor style, {
    required double speed,
    required int steps,
    required double sway,
    required double cfg,
  }) async {
    final watch = Stopwatch()..start();
    final ids = _ints(idList);
    final mask = _mask(idList.length);
    OrtValueTensor? context;
    OrtValueTensor? x;
    OrtValueTensor? time;
    try {
      context = _runOne(_textEncoder, {'ids': ids, 'style': style});
      final textMs = watch.elapsedMilliseconds;

      watch.reset();
      final logSeconds = _runScalar(_durationPredictor, {
        'ctx': context,
        'ctx_mask': mask,
        'spk': speaker,
      });
      final durationMs = watch.elapsedMilliseconds;

      final frames = frameCount(logSeconds, speed);
      final schedule = timeSchedule(steps, sway);
      x = _floats(gaussianNoise(144 * frames, _random), [1, 144, frames]);
      time = OrtValueTensor.createFloats([1]);
      final latent = x.floats;

      watch.reset();
      for (var i = 0; i < schedule.length - 1; i++) {
        await _checkCancelled(id);
        time.floats[0] = schedule[i];
        final velocity = _flow(x, time, context, mask, speaker, style);
        final dt = schedule[i + 1] - schedule[i];
        if (cfg > 0) {
          final unconditional = _flow(
            x,
            time,
            _nullContext,
            _nullMask,
            _nullSpeakerTensor,
            _nullStyleTensor,
          );
          final u = unconditional.floats;
          final v = velocity.floats;
          for (var j = 0; j < latent.length; j++) {
            latent[j] += dt * (u[j] + cfg * (v[j] - u[j]));
          }
          unconditional.release();
        } else {
          final v = velocity.floats;
          for (var j = 0; j < latent.length; j++) {
            latent[j] += dt * v[j];
          }
        }
        velocity.release();
      }
      final flowMs = watch.elapsedMilliseconds;

      watch.reset();
      await _checkCancelled(id);
      final decoded = _runOne(_codecDecoder, {'x': x});
      final samples = decoded.floats;
      final raw = Float32List(samples.length);
      for (var i = 0; i < raw.length; i++) {
        raw[i] = samples[i].clamp(-1.0, 1.0);
      }
      decoded.release();
      final wave = trimAndFade(raw);
      return (
        wave,
        VieneuStats(
          frames: frames,
          textEncoderMs: textMs,
          durationMs: durationMs,
          flowMs: flowMs,
          decoderMs: watch.elapsedMilliseconds,
        ),
      );
    } finally {
      ids.release();
      mask.release();
      context?.release();
      x?.release();
      time?.release();
    }
  }

  /// One run of the vector estimator; the caller releases the velocity.
  OrtValueTensor _flow(
    OrtValueTensor x,
    OrtValueTensor t,
    OrtValue context,
    OrtValue mask,
    OrtValue speaker,
    OrtValue style,
  ) => _runOne(_vectorEstimator, {
    'x': x,
    't': t,
    'ctx': context,
    'ctx_mask': mask,
    'spk': speaker,
    'style': style,
  });

  /// Runs [session], returning its first output; the caller releases it.
  OrtValueTensor _runOne(OrtSession session, Map<String, OrtValue> inputs) {
    final outputs = session.run(_options, inputs, [session.outputNames.first]);
    return outputs.single! as OrtValueTensor;
  }

  double _runScalar(OrtSession session, Map<String, OrtValue> inputs) {
    final output = _runOne(session, inputs);
    final value = output.floats[0];
    output.release();
    return value;
  }

  OrtValueTensor _floats(Float32List data, List<int> shape) =>
      OrtValueTensor.createTensorWithDataList(data, shape);

  OrtValueTensor _ints(List<int> data) =>
      OrtValueTensor.createTensorWithDataList(
        Int64List.fromList(data),
        [1, data.length],
      );

  OrtValueTensor _mask(int length) => OrtValueTensor.createTensorWithDataList(
    List.filled(length, true),
    [1, length],
  );
}
