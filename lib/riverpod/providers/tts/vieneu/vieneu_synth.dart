import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// The pure parts of the VieNeu-TTS v3 Nano pipeline, see its `v3nano.py`.

const vieneuSampleRate = 24000;
const vieneuFlowFps = 15.625;

const _bosId = 1;
const _eosId = 2;
const _maxChunkSeconds = 15.0;
const _minFrames = 2;

/// The longest text synthesized at once, the model was trained on short clips.
const vieneuMaxChunkChars = 140;
const vieneuChunkGapSeconds = 0.30;

const _edgeThresholdDb = -45.0;
const _edgeKeepSeconds = 0.04;
const _edgeFadeSeconds = 0.015;

/// Timings and sizes of a synthesis, in milliseconds unless noted.
class const VieneuStats({
  final int chars = 0,
  final int chunks = 0,
  final int frames = 0,
  final double audioSeconds = 0,
  final int g2pMs = 0,
  final int textEncoderMs = 0,
  final int durationMs = 0,
  final int flowMs = 0,
  final int decoderMs = 0,
  final int totalMs = 0,
}) {
  /// Processing time over audio time, below 1 is faster than real time.
  double get rtf => audioSeconds > 0 ? totalMs / 1000 / audioSeconds : 0;

  VieneuStats operator +(VieneuStats other) => VieneuStats(
    chars: chars + other.chars,
    chunks: chunks + other.chunks,
    frames: frames + other.frames,
    audioSeconds: audioSeconds + other.audioSeconds,
    g2pMs: g2pMs + other.g2pMs,
    textEncoderMs: textEncoderMs + other.textEncoderMs,
    durationMs: durationMs + other.durationMs,
    flowMs: flowMs + other.flowMs,
    decoderMs: decoderMs + other.decoderMs,
    totalMs: totalMs + other.totalMs,
  );

  Map<String, Object> toMap() => {
    'chars': chars,
    'chunks': chunks,
    'frames': frames,
    'audioSeconds': audioSeconds,
    'g2pMs': g2pMs,
    'textEncoderMs': textEncoderMs,
    'durationMs': durationMs,
    'flowMs': flowMs,
    'decoderMs': decoderMs,
    'totalMs': totalMs,
    'rtf': rtf,
  };

  factory VieneuStats.fromMap(Map<Object?, Object?> map) => VieneuStats(
    chars: map['chars']! as int,
    chunks: map['chunks']! as int,
    frames: map['frames']! as int,
    audioSeconds: map['audioSeconds']! as double,
    g2pMs: map['g2pMs']! as int,
    textEncoderMs: map['textEncoderMs']! as int,
    durationMs: map['durationMs']! as int,
    flowMs: map['flowMs']! as int,
    decoderMs: map['decoderMs']! as int,
    totalMs: map['totalMs']! as int,
  );
}

/// A preset voice: a speaker embedding and the style tokens of a reference.
class const VieneuVoice({
  required final String name,
  required final Float32List speaker,
  required final Float32List style,
});

/// The preset voices and the name of the default one, from
/// `voices_v3_nano.json`.
(String, List<VieneuVoice>) parseVieneuVoices(String json) {
  final data = jsonDecode(json) as Map<String, Object?>;
  final presets = data['presets']! as Map<String, Object?>;
  final voices = [
    for (final MapEntry(:key, :value) in presets.entries)
      VieneuVoice(
        name: key,
        speaker: Float32List.fromList([
          for (final x in (value as Map)['speaker_emb'] as List)
            (x as num).toDouble(),
        ]),
        style: Float32List.fromList([
          for (final row in value['style'] as List)
            for (final x in row as List) (x as num).toDouble(),
        ]),
      ),
  ];
  return (data['default_voice'] as String? ?? voices.first.name, voices);
}

