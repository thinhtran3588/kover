import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:kover/models/drive_item_model.dart';
import 'package:kover/utils/cancellation_token.dart';

/// One page of Drive items.
typedef DriveListing = ({List<DriveItemModel> items, String? nextPageToken});

/// Wraps the Drive API. Everything is read-only.
class GoogleDriveOperations {
  /// The pseudo folder id of the "Shared with me" view.
  static const sharedFolderId = 'shared';

  static const _folderMimeType = 'application/vnd.google-apps.folder';

  static const _typeFilter =
      "mimeType = '$_folderMimeType' or "
      "mimeType = 'application/epub+zip' or "
      "mimeType = 'application/pdf' or "
      "mimeType = 'application/zip' or "
      "mimeType = 'application/x-cbz' or "
      "mimeType = 'application/vnd.comicbook+zip' or "
      "name contains '.cbz' or name contains '.epub'";

  final drive.DriveApi _api;

  GoogleDriveOperations(this._api);

  /// Escapes [text] for use inside a single quoted Drive query string.
  static String escape(String text) =>
      text.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  static String folderQuery(String folderId) =>
      "'${escape(folderId)}' in parents and trashed = false and ($_typeFilter)";

  static String sharedQuery() =>
      'sharedWithMe = true and trashed = false and ($_typeFilter)';

  static String searchQuery(String text) =>
      "name contains '${escape(text)}' and trashed = false and ($_typeFilter)";

  /// Lists the folder [folderId], [sharedFolderId], or the files matching
  /// [search] when it is not empty.
  Future<DriveListing> list(
    String folderId, {
    String search = '',
    String? pageToken,
  }) async {
    final query = search.isNotEmpty
        ? searchQuery(search)
        : folderId == sharedFolderId
        ? sharedQuery()
        : folderQuery(folderId);

    final result = await _api.files.list(
      q: query,
      orderBy: 'folder,name_natural',
      pageSize: 100,
      pageToken: pageToken,
      $fields: 'nextPageToken, files(id,name,mimeType,size,modifiedTime)',
      supportsAllDrives: true,
      includeItemsFromAllDrives: true,
    );

    return (
      items: filterItems(result.files ?? const []),
      nextPageToken: result.nextPageToken,
    );
  }

  /// Maps Drive files to items, dropping the files that are not supported
  /// books. Folders always pass.
  static List<DriveItemModel> filterItems(List<drive.File> files) {
    return [
      for (final file in files)
        if (file.id != null && file.name != null)
          DriveItemModel(
            id: file.id!,
            name: file.name!,
            isFolder: file.mimeType == _folderMimeType,
            size: int.tryParse(file.size ?? ''),
            modifiedTime: file.modifiedTime,
          ),
    ].where((item) => item.isFolder || item.format != null).toList();
  }

  /// Streams the content of [fileId] into [target].
  Future<void> download(
    String fileId,
    File target, {
    void Function(int received, int? total)? onProgress,
    CancellationToken? token,
  }) async {
    final media = await _api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
      supportsAllDrives: true,
    ) as drive.Media;

    final sink = target.openWrite();
    var received = 0;
    try {
      await for (final chunk in media.stream) {
        token?.throwIfCancelled();
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, media.length);
      }
    } finally {
      await sink.close();
    }
  }
}
