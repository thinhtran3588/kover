import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/models/enums/format.dart';
import 'package:kover/models/local_book_model.dart';
import 'package:kover/utils/constants/layout_constants.dart';
import 'package:material_ui/material_ui.dart';

Future<void> showBookInfoSheet(BuildContext context, LocalBookModel book) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _BookInfoSheet(book: book),
  );
}

class _BookInfoSheet extends StatelessWidget {
  final LocalBookModel book;

  const _BookInfoSheet({required this.book});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final localizations = MaterialLocalizations.of(context);

    final rows = [
      if (book.author != null) (l.author, book.author!),
      (l.bookFormat, _formatName(book.format)),
      (l.bookFileName, book.fileName),
      (l.bookFileSize, _formatSize(book.fileSize)),
      (
        l.bookSource,
        switch (book.source) {
          .device => l.sourceDevice,
          .googleDrive => l.sourceGoogleDrive,
        },
      ),
      (l.dateAdded, localizations.formatMediumDate(book.created)),
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const .symmetric(horizontal: LayoutConstants.mediumPadding),
        child: Column(
          crossAxisAlignment: .start,
          mainAxisSize: .min,
          children: [
            Text(book.title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: LayoutConstants.smallPadding),
            for (final (label, value) in rows)
              ListTile(
                contentPadding: .zero,
                title: Text(label),
                subtitle: value.isEmpty ? null : Text(value),
              ),
          ],
        ),
      ),
    );
  }

  static String _formatName(Format format) => switch (format) {
    .epub => 'EPUB',
    .pdf => 'PDF',
    .archive => 'CBZ',
    _ => '',
  };

  static String _formatSize(int bytes) {
    const mb = 1024 * 1024;
    return bytes >= mb
        ? '${(bytes / mb).toStringAsFixed(1)} MB'
        : '${(bytes / 1024).ceil()} KB';
  }
}
