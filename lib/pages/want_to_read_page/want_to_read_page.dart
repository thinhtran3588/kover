import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/models/enums/order_by_option.dart';
import 'package:kover/models/enums/sort_direction.dart';
import 'package:kover/riverpod/managers/sync_manager/sync_manager.dart';
import 'package:kover/riverpod/providers/list_view_options.dart';
import 'package:kover/riverpod/providers/want_to_read.dart';
import 'package:kover/widgets/list_page/series_list_page.dart';
import 'package:kover/widgets/list_page/sort_options_menu.dart';
import 'package:material_ui/material_ui.dart';

class WantToReadPageContent extends HookConsumerWidget {
  final bool showAppBar;
  final bool showFilter;

  /// When set, the layout and sort live in [seriesViewProvider] so the page
  /// header can show their controls instead of this page.
  final ViewScope? viewScope;

  const WantToReadPageContent({
    super.key,
    this.showAppBar = true,
    this.showFilter = true,
    this.viewScope,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final controller = useTextEditingController();
    final scope = viewScope;
    final view = scope == null ? null : ref.watch(seriesViewProvider(scope));
    final localOrderBy = useState(UnorderedSortOption.name);
    final localDirection = useState(SortDirection.ascending);
    final localHideRead = useState(false);
    final localDownloadedOnly = useState(false);
    final orderBy = view?.orderBy ?? localOrderBy.value;
    final sortDirection = view?.direction ?? localDirection.value;
    final hideRead = view?.hideRead ?? localHideRead.value;
    final downloadedOnly = view?.downloadedOnly ?? localDownloadedOnly.value;
    final series = ref.watch(
      wantToReadListProvider(
        query: controller.text,
        orderBy: orderBy,
        direction: sortDirection,
        hideRead: hideRead,
        downloadedOnly: downloadedOnly,
      ),
    );

    useListenable(controller);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncManagerProvider.notifier).syncLibraries();
    });

    return SeriesListPage(
      title: l.wantToRead,
      showAppBar: showAppBar,
      showFilter: showFilter,
      controller: controller,
      isGrid: view?.isGrid,
      sortMenu: scope != null
          ? null
          : UnorderedSortMenu(
              sortDirection: sortDirection,
              onSortDirectionChanged: (SortDirection newDirection) {
                localDirection.value = newDirection;
              },
              orderBy: orderBy,
              onOrderByChanged: (UnorderedSortOption newOrderBy) {
                localOrderBy.value = newOrderBy;
              },
              hideRead: hideRead,
              onHideReadChanged: (bool newHideRead) {
                localHideRead.value = newHideRead;
              },
              downloadedOnly: downloadedOnly,
              onDownloadedOnlyChanged: (bool value) {
                localDownloadedOnly.value = value;
              },
            ),
      series: series,
    );
  }
}
