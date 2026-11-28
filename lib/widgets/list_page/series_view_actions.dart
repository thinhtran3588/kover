import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/riverpod/providers/list_view_options.dart';
import 'package:kover/widgets/list_page/list_layout_toggle_button.dart';
import 'package:kover/widgets/list_page/sort_options_menu.dart';
import 'package:material_ui/material_ui.dart';

/// The layout toggle and sort menu of the Kavita list of [scope].
class SeriesViewActions extends ConsumerWidget {
  final ViewScope scope;

  const SeriesViewActions({super.key, required this.scope});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(seriesViewProvider(scope));
    final notifier = ref.read(seriesViewProvider(scope).notifier);

    return Row(
      mainAxisSize: .min,
      children: [
        ListLayoutToggleButton(
          isGrid: view.isGrid,
          onPressed: () => notifier.update(view.copyWith(isGrid: !view.isGrid)),
        ),
        UnorderedSortMenu(
          sortDirection: view.direction,
          onSortDirectionChanged: (value) =>
              notifier.update(view.copyWith(direction: value)),
          orderBy: view.orderBy,
          onOrderByChanged: (value) =>
              notifier.update(view.copyWith(orderBy: value)),
          hideRead: view.hideRead,
          onHideReadChanged: (value) =>
              notifier.update(view.copyWith(hideRead: value)),
          downloadedOnly: view.downloadedOnly,
          onDownloadedOnlyChanged: (value) =>
              notifier.update(view.copyWith(downloadedOnly: value)),
        ),
      ],
    );
  }
}
