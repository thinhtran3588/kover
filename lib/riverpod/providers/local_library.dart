import 'dart:io';
import 'dart:isolate';

import 'package:html/parser.dart';
import 'package:kover/models/book_chapter_model.dart';
import 'package:kover/models/enums/local_book_source.dart';
import 'package:kover/models/image_model.dart';
import 'package:kover/models/local_book_model.dart';
import 'package:kover/models/page_content.dart';
import 'package:kover/models/pdf_model.dart';
import 'package:kover/riverpod/repository/local_library_repository.dart';
import 'package:kover/utils/local_books/comic_archive.dart';
import 'package:kover/utils/local_books/epub_archive.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'local_library.g.dart';

@riverpod
Stream<List<LocalBookModel>> localBooks(Ref ref, {LocalBookSource? source}) {
  return ref.watch(localLibraryRepositoryProvider).watchBooks(source: source);
}

@riverpod
Stream<List<LocalBookModel>> localContinueReading(Ref ref) {
  return ref.watch(localLibraryRepositoryProvider).watchContinueReading();
}

@riverpod
Stream<LocalBookModel> localBook(Ref ref, int id) {
  return ref.watch(localLibraryRepositoryProvider).watchBook(id);
}

@riverpod
Future<ImageModel?> localBookCover(Ref ref, int id) {
  return ref.watch(localLibraryRepositoryProvider).getCover(id);
}

/// The absolute path of the file of book [id]. Does not follow progress
/// updates, so pages are not rebuilt while reading.
Future<String> _bookPath(Ref ref, int id) async {
  final repo = ref.read(localLibraryRepositoryProvider);
  return (await repo.fileFor(await repo.getBook(id))).path;
}

/// The table of contents of the EPUB [id].
@riverpod
Future<List<BookChapterModel>> localToc(Ref ref, int id) async {
  final path = await _bookPath(ref, id);
  return Isolate.run(() {
    final archive = EpubArchive.open(path);
    try {
      return archive.readToc();
    } finally {
      archive.close();
    }
  });
}

@riverpod
Future<PageContent> localEpubPage(
  Ref ref, {
  required int id,
  required int page,
}) async {
  final path = await _bookPath(ref, id);
  // The archive is reopened for every page: that only reads the central
  // directory, and avoids sharing it across isolates.
  final html = await Isolate.run(() {
    final archive = EpubArchive.open(path);
    try {
      return archive.buildPageHtml(page);
    } finally {
      archive.close();
    }
  });
  return PageContent(root: parseFragment(html), fonts: const []);
}

@riverpod
Future<ImageModel> localImagePage(
  Ref ref, {
  required int id,
  required int page,
}) async {
  final path = await _bookPath(ref, id);
  final data = await Isolate.run(() {
    final archive = ComicArchive.open(path);
    try {
      return archive.readPage(page);
    } finally {
      archive.close();
    }
  });
  return ImageModel(data: data);
}

@riverpod
Future<PdfModel> localPdf(Ref ref, int id) async {
  final path = await _bookPath(ref, id);
  return PdfModel(data: await File(path).readAsBytes());
}
