import 'package:file_picker/file_picker.dart';
import 'package:kover/riverpod/repository/local_library_repository.dart';
import 'package:kover/utils/local_books/book_file_format.dart';
import 'package:kover/utils/safe_platform.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'local_import_manager.g.dart';

/// The progress of a running import: [done] out of [total] files.
typedef LocalImportProgress = ({int total, int done});

/// The outcome of importing a batch of files.
class LocalImportSummary {
  final List<int> importedIds = [];
  int duplicates = 0;
  int unsupported = 0;
  int failed = 0;

  bool get isEmpty =>
      importedIds.isEmpty && duplicates == 0 && unsupported == 0 && failed == 0;
}

/// Imports files into the on-device library. The state is the progress of the
/// running import, or null when idle.
@Riverpod(keepAlive: true)
class LocalImport extends _$LocalImport {
  @override
  LocalImportProgress? build() => null;

  /// Lets the user pick files and imports them one at a time.
  ///
  /// Returns null when nothing was picked or an import is already running.
  Future<LocalImportSummary?> pickAndImport() async {
    if (state != null) return null;

    final picked = await FilePicker.pickFiles(
      // `cbz` has no registered MIME type on many Android devices, so the
      // picker cannot filter by it. Unsupported files are skipped below.
      type: SafePlatform.isAndroid ? FileType.any : FileType.custom,
      allowedExtensions: SafePlatform.isAndroid ? null : supportedExtensions,
    );
    final files = picked.where((file) => file.path != null).toList();
    if (files.isEmpty) return null;

    final summary = LocalImportSummary();
    state = (total: files.length, done: 0);
    try {
      final repository = ref.read(localLibraryRepositoryProvider);
      for (final (index, file) in files.indexed) {
        switch (await repository.importFile(
          file.path!,
          displayName: file.name,
        )) {
          case LocalImportImported(:final id):
            summary.importedIds.add(id);
          case LocalImportDuplicate():
            summary.duplicates++;
          case LocalImportUnsupported():
            summary.unsupported++;
          case LocalImportFailed():
            summary.failed++;
        }
        state = (total: files.length, done: index + 1);
      }
    } finally {
      state = null;
      if (SafePlatform.isMobile) await FilePicker.clearTemporaryFiles();
    }

    return summary;
  }
}
