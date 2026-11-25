import 'dart:io';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:kover/models/drive_item_model.dart';
import 'package:kover/riverpod/repository/google_drive_repository.dart';
import 'package:kover/riverpod/repository/local_library_repository.dart';
import 'package:kover/sync/google_drive_operations.dart';
import 'package:kover/utils/cancellation_token.dart';
import 'package:kover/utils/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pool/pool.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'google_drive.freezed.dart';
part 'google_drive.g.dart';

/// A folder of Drive, the "Shared with me" view when [folderId] is
/// [GoogleDriveOperations.sharedFolderId], or the search results for [search]
/// when it is not empty. Pages are appended with [loadMore].
@riverpod
class DriveFolder extends _$DriveFolder {
  var _loadingMore = false;

  @override
  Future<DriveListing> build(String folderId, String search) {
    return ref
        .read(googleDriveRepositoryProvider)
        .list(folderId, search: search);
  }

  Future<void> loadMore() async {
    final current = state.value;
    final token = current?.nextPageToken;
    if (current == null || token == null || _loadingMore) return;

    _loadingMore = true;
    try {
      final next = await ref
          .read(googleDriveRepositoryProvider)
          .list(folderId, search: search, pageToken: token);
      state = AsyncData((
        items: [...current.items, ...next.items],
        nextPageToken: next.nextPageToken,
      ));
    } catch (e, stacktrace) {
      // The token is kept, so the next attempt retries the same page.
      log.error('failed to load more', error: e, stacktrace: stacktrace);
    } finally {
      _loadingMore = false;
    }
  }
}

/// The Drive file ids that are in the on-device library.
@riverpod
Stream<Set<String>> driveDownloadedIds(Ref ref) {
  return ref.watch(localLibraryRepositoryProvider).watchDriveIds();
}

/// Where downloads are written before being imported.
@riverpod
Future<Directory> driveTempDirectory(Ref ref) => getTemporaryDirectory();

@freezed
sealed class DriveDownloadState with _$DriveDownloadState {
  /// [progress] is null while queued or when the size is unknown.
  const factory DriveDownloadState.downloading(double? progress) =
      DriveDownloading;
  const factory DriveDownloadState.failed(String message) = DriveDownloadFailed;
}

/// Downloads Drive books and imports them into the on-device library. The
/// state holds the downloads in flight or failed, by Drive file id.
@Riverpod(keepAlive: true)
class DriveDownloads extends _$DriveDownloads {
  final _pool = Pool(2);
  final _tokens = <String, CancellationToken>{};

  @override
  Map<String, DriveDownloadState> build() => {};

  void _set(String id, DriveDownloadState? value) {
    final next = {...state};
    if (value == null) {
      next.remove(id);
    } else {
      next[id] = value;
    }
    state = next;
  }

  /// Returns the id of the local book, or null if it was cancelled or failed.
  Future<int?> download(DriveItemModel item) async {
    if (state[item.id] is DriveDownloading) return null;

    final token = _tokens[item.id] = CancellationToken();
    _set(item.id, const .downloading(null));

    File? temp;
    try {
      final directory = await ref.read(driveTempDirectoryProvider.future);
      temp = File(p.join(directory.path, 'drive_${item.id}'));

      await _pool.withResource(() {
        token.throwIfCancelled();
        return ref
            .read(googleDriveRepositoryProvider)
            .download(
              item.id,
              temp!,
              token: token,
              onProgress: (received, total) {
                final progress = total == null || total == 0
                    ? null
                    : received / total;
                final current = state[item.id];
                // Avoid rebuilding on every chunk.
                if (current is DriveDownloading &&
                    progress != null &&
                    current.progress != null &&
                    progress - current.progress! < 0.01) {
                  return;
                }
                _set(item.id, .downloading(progress));
              },
            );
      });

      final result = await ref
          .read(localLibraryRepositoryProvider)
          .importFile(
            temp.path,
            displayName: item.name,
            source: .googleDrive,
            remoteId: item.id,
          );
      _set(item.id, null);
      return switch (result) {
        LocalImportImported(:final id) || LocalImportDuplicate(:final id) => id,
        LocalImportUnsupported() => throw StateError('Unsupported file'),
        LocalImportFailed(:final error) => throw error,
      };
    } on CancellationException {
      _set(item.id, null);
      return null;
    } catch (e, stacktrace) {
      log.error('drive download failed', error: e, stacktrace: stacktrace);
      _set(item.id, .failed(e.toString()));
      return null;
    } finally {
      _tokens.remove(item.id);
      if (temp != null && await temp.exists()) await temp.delete();
    }
  }

  void cancel(String id) => _tokens[id]?.cancel();
}
