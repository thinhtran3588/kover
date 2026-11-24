import 'dart:async';
import 'dart:typed_data';

import 'package:kover/utils/logging.dart';

/// An audio request in progress, that can be cancelled.
class Synthesis {
  late final Future<Uint8List?> audio;
  var cancelled = false;

  /// Set by the synthesizer to abort its work when cancelled.
  void Function()? onCancel;

  void cancel() {
    cancelled = true;
    onCancel?.call();
  }
}

/// The most recent syntheses by key, so that audio requested ahead of time is
/// reused when it is needed.
class SynthesisCache<K> {
  final int capacity;
  final Future<Uint8List?> Function(K key, Synthesis synthesis) synthesize;
  final _entries = <K, Synthesis>{};

  SynthesisCache({required this.capacity, required this.synthesize});

  bool contains(K key) => _entries.containsKey(key);

  /// The synthesis of [key], started when there is none. The oldest ones are
  /// cancelled beyond the capacity.
  Synthesis obtain(K key) {
    var synthesis = _entries.remove(key);
    if (synthesis == null) {
      final created = synthesis = Synthesis();
      created.audio = _guarded(key, created);
      unawaited(
        created.audio.then((audio) {
          if (audio == null) remove(key, created);
        }),
      );
    }
    _entries[key] = synthesis;

    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first)!.cancel();
    }
    return synthesis;
  }

  Future<Uint8List?> _guarded(K key, Synthesis synthesis) async {
    try {
      return await synthesize(key, synthesis);
    } catch (error, stacktrace) {
      log.error('tts synthesis failed', error: error, stacktrace: stacktrace);
      return null;
    }
  }

  /// Forgets [synthesis], when it is still the one stored for [key].
  void remove(K key, Synthesis synthesis) {
    if (identical(_entries[key], synthesis)) _entries.remove(key);
  }

  void clear() {
    final all = _entries.values.toList();
    _entries.clear();
    for (final synthesis in all) {
      synthesis.cancel();
    }
  }
}
