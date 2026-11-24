import 'dart:async';
import 'dart:math' hide log;

import 'package:async/async.dart';
import 'package:material_ui/material_ui.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hooks_riverpod/experimental/persist.dart';
import 'package:kover/riverpod/managers/download_manager/download_foreground.dart';
import 'package:kover/riverpod/managers/download_manager/download_worker.dart';
import 'package:kover/riverpod/providers/connectivity.dart';
import 'package:kover/riverpod/providers/settings/credentials.dart';
import 'package:kover/riverpod/providers/settings/download_settings.dart';
import 'package:kover/riverpod/repository/download_repository.dart';
import 'package:kover/riverpod/repository/series_repository.dart';
import 'package:kover/riverpod/repository/storage_repository.dart';
import 'package:kover/riverpod/repository/volumes_repository.dart';
import 'package:kover/utils/lifecycle.dart';
import 'package:kover/utils/logging.dart';
import 'package:riverpod_annotation/experimental/json_persist.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'download_manager.freezed.dart';
part 'download_manager.g.dart';

@freezed
sealed class DownloadManagerState with _$DownloadManagerState {
  const DownloadManagerState._();

  const factory DownloadManagerState({
    @Default({}) Set<int> downloadQueue,

    /// Chapter id to the last error message of chapters that gave up.
    @Default({}) Map<int, String> failed,
    @Default({}) Set<int> paused,
  }) = _DownloadManagerState;

  factory DownloadManagerState.fromJson(Map<String, Object?> json) =>
      _$DownloadManagerStateFromJson(json);
}

@Riverpod(keepAlive: true)
Future<DownloadWorker> downloadWorker(Ref ref) async {
  final credentials = await ref.watch(credentialsProvider.future);

  final worker = await DownloadWorker.spawn(
    url: credentials.url!,
    key: credentials.apiKey!,
    customHeaders: credentials.customHeaders,
    ignoreCertificateValidation: credentials.ignoreCertificateValidation,
  );

  ref.onDispose(worker.close);

  return worker;
}

@Riverpod(keepAlive: true)
@JsonPersist()
class DownloadManager extends _$DownloadManager {
  static const _maxAttempts = 3;

  /// Waits before the second and third attempt of a chapter.
  @visibleForTesting
  static List<Duration> retryDelays = const [
    Duration(seconds: 2),
    Duration(seconds: 5),
  ];

  final Map<int, CancelableOperation<void>> _activeTasks = {};
  int _nextRequestId = 0;

  @override
  Future<DownloadManagerState> build() async {
    listenSelf((previous, next) {
      final queue = next.value;
      if (queue != null) {
        DownloadForeground.sync(
          queue.downloadQueue.difference(queue.paused).length,
        );
      }
      unawaited(_processQueue());
    });
    _listenConnectivity();
    _listenAppLifecycle();
    _listenDownloadSettings();

    await persist(
      ref.watch(storageProvider.future),
      options: const StorageOptions(cacheTime: StorageCacheTime.unsafe_forever),
    ).future;

    return state.value ?? const DownloadManagerState();
  }

  Future<void> enqueue(int chapterId) async {
    final current = await future;

    state = AsyncData(_enqueued(current, [chapterId]));
    log.info(
      'enqueued chapter for download',
      attributes: {
        'chapter_id': chapterId,
      },
    );
  }

  Future<void> enqueueVolume(int volumeId) async {
    final repository = ref.read(volumesRepositoryProvider);
    final ids = await repository.fetchChapterIds(volumeId: volumeId);
    final current = await future;

    state = AsyncData(_enqueued(current, ids));
    log.info(
      'enqueued volume for download',
      attributes: {
        'volume_id': volumeId,
        'chapter_count': ids.length,
      },
    );
  }

  Future<void> enqueueSeries(int seriesId) async {
    final repository = ref.read(seriesRepositoryProvider);
    final ids = await repository.fetchChapterIds(seriesId: seriesId);
    final current = await future;

    state = AsyncData(_enqueued(current, ids));
    log.info(
      'enqueued series for download',
      attributes: {
        'series_id': seriesId,
        'chapter_count': ids.length,
      },
    );
  }

  /// Re-queues the failed chapter [chapterId].
  Future<void> retry(int chapterId) => enqueue(chapterId);

