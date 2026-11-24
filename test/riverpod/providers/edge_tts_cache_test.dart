import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kover/riverpod/providers/tts/edge_tts_cache.dart';

void main() {
  late List<String> calls;
  late Map<String, Completer<Uint8List?>> completers;
  late Map<String, Synthesis> syntheses;
  late SynthesisCache<String> cache;

  setUp(() {
    calls = [];
    completers = {};
    syntheses = {};
    cache = SynthesisCache<String>(
      capacity: 2,
      synthesize: (key, synthesis) {
        calls.add(key);
        syntheses[key] = synthesis;
        return (completers[key] = Completer<Uint8List?>()).future;
      },
    );
  });

  test('the same key shares one synthesis', () {
    final first = cache.obtain('a');
    final second = cache.obtain('a');

    expect(identical(first, second), isTrue);
    expect(calls, ['a']);
    expect(cache.contains('a'), isTrue);
  });

  test('evicts and cancels the oldest beyond the capacity', () {
    var cancelCalls = 0;
    final a = cache.obtain('a')..onCancel = () => cancelCalls++;
    cache
      ..obtain('b')
      ..obtain('c');

    expect(cache.contains('a'), isFalse);
    expect(a.cancelled, isTrue);
    expect(cancelCalls, 1);
    expect(cache.contains('b'), isTrue);
    expect(cache.contains('c'), isTrue);
  });

  test('obtaining an existing key makes it the newest', () {
    cache
      ..obtain('a')
      ..obtain('b')
      ..obtain('a')
      ..obtain('c');

    expect(cache.contains('a'), isTrue);
    expect(cache.contains('b'), isFalse);
    expect(syntheses['b']!.cancelled, isTrue);
  });

  test('a null result is removed so the next obtain retries', () async {
    final first = cache.obtain('a');
    completers['a']!.complete(null);
    expect(await first.audio, isNull);
    await Future<void>.delayed(Duration.zero);

    expect(cache.contains('a'), isFalse);
    final second = cache.obtain('a');
    expect(identical(first, second), isFalse);
    expect(calls, ['a', 'a']);
  });

  test('a throwing synthesis resolves to null', () async {
    final failing = SynthesisCache<String>(
      capacity: 2,
      synthesize: (_, _) async => throw StateError('boom'),
    );
    final synthesis = failing.obtain('a');

    expect(await synthesis.audio, isNull);
    await Future<void>.delayed(Duration.zero);
    expect(failing.contains('a'), isFalse);
  });

  test('remove ignores a different synthesis', () {
    final a = cache.obtain('a');
    cache.remove('a', Synthesis());
    expect(cache.contains('a'), isTrue);

    cache.remove('a', a);
    expect(cache.contains('a'), isFalse);
  });

  test('clear cancels everything', () {
    final a = cache.obtain('a');
    final b = cache.obtain('b');
    cache.clear();

    expect(a.cancelled, isTrue);
    expect(b.cancelled, isTrue);
    expect(cache.contains('a'), isFalse);
    expect(cache.contains('b'), isFalse);
  });
}
