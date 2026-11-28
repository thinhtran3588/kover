import 'package:drift/drift.dart';
import 'package:kover/database/app_database.dart';
import 'package:kover/database/tables/local_books.dart';
import 'package:kover/models/enums/local_book_source.dart';

part 'local_books_dao.g.dart';

@DriftAccessor(tables: [LocalBooks])
class LocalBooksDao extends DatabaseAccessor<AppDatabase>
    with _$LocalBooksDaoMixin {
  LocalBooksDao(super.attachedDatabase);

  /// Select every column except the cover blob, so lists do not load blobs.
  JoinedSelectStatement<HasResultSet, dynamic> _selectWithoutCover() {
    return selectOnly(localBooks)..addColumns([
      for (final column in localBooks.$columns)
        if (column != localBooks.cover) column,
    ]);
  }

  LocalBook _toBook(TypedResult row) => LocalBook(
    id: row.read(localBooks.id)!,
    title: row.read(localBooks.title)!,
    author: row.read(localBooks.author),
    language: row.read(localBooks.language),
    format: row.readWithConverter(localBooks.format)!,
    source: row.readWithConverter(localBooks.source)!,
    remoteId: row.read(localBooks.remoteId),
    fileName: row.read(localBooks.fileName)!,
    filePath: row.read(localBooks.filePath)!,
    fileSize: row.read(localBooks.fileSize)!,
    pages: row.read(localBooks.pages)!,
    pagesRead: row.read(localBooks.pagesRead)!,
    bookScrollId: row.read(localBooks.bookScrollId),
    lastRead: row.read(localBooks.lastRead),
    isFavorite: row.read(localBooks.isFavorite)!,
    created: row.read(localBooks.created)!,
  );

  /// Watch all books, most recently read or added first. Optionally limited to
  /// [source] and, with [favoritesOnly], to favorites. The returned books have
  /// no cover, see [getCover].
  Stream<List<LocalBook>> watchAll({
    LocalBookSource? source,
    bool favoritesOnly = false,
  }) {
    final query = _selectWithoutCover()
      ..orderBy([
        OrderingTerm.desc(
          coalesce([localBooks.lastRead, localBooks.created]),
        ),
      ]);
    if (source != null) {
      query.where(localBooks.source.equalsValue(source));
    }
    if (favoritesOnly) {
      query.where(localBooks.isFavorite.equals(true));
    }
    return query.map(_toBook).watch();
  }

  /// Watch started but unfinished books, most recently read first.
  Stream<List<LocalBook>> watchContinueReading() {
    final query = _selectWithoutCover()
      ..where(
        localBooks.lastRead.isNotNull() &
            localBooks.pagesRead.isBiggerThanValue(0) &
            localBooks.pagesRead.isSmallerThan(localBooks.pages),
      )
      ..orderBy([OrderingTerm.desc(localBooks.lastRead)])
      ..limit(20);
    return query.map(_toBook).watch();
  }

  Stream<LocalBook> watchById(int id) {
    final query = _selectWithoutCover()..where(localBooks.id.equals(id));
    return query.map(_toBook).watchSingle();
  }

  Future<LocalBook?> getById(int id) {
    final query = _selectWithoutCover()..where(localBooks.id.equals(id));
    return query.map(_toBook).getSingleOrNull();
  }

  Future<LocalBook?> findDuplicate(String fileName, int fileSize) {
    final query = _selectWithoutCover()
      ..where(
        localBooks.fileName.equals(fileName) &
            localBooks.fileSize.equals(fileSize),
      )
      ..limit(1);
    return query.map(_toBook).getSingleOrNull();
  }

  Future<LocalBook?> findByRemoteId(String remoteId) {
    final query = _selectWithoutCover()
      ..where(localBooks.remoteId.equals(remoteId))
      ..limit(1);
    return query.map(_toBook).getSingleOrNull();
  }

  /// Insert a book and return its id.
  Future<int> insertBook(LocalBooksCompanion book) {
    return into(localBooks).insert(book);
  }

  Future<void> updateBook(int id, LocalBooksCompanion book) {
    return (update(localBooks)..where((t) => t.id.equals(id))).write(book);
  }

  /// Store the reading position and mark the book as read just now.
  Future<void> updateProgress(int id, int pagesRead, String? scrollId) {
    return updateBook(
      id,
      LocalBooksCompanion(
        pagesRead: Value(pagesRead),
        bookScrollId: Value(scrollId),
        lastRead: Value(DateTime.now()),
      ),
    );
  }

  Future<void> setFavorite(int id, bool value) {
    return updateBook(id, LocalBooksCompanion(isFavorite: Value(value)));
  }

  Future<void> deleteById(int id) {
    return (delete(localBooks)..where((t) => t.id.equals(id))).go();
  }

  /// Watch the remote ids of all books that came from a remote source.
  Stream<Set<String>> watchRemoteIds() {
    final query = selectOnly(localBooks)
      ..addColumns([localBooks.remoteId])
      ..where(localBooks.remoteId.isNotNull());
    return query
        .map((row) => row.read(localBooks.remoteId)!)
        .watch()
        .map((ids) => ids.toSet());
  }

  /// Get only the cover blob of the book [id].
  Future<Uint8List?> getCover(int id) async {
    final query = selectOnly(localBooks)
      ..addColumns([localBooks.cover])
      ..where(localBooks.id.equals(id));
    final row = await query.getSingleOrNull();
    return row?.read(localBooks.cover);
  }
}
