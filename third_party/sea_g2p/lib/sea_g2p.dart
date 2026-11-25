@DefaultAsset('package:sea_g2p/sea_g2p.dart')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

@Native<Int Function()>(symbol: 'sea_g2p_abi_version')
external int _abiVersion();

@Native<Pointer<Char> Function()>(symbol: 'sea_g2p_last_error')
external Pointer<Char> _lastError();

@Native<Pointer<Void> Function(Pointer<Char>)>(symbol: 'sea_g2p_open')
external Pointer<Void> _open(Pointer<Char> dictPath);

@Native<Void Function(Pointer<Void>)>(symbol: 'sea_g2p_close')
external void _close(Pointer<Void> handle);

@Native<Void Function(Pointer<Char>)>(symbol: 'sea_g2p_string_free')
external void _stringFree(Pointer<Char> text);

@Native<Pointer<Char> Function(Pointer<Void>, Pointer<Char>, Int)>(
  symbol: 'sea_g2p_phonemize',
)
external Pointer<Char> _phonemize(
  Pointer<Void> handle,
  Pointer<Char> text,
  int puncNorm,
);

@Native<Pointer<Char> Function(Pointer<Void>, Pointer<Char>, Int)>(
  symbol: 'sea_g2p_normalize',
)
external Pointer<Char> _normalize(
  Pointer<Void> handle,
  Pointer<Char> text,
  int puncNorm,
);

/// Vietnamese text normalization and grapheme-to-phoneme conversion.
///
/// A handle is not thread-safe, so use one from a single isolate.
class SeaG2p {
  static const _abiVersionExpected = 1;

  final Pointer<Void> _handle;

  SeaG2p._(this._handle);

  /// Opens the dictionary `sea_g2p.bin` at [dictPath].
  factory SeaG2p.open(String dictPath) {
    final version = _abiVersion();
    if (version != _abiVersionExpected) {
      throw StateError('sea-g2p ABI $version, expected $_abiVersionExpected');
    }
    final path = dictPath.toNativeUtf8();
    try {
      final handle = _open(path.cast());
      if (handle == nullptr) throw StateError(_error());
      return SeaG2p._(handle);
    } finally {
      malloc.free(path);
    }
  }

  /// The text with numbers, dates, units and abbreviations spelled out.
  String normalize(String text, {bool puncNorm = false}) =>
      _call(_normalize, text, puncNorm);

  /// Normalizes [text] then converts it to phonemes.
  String phonemize(String text, {bool puncNorm = true}) =>
      _call(_phonemize, text, puncNorm);

  String _call(
    Pointer<Char> Function(Pointer<Void>, Pointer<Char>, int) function,
    String text,
    bool puncNorm,
  ) {
    final input = text.toNativeUtf8();
    try {
      final output = function(_handle, input.cast(), puncNorm ? 1 : 0);
      if (output == nullptr) throw StateError(_error());
      try {
        return output.cast<Utf8>().toDartString();
      } finally {
        _stringFree(output);
      }
    } finally {
      malloc.free(input);
    }
  }

  void close() => _close(_handle);

  static String _error() {
    final error = _lastError();
    return error == nullptr
        ? 'sea-g2p failed'
        : error.cast<Utf8>().toDartString();
  }
}
