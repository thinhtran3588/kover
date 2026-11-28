import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:kover/riverpod/providers/google_drive_auth.dart';
import 'package:kover/sync/google_drive_operations.dart';
import 'package:kover/utils/cancellation_token.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'google_drive_repository.g.dart';

@Riverpod(keepAlive: true)
GoogleDriveRepository googleDriveRepository(Ref ref) {
  return GoogleDriveRepository(ref.read(googleDriveAuthProvider.notifier));
}

/// Browses and downloads from Google Drive. Each call uses a fresh client so
/// the access token is always current.
class GoogleDriveRepository {
  final GoogleDriveAuth _auth;

  GoogleDriveRepository(this._auth);

  Future<T> _run<T>(Future<T> Function(GoogleDriveOperations) action) async {
    final client = await _auth.authClient();
    try {
      return await action(GoogleDriveOperations(drive.DriveApi(client)));
    } finally {
      client.close();
    }
  }

  Future<DriveListing> list(
    String folderId, {
    String search = '',
    String? pageToken,
  }) {
    return _run(
      (ops) => ops.list(folderId, search: search, pageToken: pageToken),
    );
  }

  Future<void> download(
    String fileId,
    File target, {
    void Function(int received, int? total)? onProgress,
    CancellationToken? token,
  }) {
    return _run(
      (ops) => ops.download(
        fileId,
        target,
        onProgress: onProgress,
        token: token,
      ),
    );
  }
}
