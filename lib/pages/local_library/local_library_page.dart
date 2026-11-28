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
import 'package:kover/riverpod/providers/list_view_options.dart';
import 'package:kover/riverpod/providers/local_library.dart';
import 'package:kover/riverpod/providers/router.dart';
import 'package:kover/utils/constants/kover_icons.dart';
import 'package:kover/utils/constants/layout_constants.dart';
import 'package:kover/widgets/context_menu/context_menu_button.dart';
import 'package:kover/widgets/details/filter_input_field.dart';
import 'package:kover/widgets/list_page/list_layout_toggle_button.dart';
import 'package:kover/widgets/lists/adaptive_sliver_grid.dart';
import 'package:kover/widgets/util/async_value.dart';
import 'package:kover/widgets/util/sliver_adaptive_padding.dart';
import 'package:kover/widgets/util/sliver_bottom_padding.dart';
import 'package:material_ui/material_ui.dart';

/// The books of one [source]: imported files on this device, or books
/// downloaded from Google Drive. Works without a Kavita server.
class LocalBooksView extends HookConsumerWidget {
  final LocalBookSource source;
  final bool favoritesOnly;
  final bool showFilter;

  const LocalBooksView({
    super.key,
    required this.source,
    this.favoritesOnly = false,
    this.showFilter = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final books = ref.watch(
      localBooksProvider(source: source, favoritesOnly: favoritesOnly),
    );
    final progress = ref.watch(localImportProvider);
    final filterController = useTextEditingController();
    final view = ref.watch(
      localViewProvider(source, favoritesOnly),
    );

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
      floatingActionButton: favoritesOnly
          ? null
          // Lift the button above the floating navigation bar.
          : Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom,
              ),
              child: FloatingActionButton.extended(
                onPressed: isDevice && progress != null ? null : add,
                icon: Icon(
                  isDevice ? KoverIcons.importFiles : KoverIcons.cloud,
                ),
                label: Text(isDevice ? l.importFiles : l.browseGoogleDrive),
              ),
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
              favoritesOnly: favoritesOnly,
              showFilter: showFilter,
              filterController: filterController,
              view: view,
              onAdd: add,
            ),
          ),
          const SliverBottomPadding(),
        ],
      ),
    );
  }
}

/// The layout toggle and sort menu of the books of one local source tab.
class LocalViewActions extends ConsumerWidget {
  final LocalBookSource source;
  final bool favoritesOnly;

  const LocalViewActions({
    super.key,
    required this.source,
    required this.favoritesOnly,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final view = ref.watch(localViewProvider(source, favoritesOnly));
    final notifier = ref.read(
      localViewProvider(source, favoritesOnly).notifier,
    );

    return Row(
      mainAxisSize: .min,
      children: [
        ListLayoutToggleButton(
          isGrid: view.isGrid,
          onPressed: () => notifier.update(view.copyWith(isGrid: !view.isGrid)),
        ),
        ContextMenuButton(
          icon: const Icon(KoverIcons.sort),
          menu: ContextMenu(
            entries: [
              MenuHeader(text: l.sortBy),
              for (final (label, option) in [
                (l.lastRead, LocalSort.lastRead),
                (l.name, LocalSort.name),
                (l.dateAdded, LocalSort.dateAdded),
              ])
                MenuItem(
                  label: Text(label),
                  icon: view.sort == option
                      ? const Icon(KoverIcons.check)
                      : null,
                  onSelected: (_) =>
                      notifier.update(view.copyWith(sort: option)),
                ),
            ],
          ),
        ),
      ],
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
  final bool favoritesOnly;
  final bool showFilter;
  final TextEditingController filterController;
  final LocalViewState view;
  final VoidCallback onAdd;

  const _LibraryBody({
    required this.books,
    required this.source,
    required this.favoritesOnly,
    required this.showFilter,
    required this.filterController,
    required this.view,
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
        child: favoritesOnly
            ? const _NoFavorites()
            : _EmptyState(source: source, onAction: onAdd),
      );
    }

    final visible = books.where((book) {
      return query.isEmpty ||
          book.title.toLowerCase().contains(query) ||
          (book.author?.toLowerCase().contains(query) ?? false);
    }).toList();
    switch (view.sort) {
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
        !favoritesOnly &&
        query.isEmpty &&
        continueReading != null &&
        continueReading.isNotEmpty;

    return SliverSafeArea(
      top: false,
      bottom: false,
      sliver: SliverMainAxisGroup(
        slivers: [
          if (showFilter)
            SliverPadding(
              padding: const .fromLTRB(
                LayoutConstants.mediumPadding,
                LayoutConstants.mediumPadding,
                LayoutConstants.mediumPadding,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: FilterInputField(controller: filterController),
                    ),
                    LocalViewActions(
                      source: source,
                      favoritesOnly: favoritesOnly,
                    ),
                  ],
                ),
              ),
            )
          else
            const SliverToBoxAdapter(
              child: SizedBox(height: LayoutConstants.smallPadding),
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
          else if (view.isGrid)
            SliverPadding(
              padding: LayoutConstants.smallEdgeInsets,
              sliver: AdaptiveSliverGrid(
                itemCount: visible.length,
                builder: (context, index) => LocalBookCard(
                  key: ValueKey(visible[index].id),
                  book: visible[index],
                ),
              ),
            )
          else
            SliverAdaptivePadding(
              padding: LayoutConstants.smallEdgeInsets,
              sliver: SliverList.separated(
                itemBuilder: (context, index) => LocalBookCard(
                  key: ValueKey(visible[index].id),
                  book: visible[index],
                  asList: true,
                ),
                separatorBuilder: (context, index) => const SizedBox(
                  height: LayoutConstants.listSpacing,
                ),
                itemCount: visible.length,
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

class _NoFavorites extends StatelessWidget {
  const _NoFavorites();

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
              KoverIcons.wantToRead,
              size: LayoutConstants.largestIcon,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: LayoutConstants.mediumPadding),
            Text(
              l.noFavoritesTitle,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: .bold,
              ),
              textAlign: .center,
            ),
            const SizedBox(height: LayoutConstants.smallerPadding),
            Text(l.noFavoritesDescription, textAlign: .center),
          ],
        ),
      ),
    );
  }
}