/// The vocabulary of `config.json`, mapping phoneme characters to ids.
Map<String, int> parseVieneuVocab(String configJson) {
  final vocab = (jsonDecode(configJson) as Map)['vocab'] as Map;
  return {for (final e in vocab.entries) e.key as String: e.value as int};
}

/// The arrays of an `.npz` archive of version 1 little-endian float32 `.npy`
/// files, as written by `numpy.savez`.
Map<String, Float32List> parseNpz(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  return {
    for (final file in archive.files)
      if (file.isFile && file.name.endsWith('.npy'))
        file.name.substring(0, file.name.length - 4): parseNpy(file.content),
  };
}

Float32List parseNpy(Uint8List bytes) {
  const magic = [0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59]; // \x93NUMPY
  if (bytes.length < 10 || !magic.indexed.every((e) => bytes[e.$1] == e.$2)) {
    throw const FormatException('not an npy file');
  }
  final view = ByteData.sublistView(bytes);
  final version = bytes[6];
  final headerLength = version == 1
      ? view.getUint16(8, Endian.little)
      : view.getUint32(8, Endian.little);
  final start = (version == 1 ? 10 : 12) + headerLength;
  final header = latin1.decode(Uint8List.sublistView(bytes, 0, start));
  if (!header.contains("'<f4'") || header.contains("'fortran_order': True")) {
    throw const FormatException('unsupported npy layout');
  }
  final count = (bytes.length - start) ~/ 4;
  return Float32List.fromList([
    for (var i = 0; i < count; i++)
      view.getFloat32(start + i * 4, Endian.little),
  ]);
}

/// The model input of [phonemes]: begin, one id per known character, end.
/// Characters outside [vocab] are dropped.
List<int> phonemeIds(String phonemes, Map<String, int> vocab) => [
  _bosId,
  for (final rune in phonemes.runes) ?vocab[String.fromCharCode(rune)],
  _eosId,
];

/// Splits [text] into pieces of at most [maxChars], after the last `,;:` that
/// fits or else at the last space.
List<String> splitForSynthesis(
  String text, {
  int maxChars = vieneuMaxChunkChars,
}) {
  final chunks = <String>[];
  var rest = text.trim();
  while (rest.length > maxChars) {
    final window = rest.substring(0, maxChars + 1);
    var cut = _lastIndexOfAny(window, ',;:') + 1;
    if (cut <= 0) cut = window.lastIndexOf(' ');
    if (cut <= 0) cut = maxChars;
    final head = rest.substring(0, cut).trim();
    if (head.isNotEmpty) chunks.add(head);
    rest = rest.substring(cut).trim();
  }
  if (rest.isNotEmpty) chunks.add(rest);
  return chunks;
}

int _lastIndexOfAny(String text, String chars) {
  for (var i = text.length - 1; i >= 0; i--) {
    if (chars.contains(text[i])) return i;
  }
  return -1;
}

/// The number of latent frames of a chunk of [logSeconds] predicted length.
int frameCount(double logSeconds, double speed) {
  final seconds = math.min(
    math.exp(logSeconds) / math.max(speed, 1e-3),
    _maxChunkSeconds,
  );
  return math.max(_minFrames, (seconds * vieneuFlowFps).round());
}

/// The `steps + 1` times of the Euler steps, skewed by [sway].
List<double> timeSchedule(int steps, double sway) {
  final n = math.max(1, steps);
  return [
    for (var i = 0; i <= n; i++)
      () {
        final u = i / n;
        return u + sway * (math.cos(math.pi / 2 * u) - 1 + u);
      }(),
  ];
}

/// [count] samples of the standard normal distribution.
Float32List gaussianNoise(int count, math.Random random) {
  final out = Float32List(count);
  for (var i = 0; i < count; i += 2) {
    final r = math.sqrt(-2 * math.log(1 - random.nextDouble()));
    final angle = 2 * math.pi * random.nextDouble();
    out[i] = r * math.cos(angle);
    if (i + 1 < count) out[i + 1] = r * math.sin(angle);
  }
  return out;
}

