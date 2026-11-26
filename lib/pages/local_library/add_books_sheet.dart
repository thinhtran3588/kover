import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/pages/local_library/local_book_card.dart';
import 'package:kover/riverpod/managers/local_import_manager.dart';
import 'package:material_ui/material_ui.dart';

/// Lets the user pick files, imports them and reports the outcome in a
/// snackbar. A single imported book can be opened straight from it.
Future<void> importBooks(BuildContext context, WidgetRef ref) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);

  final summary = await ref.read(localImportProvider.notifier).pickAndImport();
  if (summary == null || summary.isEmpty) return;

  final parts = [
    if (summary.importedIds.isNotEmpty)
      l.importedBooks(summary.importedIds.length),
    if (summary.duplicates > 0) l.importSkippedDuplicates(summary.duplicates),
    if (summary.unsupported > 0)
      l.importSkippedUnsupported(summary.unsupported),
    if (summary.failed > 0) l.importFailedCount(summary.failed),
  ];

  final openId = summary.importedIds.length == 1
      ? summary.importedIds.single
      : null;

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(parts.join(' · ')),
        action: openId == null
            ? null
            : SnackBarAction(
                label: l.open,
                onPressed: () {
                  if (!context.mounted) return;
                  openLocalBook(context, openId);
                },
              ),
      ),
    );
}
