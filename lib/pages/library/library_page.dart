import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/models/enums/local_book_source.dart';
import 'package:kover/models/enums/reading_source.dart';
import 'package:kover/pages/home/sliver_dashboard.dart';
import 'package:kover/pages/local_library/local_library_page.dart';
import 'package:kover/pages/series_page/series_page.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:kover/riverpod/managers/download_manager/download_manager.dart';
import 'package:kover/riverpod/managers/sync_manager/sync_manager.dart';
import 'package:kover/riverpod/providers/router.dart';
import 'package:kover/riverpod/providers/settings/credentials.dart';
import 'package:kover/riverpod/providers/settings/general_settings.dart';
import 'package:kover/utils/constants/kover_icons.dart';
import 'package:kover/utils/constants/layout_constants.dart';
import 'package:kover/widgets/actions_app_bar/search_button.dart';
import 'package:kover/widgets/actions_app_bar/sync_button.dart';
import 'package:kover/widgets/list_page/series_view_actions.dart';
import 'package:kover/widgets/sources/source_gate.dart';
import 'package:kover/widgets/sources/source_tabs_scaffold.dart';
import 'package:kover/widgets/util/async_value.dart';
import 'package:material_ui/material_ui.dart';

/// The books of every reading source, one tab each.
class LibraryPage extends ConsumerWidget {
  final ReadingSource? source;

  const LibraryPage({super.key, this.source});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final loggedIn = ref.watch(loginStatusProvider) == .loggedIn;

    return Async(
      asyncValue: ref.watch(generalSettingsProvider),
      data: (settings) => SourceTabsScaffold(
        title: l.library,
        initialSource: source,
        tabActions: (source) => [
          SourceGate(
            source: source,
            fallback: const SizedBox.shrink(),
            child: switch (source) {
              .kavita => const SeriesViewActions(scope: .library),
              .googleDrive => const LocalViewActions(
                source: LocalBookSource.googleDrive,
                favoritesOnly: false,
              ),
              .device => const LocalViewActions(
                source: LocalBookSource.device,
                favoritesOnly: false,
              ),
            },
          ),
        ],
        actions: [const SearchButton(), if (loggedIn) const SyncButton()],
        savedSource: settings.librarySource,
        onSourceChanged: (value) =>
            ref.read(generalSettingsProvider.notifier).setLibrarySource(value),
        tabBuilder: (source) => SourceGate(
          source: source,
          child: switch (source) {
            .kavita => const _KavitaView(),
            .googleDrive => const LocalBooksView(
              source: LocalBookSource.googleDrive,
              showFilter: false,
            ),
            .device => const LocalBooksView(
              source: LocalBookSource.device,
              showFilter: false,
            ),
          },
        ),
      ),
    );
  }
}

/// The Kavita dashboard rows above the grid of all series.
class _KavitaView extends ConsumerWidget {
  const _KavitaView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);

    return RefreshIndicator(
      onRefresh: () => ref.read(syncManagerProvider.notifier).fullSync(),
      child: SeriesPage(
        title: l.allSeries,
        showAppBar: false,
        showFilter: false,
        viewScope: .library,
        headerSlivers: [
          const SliverToBoxAdapter(child: _KavitaLinks()),
          const SliverDashboard(),
          SliverPadding(
            padding: LayoutConstants.smallEdgeInsets,
            sliver: SliverToBoxAdapter(
              child: Padding(
                padding: const .symmetric(
                  horizontal: LayoutConstants.smallPadding,
                ),
                child: Text(
                  l.allSeries,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shortcuts to the Kavita pages that have no tab of their own.
class _KavitaLinks extends ConsumerWidget {
  const _KavitaLinks();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final isDownloading = ref.watch(
      downloadManagerProvider.select(
        (state) => state.value?.downloadQueue.isNotEmpty ?? false,
      ),
    );

    return SingleChildScrollView(
      scrollDirection: .horizontal,
      padding: LayoutConstants.smallEdgeInsets,
      child: Row(
        spacing: LayoutConstants.smallPadding,
        children: [
          ActionChip(
            avatar: const Icon(KoverIcons.library),
            label: Text(l.libraries),
            onPressed: () => const LibrariesRoute().push(context),
          ),
          ActionChip(
            avatar: const Icon(KoverIcons.collection),
            label: Text(l.collections),
            onPressed: () => const CollectionsRoute().push(context),
          ),
          ActionChip(
            avatar: const Icon(KoverIcons.readingList),
            label: Text(l.readingLists),
            onPressed: () => const ReadingListsRoute().push(context),
          ),
          ActionChip(
            avatar: const Icon(KoverIcons.bookmarkOn),
            label: Text(l.bookmarks),
            onPressed: () => const BookmarksRoute().push(context),
          ),
          ActionChip(
            avatar: isDownloading
                ? const Icon(KoverIcons.downloading)
                      .animate(onPlay: (controller) => controller.repeat())
                      .rotate(duration: 1500.ms)
                : const Icon(KoverIcons.download),
            label: Text(l.downloads),
            onPressed: () => const DownloadQueueRoute().push(context),
          ),
        ],
      ),
    );
  }
}
