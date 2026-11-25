import 'package:freezed_annotation/freezed_annotation.dart';

part 'download_status.freezed.dart';

@freezed
sealed class DownloadStatus with _$DownloadStatus {
  factory queued() = DownloadStatusInQueue;
  factory downloading({required double progress}) = DownloadStatusDownloading;
  factory downloaded() = DownloadStatusDownloaded;
  factory failed({required double progress}) = DownloadStatusFailed;
  factory paused({required double progress}) = DownloadStatusPaused;
}
