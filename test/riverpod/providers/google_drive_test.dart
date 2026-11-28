import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/models/drive_item_model.dart';
import 'package:kover/models/enums/local_book_source.dart';
import 'package:kover/riverpod/providers/google_drive.dart';
import 'package:kover/riverpod/repository/google_drive_repository.dart';
import 'package:kover/riverpod/repository/local_library_repository.dart';
import 'package:kover/utils/cancellation_token.dart';

class _FakeDrive implements GoogleDriveRepository {
  @override
  Future<void> download(
    String fileId,
    File target, {
    void Function(int received, int? total)? onProgress,
    CancellationToken? token,
  }) async {
    await target.writeAsString('content');
    onProgress?.call(50, 100);
    onProgress?.call(100, 100);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLibrary implements LocalLibraryRepository {
  final LocalImportResult result;
  String? path;
  String? name;
  LocalBookSource? source;
  String? remoteId;

  _FakeLibrary(this.result);

  @override
  Future<LocalImportResult> importFile(
    String sourcePath, {
    String? displayName,
    LocalBookSource source = LocalBookSource.device,
    String? remoteId,
  }) async {
    path = sourcePath;
    name = displayName;
    this.source = source;
    this.remoteId = remoteId;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const item = DriveItemModel(id: 'f1', name: 'book.epub', isFolder: false);
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('drive_test'));
  tearDown(() => temp.deleteSync(recursive: true));

  ProviderContainer container(_FakeLibrary library) {
    final c = ProviderContainer(
      overrides: [
        googleDriveRepositoryProvider.overrideWithValue(_FakeDrive()),
        localLibraryRepositoryProvider.overrideWithValue(library),
        driveTempDirectoryProvider.overrideWith((ref) async => temp),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test(
    'imports the download with its remote id and clears the entry',
    () async {
      final library = _FakeLibrary(const .imported(7));
      final c = container(library);
      final states = <Map<String, DriveDownloadState>>[];
      c.listen(driveDownloadsProvider, (_, next) => states.add(next));

      final id = await c.read(driveDownloadsProvider.notifier).download(item);

      expect(id, 7);
      expect(library.name, 'book.epub');
      expect(library.source, LocalBookSource.googleDrive);
      expect(library.remoteId, 'f1');
      expect(
        states.any((s) => s['f1'] == const DriveDownloadState.downloading(0.5)),
        isTrue,
      );
      expect(c.read(driveDownloadsProvider), isEmpty);
      expect(File(library.path!).existsSync(), isFalse);
    },
  );

  test('keeps a failed entry when the import fails', () async {
    final library = _FakeLibrary(const .failed('boom'));
    final c = container(library);

    final id = await c.read(driveDownloadsProvider.notifier).download(item);

    expect(id, isNull);
    expect(c.read(driveDownloadsProvider)['f1'], isA<DriveDownloadFailed>());
  });
}
