import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kover/database/app_database.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<int> insert({
    String name = 'book.epub',
    int size = 100,
    int pages = 10,
    String? remoteId,
  }) {
    return database.localBooksDao.insertBook(
      LocalBooksCompanion.insert(
        title: name,
        format: .epub,
        source: remoteId == null ? .device : .googleDrive,
        remoteId: Value(remoteId),
        fileName: name,
        filePath: 'local_books/$name',
        fileSize: size,
        pages: pages,
        cover: const Value.absent(),
      ),
    );
  }

  group('LocalBooksDao', () {
    test('inserts and reads a book without loading its cover', () async {
      final id = await database.localBooksDao.insertBook(
        LocalBooksCompanion.insert(
          title: 'Book',
          format: .pdf,
          source: .device,
          fileName: 'book.pdf',
          filePath: 'local_books/book.pdf',
          fileSize: 1,
          pages: 3,
          cover: Value(Uint8List.fromList([1, 2, 3])),
        ),
      );

      final book = await database.localBooksDao.getById(id);

      expect(book!.title, 'Book');
      expect(book.format.name, 'pdf');
      expect(book.cover, isNull);
      expect(await database.localBooksDao.getCover(id), [1, 2, 3]);
    });

    test('continue reading only lists started, unfinished books', () async {
      final untouched = await insert(name: 'a.epub');
      final started = await insert(name: 'b.epub');
      final finished = await insert(name: 'c.epub');
      final dao = database.localBooksDao;

      await dao.updateProgress(started, 4, 'scroll');
      await dao.updateProgress(finished, 10, null);

      final books = await dao.watchContinueReading().first;

      expect(books.map((b) => b.id), [started]);
      expect(books.single.bookScrollId, 'scroll');
      expect(untouched, isNot(started));
    });

    test('updateProgress sets lastRead', () async {
      final id = await insert();
      expect((await database.localBooksDao.getById(id))!.lastRead, isNull);

      await database.localBooksDao.updateProgress(id, 2, null);

      final book = await database.localBooksDao.getById(id);
      expect(book!.pagesRead, 2);
      expect(book.lastRead, isNotNull);
    });

    test('finds duplicates by file name and size, and by remote id', () async {
      final id = await insert(name: 'a.epub', size: 5, remoteId: 'drive-1');
      final dao = database.localBooksDao;

      expect((await dao.findDuplicate('a.epub', 5))!.id, id);
      expect(await dao.findDuplicate('a.epub', 6), isNull);
      expect((await dao.findByRemoteId('drive-1'))!.id, id);
      expect(await dao.findByRemoteId('other'), isNull);
      expect(await dao.watchRemoteIds().first, {'drive-1'});
    });

    test('sets favorites and filters by them', () async {
      final a = await insert(name: 'a.epub');
      await insert(name: 'b.epub');
      final dao = database.localBooksDao;

      await dao.setFavorite(a, true);

      expect(
        (await dao.watchAll(favoritesOnly: true).first).map((b) => b.id),
        [a],
      );
      expect(
        await dao.watchAll(source: .googleDrive, favoritesOnly: true).first,
        isEmpty,
      );

      await dao.setFavorite(a, false);

      expect(await dao.watchAll(favoritesOnly: true).first, isEmpty);
    });

    test('filters by source and deletes', () async {
      final device = await insert(name: 'a.epub');
      await insert(name: 'b.epub', remoteId: 'x');
      final dao = database.localBooksDao;

      expect(
        (await dao.watchAll(source: .device).first).map((b) => b.id),
        [device],
      );
      expect(await dao.watchAll().first, hasLength(2));

      await dao.deleteById(device);

      expect(await dao.getById(device), isNull);
    });
  });
}
