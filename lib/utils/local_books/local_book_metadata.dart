import 'dart:isolate';
import 'dart:typed_data';

import 'package:kover/models/enums/format.dart';
import 'package:kover/utils/local_books/comic_archive.dart';
import 'package:kover/utils/local_books/cover_thumbnail.dart';
import 'package:kover/utils/local_books/epub_archive.dart';
import 'package:pdfrx/pdfrx.dart';

const _pdfCoverWidth = 300.0;

typedef LocalBookMetadata = ({
  String title,
  String? author,
  String? language,
  int pages,

  /// Raw (unscaled) cover image bytes.
  Uint8List? cover,
});

/// Reads title, author, language, page count and cover of the book at [path].
/// [fallbackTitle] is used when the file does not name itself.
Future<LocalBookMetadata> extractMetadata(
  String path,
  Format format, {
  required String fallbackTitle,
}) {
  return switch (format) {
    .epub => Isolate.run(() => _epubMetadata(path, fallbackTitle)),
    .archive => Isolate.run(() => _comicMetadata(path, fallbackTitle)),
    .pdf => _pdfMetadata(path, fallbackTitle),
    _ => throw UnsupportedError('Unsupported book format: $format'),
  };
}

LocalBookMetadata _epubMetadata(String path, String fallbackTitle) {
  final archive = EpubArchive.open(path);
  try {
    final info = archive.readInfo();
    if (info.spine.isEmpty) throw const FormatException('Empty EPUB');
    return (
      title: info.title ?? fallbackTitle,
      author: info.author,
      language: info.language,
      pages: info.spine.length,
      cover: archive.readCover(),
    );
  } finally {
    archive.close();
  }
}

LocalBookMetadata _comicMetadata(String path, String fallbackTitle) {
  final archive = ComicArchive.open(path);
  try {
    if (archive.imageEntries.isEmpty) {
      throw const FormatException('Archive has no images');
    }
    return (
      title: fallbackTitle,
      author: null,
      language: null,
      pages: archive.imageEntries.length,
      cover: archive.readPage(0),
    );
  } finally {
    archive.close();
  }
}

Future<LocalBookMetadata> _pdfMetadata(
  String path,
  String fallbackTitle,
) async {
  await pdfrxFlutterInitialize();
  final document = await PdfDocument.openFile(path);
  try {
    Uint8List? cover;
    final page = document.pages.firstOrNull;
    if (page != null) {
      final rendered = await page.render(
        fullWidth: _pdfCoverWidth,
        fullHeight: _pdfCoverWidth * page.height / page.width,
      );
      if (rendered != null) {
        try {
          final image = await rendered.createImage();
          try {
            cover = await encodePng(image);
          } finally {
            image.dispose();
          }
        } finally {
          rendered.dispose();
        }
      }
    }
    return (
      title: fallbackTitle,
      author: null,
      language: null,
      pages: document.pages.length,
      cover: cover,
    );
  } finally {
    await document.dispose();
  }
}
