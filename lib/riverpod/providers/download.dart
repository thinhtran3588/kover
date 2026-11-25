import 'package:kover/models/download_status.dart';
import 'package:kover/riverpod/managers/download_manager/download_manager.dart';
import 'package:kover/riverpod/providers/series.dart';
import 'package:kover/riverpod/providers/volume.dart';
import 'package:kover/riverpod/repository/download_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'download.g.dart';

/// Whether every page of [chapterId] is stored locally
@riverpod
Stream<bool> chapterDownloaded(
  Ref ref, {
  required int chapterId,
}) {
  final repo = ref.watch(downloadRepositoryProvider);
  return repo.watchIsChapterDownloaded(chapterId: chapterId).distinct();
}

/// The download progress percent for chapter [chapterId]
@riverpod
Stream<double> chapterDownloadProgress(
  Ref ref, {
  required int chapterId,
}) {
  final repo = ref.watch(downloadRepositoryProvider);
  return repo.watchDownloadProgress(chapterId: chapterId).distinct();
}

/// The download status for chapter [chapterId]
@riverpod
Future<DownloadStatus?> chapterDownloadStatus(
  Ref ref, {
  required int chapterId,
}) async {
  final managerFuture = ref.watch(
    downloadManagerProvider.selectAsync(
      (state) => (
        inQueue: state.downloadQueue.contains(chapterId),
        failed: state.failed.containsKey(chapterId),
        paused: state.paused.contains(chapterId),
      ),
    ),
  );
  final downloadProgressFuture = ref.watch(
    chapterDownloadProgressProvider(chapterId: chapterId).future,
  );
  final downloadedFuture = ref.watch(
    chapterDownloadedProvider(chapterId: chapterId).future,
  );

  final manager = await managerFuture;
  final downloadProgress = await downloadProgressFuture;
  final downloaded = await downloadedFuture;

  if (downloaded) return .downloaded();
  if (manager.failed) return .failed(progress: downloadProgress);
  if (manager.paused) return .paused(progress: downloadProgress);
  if (manager.inQueue) {
    if (downloadProgress > 0.0) return .downloading(progress: downloadProgress);
    return .queued();
  }
  // Pages without a queued download mean it stopped before finishing.
  if (downloadProgress > 0.0) return .failed(progress: downloadProgress);
  return null;
}

/// Emits download progress percent for volume [volumeId]
@riverpod
Stream<double> volumeDownloadProgress(
  Ref ref, {
  required int volumeId,
}) {
  final repo = ref.watch(downloadRepositoryProvider);
  return repo.watchVolumeDownloadProgress(volumeId: volumeId).distinct();
}

/// The download status for volume [volumeId]
@riverpod
Future<DownloadStatus?> volumeDownloadStatus(
  Ref ref, {
  required int volumeId,
}) async {
  final progress = await ref.watch(
    volumeDownloadProgressProvider(volumeId: volumeId).future,
  );
  final chapterIds = await ref.watch(
    volumeChapterIdsProvider(volumeId: volumeId).future,
  );
  final manager = await ref.watch(downloadManagerProvider.future);

  return _aggregateStatus(manager, chapterIds, progress);
}

/// Emits total download progress percent for all chapters belonging to series [seriesId]
@riverpod
Stream<double> seriesDownloadProgress(
  Ref ref, {
  required int seriesId,
}) {
  final repo = ref.watch(downloadRepositoryProvider);
  return repo.watchSeriesDownloadProgress(seriesId: seriesId).distinct();
}

/// The download status for series [seriesId]
@riverpod
Future<DownloadStatus?> seriesDownloadStatus(
  Ref ref, {
  required int seriesId,
}) async {
  final progress = await ref.watch(
    seriesDownloadProgressProvider(seriesId: seriesId).future,
  );
  final chapterIds = await ref.watch(
    seriesChapterIdsProvider(seriesId: seriesId).future,
  );
  final manager = await ref.watch(downloadManagerProvider.future);

  return _aggregateStatus(manager, chapterIds, progress);
}

DownloadStatus? _aggregateStatus(
  DownloadManagerState manager,
  List<int> chapterIds,
  double progress,
) {
  if (progress >= 1.0) return .downloaded();
  if (chapterIds.any(manager.downloadQueue.contains)) {
    return progress > 0.0 ? .downloading(progress: progress) : .queued();
  }
  if (chapterIds.any(manager.failed.containsKey)) {
    return .failed(progress: progress);
  }
  if (chapterIds.any(manager.paused.contains)) {
    return .paused(progress: progress);
  }
  return null;
}
