import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kover/models/enums/format.dart';
import 'package:kover/utils/local_books/book_file_format.dart';
import 'package:kover/utils/local_books/comic_archive.dart';
import 'package:path/path.dart' as p;

void main() {
  test('lists page images in natural order, skipping junk entries', () {
    final tempDir = Directory.systemTemp.createTempSync('comic_archive_test');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final archive = Archive();
    for (final name in [
      '10.jpg',
      '2.jpg',
      '__MACOSX/._2.jpg',
      '.DS_Store',
      'notes.txt',
    ]) {
      archive.add(ArchiveFile.bytes(name, [1, 2, 3]));
    }
    final path = p.join(tempDir.path, 'comic.cbz');
    File(path).writeAsBytesSync(ZipEncoder().encodeBytes(archive));

    final comic = ComicArchive.open(path);
    addTearDown(comic.close);

    expect(comic.imageEntries, ['2.jpg', '10.jpg']);
    expect(comic.readPage(0), [1, 2, 3]);
  });

  test('maps file names to formats', () {
    expect(formatForFileName('a.EPUB'), Format.epub);
    expect(formatForFileName('a.pdf'), Format.pdf);
    expect(formatForFileName('a.cbz'), Format.archive);
    expect(formatForFileName('a.zip'), Format.archive);
    expect(formatForFileName('a.cbr'), isNull);
  });
}
