import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

const _imageExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.avif'};

/// A CBZ/ZIP archive of page images, read lazily from disk.
class ComicArchive {
  final InputFileStream _input;
  final Archive _archive;

  /// Names of the page images in reading order.
  final List<String> imageEntries;

  ComicArchive._(this._input, this._archive, this.imageEntries);

  static ComicArchive open(String path) {
    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final entries =
          archive.files
              .where((f) => f.isFile && _isPageImage(f.name))
              .map((f) => f.name)
              .toList()
            ..sort(compareNatural);
      return ComicArchive._(input, archive, entries);
    } catch (_) {
      input.closeSync();
      rethrow;
    }
  }

  static bool _isPageImage(String name) {
    if (name.startsWith('__MACOSX/')) return false;
    if (p.posix.basename(name).startsWith('.')) return false;
    return _imageExtensions.contains(p.posix.extension(name).toLowerCase());
  }

  Uint8List readPage(int index) {
    final file = _archive.findFile(imageEntries[index]);
    final bytes = file?.readBytes();
    if (bytes == null) {
      throw StateError('Missing page $index in archive');
    }
    return bytes;
  }

  void close() {
    _archive.clearSync();
    _input.closeSync();
  }
}