  /// Re-queues every failed chapter.
  Future<void> retryAll() async {
    final current = await future;

    state = AsyncData(_enqueued(current, current.failed.keys));
    log.info(
      'retrying all failed downloads',
      attributes: {'count': current.failed.length},
    );
  }

  /// Stops the download of [chapterId] but keeps the pages fetched so far.
  Future<void> pause(int chapterId) async {
    await _activeTasks.remove(chapterId)?.cancel();
    final current = await future;

    state = AsyncData(
      current.copyWith(
        downloadQueue: Set<int>.from(current.downloadQueue)..remove(chapterId),
        paused: {...current.paused, chapterId},
      ),
    );
    log.info(
      'paused download for chapter',
      attributes: {'chapter_id': chapterId},
    );
  }

  /// Puts the paused chapter [chapterId] back in the queue.
  Future<void> resume(int chapterId) => enqueue(chapterId);

  Future<void> cancel(int chapterId) async {
    await _activeTasks.remove(chapterId)?.cancel();
    final current = await future;

    state = AsyncData(_cleared(current, [chapterId]));
    log.info(
      'canceled download for chapter',
      attributes: {'chapter_id': chapterId},
    );
  }

  Future<void> cancelAll() async {
    final current = await future;

    await _clearActiveTasks();

    state = AsyncData(
      current.copyWith(downloadQueue: {}, failed: {}, paused: {}),
    );
    log.info(
      'canceled all downloads',
      attributes: {'count': current.downloadQueue.length},
    );
  }

  Future<void> deleteChapter(int chapterId) async {
    await _clearIds([chapterId]);
    await ref
        .read(downloadRepositoryProvider)
        .deleteChapter(chapterId: chapterId);
  }

  Future<void> deleteVolume(int volumeId) async {
    final ids = await ref
        .read(volumesRepositoryProvider)
        .getChapterIds(volumeId: volumeId);

    await _clearIds(ids);
    await ref.read(downloadRepositoryProvider).deleteVolume(volumeId);
  }

  Future<void> deleteSeries(int seriesId) async {
    final ids = await ref
        .read(seriesRepositoryProvider)
        .allChapterIds(seriesId: seriesId);

    await _clearIds(ids);
    await ref.read(downloadRepositoryProvider).deleteSeries(seriesId: seriesId);
  }

  Future<void> _processQueue() async {
    if (ref.read(hasConnectionProvider).value != true) {
      return;
    }

    final concurrentDownloads = await ref.read(
      downloadSettingsProvider.selectAsync(
        (state) => state.concurrentDownloads,
      ),
    );

    final current = await future;
    if (current.downloadQueue.isEmpty) return;
    final worker = await ref.read(downloadWorkerProvider.future);

    // Evaluate the active set only after the last await so concurrent calls
    // cannot exceed the cap or start a chapter twice.
    final toStart = current.downloadQueue
        .where((i) => !_activeTasks.containsKey(i))
        .where((i) => !current.paused.contains(i))
        .take(max(0, concurrentDownloads - _activeTasks.length))
        .toList();

    for (final chapterId in toStart) {
      log.info(
        'starting download for chapter',
        attributes: {
          'chapter_id': chapterId,
        },
      );

      unawaited(_startDownload(chapterId, worker));
    }
  }

  Future<void> _clearActiveTasks() async {
    final tasks = _activeTasks.values.toList();

    // Clear the active tasks map before awaiting cancellation to avoid
    // modifying the map while iterating.
    _activeTasks.clear();

    for (final task in tasks) {
      await task.cancel();
    }
  }

