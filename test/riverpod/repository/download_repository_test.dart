import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kover/api/openapi.swagger.dart';
import 'package:kover/database/app_database.dart';
import 'package:kover/riverpod/repository/download_repository.dart';
import 'package:kover/riverpod/repository/font_repository.dart';
import 'package:kover/sync/book_sync_operations.dart';
import 'package:kover/sync/chapter_sync_operations.dart';
import 'package:kover/sync/series_sync_operations.dart';
import 'package:kover/sync/volume_sync_operations.dart';

class _FakeChapterOps extends Fake implements ChapterSyncOperations {
  _FakeChapterOps(this.pages);
  final int pages;

  @override
  Future<ChapterDto?> getChapter(int chapterId) async => ChapterDto(
    id: chapterId,
    volumeId: 1,
    pages: pages,
    format: MangaFormat.archive,
  );

  @override
  Future<ChapterCoversCompanion?> getChapterCover(int chapterId) async => null;
}

class _FakeFonts extends Fake implements FontRepository {}

class _FakeSeriesOps extends Fake implements SeriesSyncOperations {}

class _FakeVolumeOps extends Fake implements VolumeSyncOperations {
  @override
  Future<VolumeDto?> getVolume(int volumeId) async => null;

  @override
  Future<VolumeCoversCompanion?> getVolumeCover(int volumeId) async => null;
}

class _FakeBookOps extends Fake implements BookSyncOperations {
  _FakeBookOps({this.failOnPage});
  final int? failOnPage;
  final fetched = <int>[];
  var inFlight = 0;
  var maxInFlight = 0;

  @override
  Future<Uint8List> getImagePage({
    required int chapterId,
    required int page,
  }) async {
    inFlight++;
    maxInFlight = max(maxInFlight, inFlight);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (page == failOnPage) throw Exception('boom');
      fetched.add(page);
      return Uint8List.fromList([page]);
    } finally {
      inFlight--;
    }
  }
}

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

  DownloadRepository build(int pages, _FakeBookOps book) => DownloadRepository(
    db: database,
    fontsRepository: _FakeFonts(),
    bookClient: book,
    chapterClient: _FakeChapterOps(pages),
    volumeClient: _FakeVolumeOps(),
    seriesClient: _FakeSeriesOps(),
  );

  group('DownloadRepository.downloadChapter', () {
    test(
      'when pages are missing, then fetches only those with bounded '
      'concurrency',
      () async {
        await database.downloadDao.insertPagesBatch([
          for (final p in [0, 1, 2])
            DownloadedPagesCompanion.insert(
              chapterId: 7,
              page: p,
              data: Uint8List.fromList([p]),
            ),
        ]);
        final book = _FakeBookOps();

        await build(40, book).downloadChapter(chapterId: 7);

        expect(book.fetched.toSet(), {for (var p = 3; p < 40; p++) p});
        expect(book.maxInFlight, lessThanOrEqualTo(6));
        expect(book.maxInFlight, greaterThan(2));
        final stored = await database.downloadDao.downloadedPageNumbers(
          chapterId: 7,
        );
        expect(stored.length, 40);
      },
    );

    test(
      'when a page fails, then the other pages are still fetched and '
      'persisted and the error propagates',
      () async {
        final book = _FakeBookOps(failOnPage: 20);

        await expectLater(
          build(40, book).downloadChapter(chapterId: 7),
          throwsException,
        );

        final stored = await database.downloadDao.downloadedPageNumbers(
          chapterId: 7,
        );
        expect(stored.toSet(), {
          for (var p = 0; p < 40; p++)
            if (p != 20) p,
        });
      },
    );
  });
}