/// The samples of silence before and after the sound of [wav], where the mean
/// level of every 10 ms stays below -45 dB.
(int, int) edgeSilence(Float32List wav, {int sampleRate = vieneuSampleRate}) {
  final window = math.max(1, sampleRate ~/ 100);
  final windows = wav.length ~/ window;
  if (windows == 0) return (wav.length, 0);
  final threshold = math.pow(10, _edgeThresholdDb / 20);
  int? first;
  int? last;
  for (var w = 0; w < windows; w++) {
    var sum = 0.0;
    for (var i = w * window; i < (w + 1) * window; i++) {
      sum += wav[i].abs();
    }
    if (sum / window > threshold) {
      first ??= w;
      last = w;
    }
  }
  if (first == null || last == null) return (wav.length, 0);
  return (first * window, wav.length - (last + 1) * window);
}

/// Cuts the silence at both ends of [wav] down to 40 ms and fades the edges.
Float32List trimAndFade(Float32List wav, {int sampleRate = vieneuSampleRate}) {
  if (wav.isEmpty) return wav;
  final (lead, tail) = edgeSilence(wav, sampleRate: sampleRate);
  final keep = (_edgeKeepSeconds * sampleRate).toInt();
  final int start = math.max(0, lead - keep);
  final int end = wav.length - math.max(0, tail - keep);
  final out = wav.sublist(start, end);
  final n = math.min((_edgeFadeSeconds * sampleRate).toInt(), out.length ~/ 2);
  for (var i = 0; i < n; i++) {
    final ramp = 0.5 - 0.5 * math.cos(n > 1 ? math.pi * i / (n - 1) : 0);
    out[i] *= ramp;
    out[out.length - 1 - i] *= ramp;
  }
  return out;
}

/// Joins trimmed chunks, padding with silence so that at least
/// [vieneuChunkGapSeconds] separate the sound of consecutive ones.
Float32List joinChunks(List<Float32List> chunks) {
  if (chunks.length == 1) return chunks.first;
  final parts = <Float32List>[];
  for (var i = 0; i < chunks.length; i++) {
    if (i > 0) {
      final previous = chunks[i - 1];
      final (previousLead, previousTail) = edgeSilence(previous);
      final tail = previousLead == previous.length
          ? previous.length
          : previousTail;
      final (lead, _) = edgeSilence(chunks[i]);
      final pad =
          (vieneuChunkGapSeconds * vieneuSampleRate).toInt() - tail - lead;
      if (pad > 0) parts.add(Float32List(pad));
    }
    parts.add(chunks[i]);
  }
  final out = Float32List(parts.fold(0, (sum, p) => sum + p.length));
  var offset = 0;
  for (final part in parts) {
    out.setRange(offset, offset + part.length, part);
    offset += part.length;
  }
  return out;
}

/// A mono 16-bit PCM WAV file of [samples] in the range -1 to 1.
Uint8List wavBytes(Float32List samples, {int sampleRate = vieneuSampleRate}) {
  final dataLength = samples.length * 2;
  final out = ByteData(44 + dataLength);
  void tag(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      out.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  out.setUint32(4, 36 + dataLength, Endian.little);
  tag(8, 'WAVEfmt ');
  out.setUint32(16, 16, Endian.little);
  out.setUint16(20, 1, Endian.little); // PCM
  out.setUint16(22, 1, Endian.little); // mono
  out.setUint32(24, sampleRate, Endian.little);
  out.setUint32(28, sampleRate * 2, Endian.little);
  out.setUint16(32, 2, Endian.little);
  out.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  out.setUint32(40, dataLength, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    out.setInt16(
      44 + i * 2,
      (samples[i].clamp(-1.0, 1.0) * 32767).round(),
      Endian.little,
    );
  }
  return out.buffer.asUint8List();
}
