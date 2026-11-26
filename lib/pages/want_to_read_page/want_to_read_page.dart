import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/models/enums/order_by_option.dart';
import 'package:kover/models/enums/sort_direction.dart';
import 'package:kover/riverpod/managers/sync_manager/sync_manager.dart';
import 'package:kover/riverpod/providers/want_to_read.dart';
import 'package:kover/widgets/list_page/series_list_page.dart';
import 'package:kover/widgets/list_page/sort_options_menu.dart';
import 'package:material_ui/material_ui.dart';

class WantToReadPageContent extends HookConsumerWidget {
  final bool showAppBar;

  const WantToReadPageContent({super.key, this.showAppBar = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final controller = useTextEditingController();
    final orderBy = useState(UnorderedSortOption.name);
    final sortDirection = useState(SortDirection.ascending);
    final hideRead = useState(false);
    final downloadedOnly = useState(false);
    final series = ref.watch(
      wantToReadListProvider(
        query: controller.text,
        orderBy: orderBy.value,
        direction: sortDirection.value,
        hideRead: hideRead.value,
        downloadedOnly: downloadedOnly.value,
      ),
    );

    useListenable(controller);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncManagerProvider.notifier).syncLibraries();
    });

    return SeriesListPage(
      title: l.wantToRead,
      showAppBar: showAppBar,
      controller: controller,
      sortMenu: UnorderedSortMenu(
        sortDirection: sortDirection.value,
        onSortDirectionChanged: (SortDirection newDirection) {
          sortDirection.value = newDirection;
        },
        orderBy: orderBy.value,
        onOrderByChanged: (UnorderedSortOption newOrderBy) {
          orderBy.value = newOrderBy;
        },
        hideRead: hideRead.value,
        onHideReadChanged: (bool newHideRead) {
          hideRead.value = newHideRead;
        },
        downloadedOnly: downloadedOnly.value,
        onDownloadedOnlyChanged: (bool value) {
          downloadedOnly.value = value;
        },
      ),
      series: series,
    );
  }
}
