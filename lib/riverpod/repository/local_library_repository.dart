import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:kover/database/app_database.dart';
import 'package:kover/models/enums/local_book_source.dart';
import 'package:kover/models/image_model.dart';
import 'package:kover/models/local_book_model.dart';
import 'package:kover/riverpod/repository/database.dart';
import 'package:kover/utils/local_books/book_file_format.dart';
import 'package:kover/utils/local_books/cover_thumbnail.dart';
import 'package:kover/utils/local_books/local_book_metadata.dart';
import 'package:kover/utils/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'local_library_repository.freezed.dart';
part 'local_library_repository.g.dart';

const _booksDirectory = 'local_books';

@freezed
sealed class LocalImportResult with _$LocalImportResult {
  const factory LocalImportResult.imported(int id) = LocalImportImported;
  const factory LocalImportResult.duplicate(int id) = LocalImportDuplicate;
  const factory LocalImportResult.unsupported() = LocalImportUnsupported;
  const factory LocalImportResult.failed(Object error) = LocalImportFailed;
}

/// The on-device library. Independent of the Kavita server: it only depends on
/// the database and the file system.
@Riverpod(keepAlive: true)
LocalLibraryRepository localLibraryRepository(Ref ref) {
  return LocalLibraryRepository(ref.watch(databaseProvider));
}

class LocalLibraryRepository {
  final AppDatabase _db;

  LocalLibraryRepository(this._db);

  Future<Directory> _supportDirectory() => getApplicationSupportDirectory();

  /// Copies the file at [sourcePath] into the library.
  Future<LocalImportResult> importFile(
    String sourcePath, {
    String? displayName,
    LocalBookSource source = .device,
    String? remoteId,
  }) async {
    final name = displayName ?? p.basename(sourcePath);
    final format = formatForFileName(name);
    if (format == null) return const .unsupported();

    File? copy;
    try {
      final size = await File(sourcePath).length();

      final existing = remoteId != null
          ? await _db.localBooksDao.findByRemoteId(remoteId)
          : await _db.localBooksDao.findDuplicate(name, size);
      if (existing != null) return .duplicate(existing.id);

      final support = await _supportDirectory();
      final relativePath = p.join(
        _booksDirectory,
        '${DateTime.now().millisecondsSinceEpoch}_${_sanitize(name)}',
      );
      copy = File(p.join(support.path, relativePath));
      await copy.parent.create(recursive: true);
      await File(sourcePath).copy(copy.path);

      final metadata = await extractMetadata(
        copy.path,
        format,
        fallbackTitle: p.basenameWithoutExtension(name),
      );
      final cover = metadata.cover == null
          ? null
          : await createCoverThumbnail(metadata.cover!);

      final id = await _db.localBooksDao.insertBook(
        LocalBooksCompanion.insert(
          title: metadata.title,
          author: Value(metadata.author),
          language: Value(metadata.language),
          format: format,
          source: source,
          remoteId: Value(remoteId),
          fileName: name,
          filePath: relativePath,
          fileSize: size,
          pages: metadata.pages,
          cover: Value(cover),
        ),
      );
      return .imported(id);
    } catch (e, stacktrace) {
      log.error('failed to import book', error: e, stacktrace: stacktrace);
      if (copy != null && await copy.exists()) await copy.delete();
      return .failed(e);
    }
  }

  static String _sanitize(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');

  Stream<List<LocalBookModel>> watchBooks({LocalBookSource? source}) {
    return _db.localBooksDao
        .watchAll(source: source)
        .map((rows) => rows.map(LocalBookModel.fromDatabaseModel).toList());
  }

  Stream<List<LocalBookModel>> watchContinueReading() {
    return _db.localBooksDao.watchContinueReading().map(
      (rows) => rows.map(LocalBookModel.fromDatabaseModel).toList(),
    );
  }

  Stream<LocalBookModel> watchBook(int id) {
    return _db.localBooksDao
        .watchById(id)
        .map(LocalBookModel.fromDatabaseModel);
  }

  Future<LocalBookModel> getBook(int id) async {
    final row = await _db.localBooksDao.getById(id);
    if (row == null) throw StateError('Local book $id not found');
    return LocalBookModel.fromDatabaseModel(row);
  }

  Future<ImageModel?> getCover(int id) async {
    final data = await _db.localBooksDao.getCover(id);
    return data == null ? null : ImageModel(data: data);
  }

  Stream<Set<String>> watchDriveIds() => _db.localBooksDao.watchRemoteIds();

  /// The id of the local book downloaded from Drive file [remoteId].
  Future<int?> findDriveBookId(String remoteId) async {
    return (await _db.localBooksDao.findByRemoteId(remoteId))?.id;
  }

  Future<File> fileFor(LocalBookModel book) async {
    final support = await _supportDirectory();
    return File(p.join(support.path, book.filePath));
  }

  Future<void> saveProgress(int id, {required int page, String? scrollId}) {
    return _db.localBooksDao.updateProgress(id, page, scrollId);
  }

  Future<void> markRead(int id) async {
    final book = await getBook(id);
    await _db.localBooksDao.updateProgress(id, book.pages, null);
  }

  Future<void> markUnread(int id) {
    return _db.localBooksDao.updateBook(
      id,
      const LocalBooksCompanion(
        pagesRead: Value(0),
        bookScrollId: Value(null),
        lastRead: Value(null),
      ),
    );
  }

  /// Delete the book file, then its row.
  Future<void> delete(int id) async {
    final book = await getBook(id);
    final file = await fileFor(book);
    if (await file.exists()) await file.delete();
    await _db.localBooksDao.deleteById(id);
  }
}