  Future<void> _startDownload(int chapterId, DownloadWorker worker) async {
    final repository = ref.read(downloadRepositoryProvider);
    CancelableOperation<void>? active;
    var error = '';

    try {
      for (var attempt = 0; attempt < _maxAttempts; attempt++) {
        if (attempt > 0) {
          // Held in the active tasks so cancelling also cuts the wait short.
          final wait = CancelableOperation.fromFuture(
            Future<void>.delayed(
              retryDelays[min(attempt - 1, retryDelays.length - 1)],
            ),
          );
          active = wait;
          _activeTasks[chapterId] = wait;
          await wait.valueOrCancellation();
          if (wait.isCanceled) return;
        }

        final requestId = _nextRequestId++;
        final task = CancelableOperation.fromFuture(
          worker.downloadChapter(requestId: requestId, chapterId: chapterId),
          onCancel: () {
            worker.cancel(requestId);
          },
        );
        active = task;
        _activeTasks[chapterId] = task;

        try {
          await task.valueOrCancellation();
          if (task.isCanceled) return;

          if (await repository.isChapterDownloaded(chapterId: chapterId)) {
            log.info(
              'download completed for chapter',
              attributes: {'chapter_id': chapterId},
            );
            await _settle(chapterId, task);
            return;
          }
          error = 'Download incomplete';
        } catch (e, stacktrace) {
          if (task.isCanceled) return;
          error = e.toString();
          log.error(
            'download failed for chapter',
            error: e,
            stacktrace: stacktrace,
            attributes: {
              'chapter_id': chapterId,
              'attempt': attempt + 1,
            },
          );
        }
      }

      // Offline: keep the chapter queued so it resumes on reconnect instead of
      // being marked failed.
      if (ref.read(hasConnectionProvider).value != true) {
        log.info(
          'offline, keeping chapter queued',
          attributes: {'chapter_id': chapterId},
        );
        return;
      }

      log.warning(
        'giving up on chapter download',
        attributes: {'chapter_id': chapterId, 'error': error},
      );
      await _settle(chapterId, active, error: error);
    } finally {
      if (active != null && identical(_activeTasks[chapterId], active)) {
        _activeTasks.remove(chapterId);
      }
    }
  }

  /// Takes [chapterId] out of the queue once its download ended, as completed
  /// or, with an [error], as failed. Does nothing if [task] no longer owns the
  /// chapter because it was cancelled meanwhile.
  Future<void> _settle(
    int chapterId,
    CancelableOperation<void>? task, {
    String? error,
  }) async {
    final current = await future;
    if (!identical(_activeTasks[chapterId], task)) return;

    // Free the slot in the same step as the state change so the queue never
    // sees the chapter as both done and idle.
    _activeTasks.remove(chapterId);
    final failed = Map<int, String>.from(current.failed)..remove(chapterId);
    state = AsyncData(
      current.copyWith(
        downloadQueue: Set<int>.from(current.downloadQueue)..remove(chapterId),
        failed: error == null ? failed : {...failed, chapterId: error},
      ),
    );
  }

  DownloadManagerState _enqueued(
    DownloadManagerState current,
    Iterable<int> ids,
  ) {
    final idSet = ids.toSet();
    return current.copyWith(
      downloadQueue: {...current.downloadQueue, ...idSet},
      failed: Map<int, String>.from(current.failed)
        ..removeWhere((id, _) => idSet.contains(id)),
      paused: current.paused.difference(idSet),
    );
  }

  DownloadManagerState _cleared(
    DownloadManagerState current,
    Iterable<int> ids,
  ) {
    final idSet = ids.toSet();
    return current.copyWith(
      downloadQueue: current.downloadQueue.difference(idSet),
      failed: Map<int, String>.from(current.failed)
        ..removeWhere((id, _) => idSet.contains(id)),
      paused: current.paused.difference(idSet),
    );
  }

  Future<void> _clearIds(List<int> chapterIds) async {
    final active = _activeTasks.keys
        .where((k) => chapterIds.contains(k))
        .toList();
    for (final k in active) {
      await _activeTasks.remove(k)?.cancel();
    }
    final current = await future;
    state = AsyncData(_cleared(current, chapterIds));
  }

  void _listenConnectivity() {
    ref.listen(hasConnectionProvider, (prev, next) {
      next.whenData((good) async {
        if (prev != null && good != prev.value && good) {
          await _processQueue();
        }
      });
    });
  }

  void _listenAppLifecycle() async {
    final observer = LifecycleOnResumeObserver(
      onResume: _processQueue,
    );
    WidgetsBinding.instance.addObserver(observer);
    ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));
  }

  void _listenDownloadSettings() {
    ref.listen(
      downloadSettingsProvider,
      (prev, next) async {
        next.whenData((next) async {
          if (next.concurrentDownloads != prev?.value?.concurrentDownloads) {
            await _clearActiveTasks();
            await _processQueue();
          }
        });
      },
    );
  }
}
