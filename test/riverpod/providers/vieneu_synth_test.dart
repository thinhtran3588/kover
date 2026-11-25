import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kover/riverpod/providers/tts/vieneu/vieneu_synth.dart';

Uint8List _npy(List<double> values, String shape) {
  final header = "{'descr': '<f4', 'fortran_order': False, 'shape': $shape, }";
  final padded = '${header.padRight(118 - 1)}\n';
  final out = BytesBuilder()
    ..add([0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59, 1, 0])
    ..add([padded.length, 0])
    ..add(latin1.encode(padded))
    ..add(Float32List.fromList(values).buffer.asUint8List());
  return out.toBytes();
}

void main() {
  test('reads an npz of float32 arrays', () {
    final archive = Archive()
      ..add(ArchiveFile.bytes('a.npy', _npy([1, 2.5], '(2,)')))
      ..add(ArchiveFile.bytes('b.npy', _npy([3], '()')));
    final arrays = parseNpz(Uint8List.fromList(ZipEncoder().encode(archive)));
    expect(arrays['a'], [1.0, 2.5]);
    expect(arrays['b'], [3.0]);
  });

  test('rejects other npy layouts', () {
    final bytes = _npy([1], '(1,)');
    final text = latin1.decode(bytes).replaceFirst('<f4', '<f8');
    expect(() => parseNpy(latin1.encode(text)), throwsFormatException);
  });

  test('maps phonemes to ids and drops unknown characters', () {
    const vocab = {'a': 15, 'ɛ': 47, ' ': 3};
    expect(phonemeIds('aɛ a?', vocab), [1, 15, 47, 3, 15, 2]);
  });

  group('splitForSynthesis', () {
    test('keeps short text whole', () {
      expect(splitForSynthesis('xin chào'), ['xin chào']);
    });

    test('cuts after the last comma that fits', () {
      final text = '${'a' * 100}, ${'b' * 100}';
      expect(splitForSynthesis(text), ['${'a' * 100},', 'b' * 100]);
    });

    test('cuts at a space without punctuation', () {
      final text = List.filled(60, 'abc').join(' ');
      final chunks = splitForSynthesis(text);
      expect(chunks.every((c) => c.length <= 140), isTrue);
      expect(chunks.join(' '), text);
    });

    test('cuts a word longer than the limit', () {
      final chunks = splitForSynthesis('x' * 300);
      expect(chunks.map((c) => c.length), [140, 140, 20]);
    });
  });

  test('frame count follows the predicted duration, speed and cap', () {
    expect(frameCount(math.log(2), 1), (2 * vieneuFlowFps).round());
    expect(frameCount(math.log(2), 2), (1 * vieneuFlowFps).round());
    expect(frameCount(math.log(100), 1), (15 * vieneuFlowFps).round());
    expect(frameCount(-20, 1), 2);
  });

  test('time schedule goes from 0 to 1 and sways', () {
    final plain = timeSchedule(4, 0);
    expect(plain, [0, 0.25, 0.5, 0.75, 1]);
    final swayed = timeSchedule(8, -1);
    expect(swayed.first, 0);
    expect(swayed.last, closeTo(1, 1e-12));
    expect(swayed.length, 9);
  });

  test('gaussian noise has unit variance', () {
    final noise = gaussianNoise(20001, math.Random(1));
    final mean = noise.reduce((a, b) => a + b) / noise.length;
    final variance =
        noise.fold<double>(0, (s, x) => s + (x - mean) * (x - mean)) /
        noise.length;
    expect(mean.abs(), lessThan(0.05));
    expect(variance, closeTo(1, 0.05));
  });

  group('trimAndFade', () {
    Float32List tone(int samples) => Float32List.fromList([
      for (var i = 0; i < samples; i++) 0.5 * math.sin(i * 0.3),
    ]);

    test('keeps 40 ms of silence at each end and fades the edges', () {
      final wav = Float32List(vieneuSampleRate * 2)
        ..setRange(
          vieneuSampleRate,
          vieneuSampleRate + vieneuSampleRate ~/ 2,
          tone(vieneuSampleRate ~/ 2),
        );
      final out = trimAndFade(wav);
      final keep = (0.04 * vieneuSampleRate).toInt();
      expect(out.length, vieneuSampleRate ~/ 2 + 2 * keep);
      expect(out.first, 0);
      expect(out.last, 0);
    });

    test('reduces silence to its last 40 ms', () {
      expect(trimAndFade(Float32List(48000)).length, 960);
    });

    test('returns empty audio as it is', () {
      expect(trimAndFade(Float32List(0)), isEmpty);
    });
  });

  test('joins chunks with a pause', () {
    final a = Float32List.fromList(List.filled(2400, 0.5));
    final b = Float32List.fromList(List.filled(2400, 0.5));
    expect(
      joinChunks([a, b]).length,
      2400 * 2 + (vieneuChunkGapSeconds * vieneuSampleRate).toInt(),
    );
    expect(joinChunks([a]), same(a));
  });

  test('writes a mono 16-bit WAV', () {
    final wav = wavBytes(Float32List.fromList([0, 1, -1, 2]));
    final view = ByteData.sublistView(wav);
    expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
    expect(ascii.decode(wav.sublist(8, 12)), 'WAVE');
    expect(view.getUint32(24, Endian.little), 24000);
    expect(view.getUint32(40, Endian.little), 8);
    expect(wav.length, 44 + 8);
    expect(view.getInt16(46, Endian.little), 32767);
    expect(view.getInt16(48, Endian.little), -32767);
    expect(view.getInt16(50, Endian.little), 32767);
  });

  test('parses preset voices', () {
    final json = jsonEncode({
      'default_voice': 'B',
      'presets': {
        'A': {
          'speaker_emb': [0.5, 1],
          'style': [
            [1, 2],
            [3, 4],
          ],
        },
        'B': {
          'speaker_emb': [0],
          'style': [
            [5],
          ],
        },
      },
    });
    final (defaultVoice, voices) = parseVieneuVoices(json);
    expect(defaultVoice, 'B');
    expect(voices.map((v) => v.name), ['A', 'B']);
    expect(voices.first.style, [1, 2, 3, 4]);
    expect(voices.first.speaker, [0.5, 1]);
  });

  test('stats compute the real-time factor and survive a round trip', () {
    const stats = VieneuStats(audioSeconds: 4, totalMs: 2000, chunks: 1);
    expect(stats.rtf, 0.5);
    final sum = stats + stats;
    expect(sum.totalMs, 4000);
    expect(VieneuStats.fromMap(sum.toMap()).audioSeconds, 8);
  });
}
