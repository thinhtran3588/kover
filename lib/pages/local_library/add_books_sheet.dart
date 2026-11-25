import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/pages/local_library/local_book_card.dart';
import 'package:kover/riverpod/managers/local_import_manager.dart';
import 'package:kover/utils/constants/kover_icons.dart';
import 'package:kover/utils/constants/layout_constants.dart';
import 'package:material_ui/material_ui.dart';

/// The ways to add books to the on-device library.
enum AddBooksAction { importFiles }

/// Shows the sheet that lets the user choose how to add books, and returns
/// the chosen action.
Future<AddBooksAction?> showAddBooksSheet(BuildContext context) {
  return showModalBottomSheet<AddBooksAction>(
    context: context,
    showDragHandle: true,
    builder: (context) => const AddBooksSheet(),
  );
}

class AddBooksSheet extends StatelessWidget {
  const AddBooksSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: .min,
        children: [
          Padding(
            padding: const .only(
              left: LayoutConstants.mediumPadding,
              right: LayoutConstants.mediumPadding,
              bottom: LayoutConstants.smallPadding,
            ),
            child: Align(
              alignment: .centerStart,
              child: Text(
                l.addBooks,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(KoverIcons.importFiles),
            title: Text(l.importFiles),
            subtitle: Text(l.importFilesSubtitle),
            onTap: () => Navigator.of(context).pop(AddBooksAction.importFiles),
          ),
        ],
      ),
    );
  }
}

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
