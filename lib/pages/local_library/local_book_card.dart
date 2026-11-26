import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/models/local_book_model.dart';
import 'package:kover/pages/local_library/book_info_sheet.dart';
import 'package:kover/riverpod/providers/local_library.dart';
import 'package:kover/riverpod/providers/router.dart';
import 'package:kover/riverpod/repository/local_library_repository.dart';
import 'package:kover/utils/constants/kover_icons.dart';
import 'package:kover/utils/constants/layout_constants.dart';
import 'package:kover/widgets/cards/cover_card.dart';
import 'package:kover/widgets/cards/cover_image.dart';
import 'package:kover/widgets/context_menu/actions_menu.dart';
import 'package:kover/widgets/util/async_value.dart';
import 'package:material_ui/material_ui.dart';

/// Opens the on-device book [id] in the reader.
void openLocalBook(BuildContext context, int id) {
  // Local books are addressed by their negated id, see `LocalBookIds`.
  ReaderRoute(seriesId: -id, chapterId: -id, readingListId: null).push(context);
}

class LocalBookCard extends ConsumerWidget {
  final LocalBookModel book;

  const LocalBookCard({super.key, required this.book});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);

    return ActionsContextMenu(
      onMarkRead: book.progress < 1
          ? () => ref.read(localLibraryRepositoryProvider).markRead(book.id)
          : null,
      onMarkUnread: book.pagesRead > 0
          ? () => ref.read(localLibraryRepositoryProvider).markUnread(book.id)
          : null,
      onAddWantToRead: book.isFavorite
          ? null
          : () => ref
                .read(localLibraryRepositoryProvider)
                .setFavorite(book.id, true),
      onRemoveWantToRead: book.isFavorite
          ? () => ref
                .read(localLibraryRepositoryProvider)
                .setFavorite(book.id, false)
          : null,
      extraEntries: [
        MenuItem(
          label: Text(l.bookInfo),
          icon: const Icon(KoverIcons.info),
          onSelected: (_) => showBookInfoSheet(context, book),
        ),
        MenuItem(
          label: Text(l.deleteBook),
          icon: const Icon(KoverIcons.trash),
          onSelected: (_) => _confirmDelete(context, ref),
        ),
      ],
      child: CoverCard(
        title: book.title,
        icon: Icon(
          switch (book.format) {
            .epub => KoverIcons.epubFormat,
            .archive => KoverIcons.archiveFormat,
            .image => KoverIcons.imageFormat,
            .pdf => KoverIcons.pdfFormat,
            _ => KoverIcons.unknownFormat,
          },
          size: LayoutConstants.smallIcon,
        ),
        progress: book.progress,
        coverImage: Async(
          asyncValue: ref.watch(localBookCoverProvider(book.id)),
          data: (image) => PlaceholderCoverImage(image: image),
          loading: () => const LoadingCover(),
        ),
        downloadStatusIcon: book.source == .googleDrive
            ? const Card(
                child: Padding(
                  padding: LayoutConstants.smallEdgeInsets,
                  child: Icon(
                    KoverIcons.cloud,
                    size: LayoutConstants.smallIcon,
                  ),
                ),
              )
            : null,
        actionLabel: book.pagesRead > 0 ? l.continueReading : l.read,
        actionDisabled: false,
        onTap: () => openLocalBook(context, book.id),
        onActionTap: () => openLocalBook(context, book.id),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.deleteBook),
        content: Text(l.deleteBookConfirm(book.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.deleteBook),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await ref.read(localLibraryRepositoryProvider).delete(book.id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l.bookDeleted(book.title))));
  }
}
