import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/models/enums/local_book_source.dart';
import 'package:kover/models/local_book_model.dart';
import 'package:kover/pages/home/home_section.dart';
import 'package:kover/pages/local_library/add_books_sheet.dart';
import 'package:kover/pages/local_library/local_book_card.dart';
import 'package:kover/riverpod/managers/local_import_manager.dart';
import 'package:kover/riverpod/providers/local_library.dart';
import 'package:kover/riverpod/providers/router.dart';
import 'package:kover/utils/constants/kover_icons.dart';
import 'package:kover/utils/constants/layout_constants.dart';
import 'package:kover/widgets/context_menu/context_menu_button.dart';
import 'package:kover/widgets/details/filter_input_field.dart';
import 'package:kover/widgets/lists/adaptive_sliver_grid.dart';
import 'package:kover/widgets/util/async_value.dart';
import 'package:kover/widgets/util/sliver_bottom_padding.dart';
import 'package:material_ui/material_ui.dart';

enum _LocalSort { lastRead, name, dateAdded }

/// The books of one [source]: imported files on this device, or books
/// downloaded from Google Drive. Works without a Kavita server.
class LocalBooksView extends HookConsumerWidget {
  final LocalBookSource source;
  final bool favoritesOnly;

  const LocalBooksView({
    super.key,
    required this.source,
    this.favoritesOnly = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final books = ref.watch(
      localBooksProvider(source: source, favoritesOnly: favoritesOnly),
    );
    final progress = ref.watch(localImportProvider);
    final filterController = useTextEditingController();
    final sort = useState(_LocalSort.lastRead);

    final isDevice = source == LocalBookSource.device;
    Future<void> add() async {
      if (isDevice) {
        await importBooks(context, ref);
      } else {
        await const GoogleDriveRoute().push<void>(context);
      }
    }

    return Scaffold(
      extendBody: true,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: isDevice && progress != null ? null : add,
        icon: Icon(isDevice ? KoverIcons.importFiles : KoverIcons.cloud),
        label: Text(isDevice ? l.importFiles : l.browseGoogleDrive),
      ),
      body: CustomScrollView(
        keyboardDismissBehavior: .onDrag,
        slivers: [
          if (isDevice)
            SliverToBoxAdapter(child: _ImportProgress(progress: progress)),
          AsyncSliver(
            asyncValue: books,
            data: (books) => _LibraryBody(
              books: books,
              source: source,
              filterController: filterController,
              sort: sort.value,
              onSort: (value) => sort.value = value,
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
  final LocalBookSource source;
  final TextEditingController filterController;
  final _LocalSort sort;
  final ValueChanged<_LocalSort> onSort;
  final VoidCallback onAdd;

  const _LibraryBody({
    required this.books,
    required this.source,
    required this.filterController,
    required this.sort,
    required this.onSort,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);

    final query = useValueListenable(filterController).text
        .trim()
        .toLowerCase();
    final continueReading = ref
        .watch(localContinueReadingProvider)
        .value
        ?.where((book) => book.source == source)
        .toList();

    if (books.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _EmptyState(source: source, onAction: onAdd),
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
              child: Row(
                children: [
                  Expanded(
                    child: FilterInputField(controller: filterController),
                  ),
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
                            icon: sort == option
                                ? const Icon(KoverIcons.check)
                                : null,
                            onSelected: (_) => onSort(option),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
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
  final LocalBookSource source;
  final VoidCallback onAction;

  const _EmptyState({required this.source, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDevice = source == LocalBookSource.device;

    return Center(
      child: Padding(
        padding: LayoutConstants.mediumEdgeInsets,
        child: Column(
          mainAxisSize: .min,
          children: [
            Icon(
              isDevice ? KoverIcons.device : KoverIcons.cloud,
              size: LayoutConstants.largestIcon,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: LayoutConstants.mediumPadding),
            Text(
              isDevice ? l.localLibraryEmptyTitle : l.driveLibraryEmptyTitle,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: .bold,
              ),
              textAlign: .center,
            ),
            const SizedBox(height: LayoutConstants.smallerPadding),
            Text(
              isDevice
                  ? l.localLibraryEmptyDescription
                  : l.driveLibraryEmptyDescription,
              textAlign: .center,
            ),
            const SizedBox(height: LayoutConstants.mediumPadding),
            FilledButton.icon(
              onPressed: onAction,
              icon: Icon(isDevice ? KoverIcons.importFiles : KoverIcons.cloud),
              label: Text(isDevice ? l.importFiles : l.browseGoogleDrive),
            ),
          ],
        ),
      ),
    );
  }
}
