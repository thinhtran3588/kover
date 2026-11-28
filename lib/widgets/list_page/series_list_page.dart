import 'package:kover/models/series_model.dart';
import 'package:kover/widgets/cards/series_card.dart';
import 'package:kover/widgets/list_page/entities_list_page.dart';
import 'package:kover/widgets/lists/list_entries/series_list_entry.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

class SeriesListPage extends StatelessWidget {
  final String title;
  final TextEditingController controller;
  final AsyncValue<List<SeriesModel>> series;
  final Widget? sortMenu;

  /// Whether to show the large app bar, see [EntitiesListPage.showAppBar].
  final bool showAppBar;

  /// Slivers shown between the filter field and the series.
  final List<Widget> headerSlivers;

  /// Whether to show the filter field, see [EntitiesListPage.showFilter].
  final bool showFilter;

  /// The layout owned by the caller, see [EntitiesListPage.isGrid].
  final bool? isGrid;

  /// Hides the read action button on the grid cards.
  final bool hideAction;

  /// Overrides the default series tap navigation.
  final void Function(SeriesModel series)? onSeriesTap;

  /// Adds a "Series details" entry to each entry's context menu.
  final void Function(SeriesModel series)? onViewDetails;

  const new({
    super.key,
    required this.title,
    required this.controller,
    required this.series,
    this.sortMenu,
    this.showAppBar = true,
    this.headerSlivers = const [],
    this.showFilter = true,
    this.isGrid,
    this.hideAction = false,
    this.onSeriesTap,
    this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    return EntitiesListPage(
      title: title,
      filterController: controller,
      items: series,
      sortMenu: sortMenu,
      showAppBar: showAppBar,
      headerSlivers: headerSlivers,
      showFilter: showFilter,
      isGrid: isGrid,
      gridBuilder: (context, series) => SeriesCard(
        key: ValueKey(series.id),
        seriesId: series.id,
        hideAction: hideAction,
        onTap: onSeriesTap == null ? null : () => onSeriesTap!(series),
        onViewDetails: onViewDetails == null
            ? null
            : () => onViewDetails!(series),
      ),
      listBuilder: (context, series) => SeriesListEntry(
        key: ValueKey(series.id),
        seriesId: series.id,
        onTap: onSeriesTap == null ? null : () => onSeriesTap!(series),
        onViewDetails: onViewDetails == null
            ? null
            : () => onViewDetails!(series),
      ),
    );
  }
}
