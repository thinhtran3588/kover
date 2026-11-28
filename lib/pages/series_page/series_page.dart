import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/models/enums/order_by_option.dart';
import 'package:kover/models/enums/sort_direction.dart';
import 'package:kover/riverpod/providers/collections.dart';
import 'package:kover/riverpod/providers/library.dart';
import 'package:kover/riverpod/providers/list_view_options.dart';
import 'package:kover/riverpod/providers/series.dart';
import 'package:kover/widgets/list_page/series_list_page.dart';
import 'package:kover/widgets/list_page/sort_options_menu.dart';
import 'package:kover/widgets/util/async_value.dart';
import 'package:material_ui/material_ui.dart';

class LibrarySeriesPage extends ConsumerWidget {
  final int libraryId;

  const LibrarySeriesPage({
    super.key,
    required this.libraryId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider(libraryId: libraryId));
    return Async(
      asyncValue: library,
      data: (data) {
        return SeriesPage(
          title: data.name,
          libraryId: data.id,
        );
      },
    );
  }
}

class CollectionSeriesPage extends ConsumerWidget {
  final int collectionId;

  const CollectionSeriesPage({
    super.key,
    required this.collectionId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collection = ref.watch(
      collectionProvider(collectionId: collectionId),
    );
    return Async(
      asyncValue: collection,
      data: (data) {
        return SeriesPage(
          title: data.title,
          collectionId: data.id,
        );
      },
    );
  }
}

class SeriesPage extends HookConsumerWidget {
  final String title;
  final String? subtitle;
  final int? libraryId;
  final int? collectionId;

  /// Whether to show the large app bar. Disabled when embedded in tabs.
  final bool showAppBar;

  /// Slivers shown between the filter field and the series, hidden while the
  /// filter text is not empty.
  final List<Widget> headerSlivers;

  /// Whether to show the filter field.
  final bool showFilter;

  /// When set, the layout and sort live in [seriesViewProvider] so the page
  /// header can show their controls instead of this page.
  final ViewScope? viewScope;

  const SeriesPage({
    super.key,
    required this.title,
    this.subtitle,
    this.libraryId,
    this.collectionId,
    this.showAppBar = true,
    this.headerSlivers = const [],
    this.showFilter = true,
    this.viewScope,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = viewScope;
    final view = scope == null ? null : ref.watch(seriesViewProvider(scope));
    final localOrderBy = useState(UnorderedSortOption.name);
    final sortDirection = useState(SortDirection.ascending);
    final localHideRead = useState(false);
    final localDownloadedOnly = useState(false);
    final orderBy = view?.orderBy ?? localOrderBy.value;
    final direction = view?.direction ?? sortDirection.value;
    final hideRead = view?.hideRead ?? localHideRead.value;
    final downloadedOnly = view?.downloadedOnly ?? localDownloadedOnly.value;
    final controller = useTextEditingController();

    final query = ref.watch(
      filterSeriesProvider(
        controller.text,
        libraryId: libraryId,
        collectionId: collectionId,
        orderBy: orderBy,
        direction: direction,
        hideRead: hideRead,
        downloadedOnly: downloadedOnly,
      ),
    );

    useListenable(controller);

    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: SeriesListPage(
        title: title,
        showAppBar: showAppBar,
        showFilter: showFilter,
        headerSlivers: controller.text.isEmpty ? headerSlivers : const [],
        controller: controller,
        isGrid: view?.isGrid,
        sortMenu: scope != null
            ? null
            : UnorderedSortMenu(
                sortDirection: direction,
                onSortDirectionChanged: (onSort) =>
                    sortDirection.value = onSort,
                orderBy: orderBy,
                onOrderByChanged: (onOrder) => localOrderBy.value = onOrder,
                hideRead: hideRead,
                onHideReadChanged: (onHideRead) =>
                    localHideRead.value = onHideRead,
                downloadedOnly: downloadedOnly,
                onDownloadedOnlyChanged: (value) =>
                    localDownloadedOnly.value = value,
              ),
        series: query,
      ),
    );
  }
}
