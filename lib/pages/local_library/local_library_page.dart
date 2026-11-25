import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/models/local_book_model.dart';
import 'package:kover/pages/home/home_section.dart';
import 'package:kover/pages/local_library/add_books_sheet.dart';
import 'package:kover/pages/local_library/local_book_card.dart';
import 'package:kover/riverpod/managers/local_import_manager.dart';
import 'package:kover/riverpod/providers/local_library.dart';
import 'package:kover/utils/constants/kover_icons.dart';
import 'package:kover/utils/constants/layout_constants.dart';
import 'package:kover/widgets/context_menu/context_menu_button.dart';
import 'package:kover/widgets/details/filter_input_field.dart';
import 'package:kover/widgets/lists/adaptive_sliver_grid.dart';
import 'package:kover/widgets/util/async_value.dart';
import 'package:kover/widgets/util/sliver_bottom_padding.dart';
import 'package:material_ui/material_ui.dart';

enum _LocalSort { lastRead, name, dateAdded }

/// The books imported on this device. Works without a Kavita server.
class LocalLibraryPage extends HookConsumerWidget {
  const LocalLibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final books = ref.watch(localBooksProvider());
    final progress = ref.watch(localImportProvider);
    final filterController = useTextEditingController();
    final sort = useState(_LocalSort.lastRead);

    Future<void> add() async {
      final action = await showAddBooksSheet(context);
      if (action == null || !context.mounted) return;

      switch (action) {
        case .importFiles:
          await importBooks(context, ref);
      }
    }

    return Scaffold(
      extendBody: true,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: progress == null ? add : null,
        icon: const Icon(KoverIcons.importFiles),
        label: Text(l.addBooks),
      ),
      body: CustomScrollView(
        keyboardDismissBehavior: .onDrag,
        slivers: [
          SliverAppBar.large(
            title: Text(l.onThisDevice),
            actionsPadding: const .symmetric(
              horizontal: LayoutConstants.smallPadding,
            ),
            actions: [
              ContextMenuButton(
                icon: const Icon(KoverIcons.sort),
                menu: ContextMenu(
                  entries: [
                    MenuHeader(text: l.sortBy),
                    for (final (label, option) in [
                      (l.lastRead, _LocalSort.lastRead),
                      (l.name, _LocalSort.name),
                      (l.dateAdded, _LocalSort.dateAdded),
                    ])
                      MenuItem(
                        label: Text(label),
                        icon: sort.value == option
                            ? const Icon(KoverIcons.check)
                            : null,
                        onSelected: (_) => sort.value = option,
                      ),
                  ],
                ),
              ),
            ],
          ),
          SliverToBoxAdapter(child: _ImportProgress(progress: progress)),
          AsyncSliver(
            asyncValue: books,
            data: (books) => _LibraryBody(
              books: books,
              filterController: filterController,
              sort: sort.value,
              onAdd: add,
            ),
          ),
          const SliverBottomPadding(),
        ],
      ),
    );
  }
}

class _ImportProgress extends StatelessWidget {
  final LocalImportProgress? progress;

  const _ImportProgress({required this.progress});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final progress = this.progress;

    return AnimatedSize(
      duration: LayoutConstants.pageSlideDuration,
      alignment: .topCenter,
      child: progress == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const .symmetric(
                horizontal: LayoutConstants.mediumPadding,
                vertical: LayoutConstants.smallPadding,
              ),
              child: Column(
                crossAxisAlignment: .start,
                spacing: LayoutConstants.smallPadding,
                children: [
                  Text(l.importingProgress(progress.done, progress.total)),
                  LinearProgressIndicator(
                    value: progress.done / progress.total,
                  ),
                ],
              ),
            ),
    );
  }
}

class _LibraryBody extends HookConsumerWidget {
  final List<LocalBookModel> books;
  final TextEditingController filterController;
  final _LocalSort sort;
  final VoidCallback onAdd;

  const _LibraryBody({
    required this.books,
    required this.filterController,
    required this.sort,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);

    final query = useValueListenable(filterController).text
        .trim()
        .toLowerCase();
    final continueReading = ref.watch(localContinueReadingProvider).value;

    if (books.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _EmptyState(onImport: onAdd),
      );
    }

    final visible = books.where((book) {
      return query.isEmpty ||
          book.title.toLowerCase().contains(query) ||
          (book.author?.toLowerCase().contains(query) ?? false);
    }).toList();
    switch (sort) {
      case .lastRead:
        break; // The database already orders by last read, then date added.
      case .name:
        visible.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case .dateAdded:
        visible.sort((a, b) => b.created.compareTo(a.created));
    }

    final showContinue =
        query.isEmpty && continueReading != null && continueReading.isNotEmpty;

    return SliverSafeArea(
      top: false,
      bottom: false,
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverPadding(
            padding: const .symmetric(
              horizontal: LayoutConstants.mediumPadding,
            ),
            sliver: SliverToBoxAdapter(
              child: FilterInputField(controller: filterController),
            ),
          ),
          if (showContinue) ...[
            HomeSection.localBooks(
              title: l.continueReading,
              items: continueReading,
            ),
            SliverPadding(
              padding: LayoutConstants.smallEdgeInsets,
              sliver: SliverToBoxAdapter(
                child: Padding(
                  padding: const .symmetric(
                    horizontal: LayoutConstants.smallPadding,
                  ),
                  child: Text(
                    l.allBooks,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
              ),
            ),
          ],
          if (visible.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: LayoutConstants.largeEdgeInsets,
                child: Text(
                  l.noMatchingBooks,
                  textAlign: .center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            )
          else
            SliverPadding(
              padding: LayoutConstants.smallEdgeInsets,
              sliver: AdaptiveSliverGrid(
                itemCount: visible.length,
                builder: (context, index) => LocalBookCard(
                  key: ValueKey(visible[index].id),
                  book: visible[index],
                ),
              ),
            ),
          // Keeps the last row clear of the floating action button.
          const SliverToBoxAdapter(child: SizedBox(height: 72)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onImport;

  const _EmptyState({required this.onImport});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: LayoutConstants.mediumEdgeInsets,
        child: Column(
          mainAxisSize: .min,
          children: [
            Icon(
              KoverIcons.device,
              size: LayoutConstants.largestIcon,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: LayoutConstants.mediumPadding),
            Text(
              l.localLibraryEmptyTitle,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: .bold,
              ),
              textAlign: .center,
            ),
            const SizedBox(height: LayoutConstants.smallerPadding),
            Text(
              l.localLibraryEmptyDescription,
              textAlign: .center,
            ),
            const SizedBox(height: LayoutConstants.mediumPadding),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(KoverIcons.importFiles),
              label: Text(l.importFiles),
            ),
          ],
        ),
      ),
    );
  }
}
