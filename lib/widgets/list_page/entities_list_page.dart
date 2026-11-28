import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/utils/constants/layout_constants.dart';
import 'package:kover/widgets/details/filter_input_field.dart';
import 'package:kover/widgets/list_page/list_layout_toggle_button.dart';
import 'package:kover/widgets/lists/adaptive_sliver_grid.dart';
import 'package:kover/widgets/util/async_value.dart';
import 'package:kover/widgets/util/sliver_adaptive_padding.dart';
import 'package:kover/widgets/util/sliver_bottom_padding.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

class EntitiesListPage<T> extends HookWidget {
  final String title;
  final Widget? sortMenu;
  final TextEditingController filterController;
  final AsyncValue<List<T>> items;
  final Widget Function(BuildContext context, T item) gridBuilder;
  final Widget Function(BuildContext context, T item) listBuilder;

  /// Whether to show the large app bar with [title]. When false the list
  /// toggle and [sortMenu] move next to the filter field.
  final bool showAppBar;

  /// Slivers shown between the filter field and the items.
  final List<Widget> headerSlivers;

  /// Whether to show the filter field.
  final bool showFilter;

  /// The grid or list layout when owned by the caller, which then shows its
  /// own toggle. When null the page keeps the state and shows the toggle.
  final bool? isGrid;

  /// Shown instead of the items when there are none. Reads "No results" while
  /// the filter has text.
  final String? emptyMessage;

  const new({
    super.key,
    required this.title,
    required this.filterController,
    required this.items,
    required this.gridBuilder,
    required this.listBuilder,
    this.sortMenu,
    this.showAppBar = true,
    this.headerSlivers = const [],
    this.showFilter = true,
    this.isGrid,
    this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    final emptyMessage = this.emptyMessage;

    return _EntitiesListPage(
      title: title,
      filterController: filterController,
      sortMenu: sortMenu,
      showAppBar: showAppBar,
      headerSlivers: headerSlivers,
      showFilter: showFilter,
      externalIsGrid: isGrid,
      sliver: AsyncSliver(
        asyncValue: items,
        data: (data) {
          if (data.isEmpty && emptyMessage != null) {
            return SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: LayoutConstants.largeEdgeInsets,
                  child: Text(
                    filterController.text.isEmpty
                        ? emptyMessage
                        : AppLocalizations.of(context).noSearchResults,
                    textAlign: .center,
                  ),
                ),
              ),
            );
          }
          return _SliverEntitiesListBody<T>(
            items: data,
            gridBuilder: gridBuilder,
            listBuilder: listBuilder,
          );
        },
      ),
    );
  }
}

class _EntitiesListPage extends HookWidget {
  final String title;
  final Widget? sortMenu;
  final TextEditingController filterController;
  final Widget sliver;
  final bool showAppBar;
  final List<Widget> headerSlivers;
  final bool showFilter;
  final bool? externalIsGrid;

  const new({
    required this.title,
    required this.filterController,
    required this.sliver,
    required this.showAppBar,
    required this.headerSlivers,
    required this.showFilter,
    required this.externalIsGrid,
    this.sortMenu,
  });

  @override
  Widget build(BuildContext context) {
    final localIsGrid = useState(true);
    final isGrid = externalIsGrid ?? localIsGrid.value;
    final toggle = ListLayoutToggleButton(
      isGrid: isGrid,
      onPressed: () {
        localIsGrid.value = !localIsGrid.value;
      },
    );
    final filter = showFilter
        ? FilterInputField(controller: filterController)
        : null;

    return CustomScrollView(
      keyboardDismissBehavior: .onDrag,
      slivers: [
        if (showAppBar)
          SliverAppBar.large(
            title: Text(title),
            actionsPadding: const EdgeInsets.symmetric(
              horizontal: LayoutConstants.smallPadding,
            ),
            actions: [if (externalIsGrid == null) toggle, ?sortMenu],
          ),
        SliverSafeArea(
          top: false,
          bottom: false,
          sliver: SliverMainAxisGroup(
            slivers: [
              if (!showAppBar &&
                  filter == null &&
                  externalIsGrid != null &&
                  sortMenu == null)
                const SliverToBoxAdapter(
                  child: SizedBox(height: LayoutConstants.smallPadding),
                )
              else if (filter != null || !showAppBar)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    LayoutConstants.mediumPadding,
                    showAppBar ? 0 : LayoutConstants.mediumPadding,
                    LayoutConstants.mediumPadding,
                    0,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: showAppBar
                        ? filter
                        : Row(
                            mainAxisAlignment: .end,
                            children: [
                              ?(filter == null
                                  ? null
                                  : Expanded(child: filter)),
                              if (externalIsGrid == null) toggle,
                              ?sortMenu,
                            ],
                          ),
                  ),
                ),
              ...headerSlivers,
              EntitiesPageScope(isGrid: isGrid, child: sliver),
            ],
          ),
        ),
        const SliverBottomPadding(),
      ],
    );
  }
}

class _SliverEntitiesListBody<T> extends StatelessWidget {
  final List<T> items;
  final Widget Function(BuildContext context, T item) gridBuilder;
  final Widget Function(BuildContext context, T item) listBuilder;
  const new({
    super.key,
    required this.items,
    required this.gridBuilder,
    required this.listBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final isGrid = EntitiesPageScope.of(context).isGrid;

    if (isGrid) {
      return SliverPadding(
        padding: LayoutConstants.smallEdgeInsets,
        sliver: AdaptiveSliverGrid(
          builder: (context, index) => gridBuilder(context, items[index]),
          itemCount: items.length,
        ),
      );
    }

    return SliverAdaptivePadding(
      padding: LayoutConstants.smallEdgeInsets,
      sliver: SliverList.separated(
        itemBuilder: (context, index) => listBuilder(context, items[index]),
        separatorBuilder: (context, index) => const SizedBox(
          height: LayoutConstants.listSpacing,
        ),
        itemCount: items.length,
      ),
    );
  }
}

class EntitiesPageScope extends InheritedWidget {
  final bool isGrid;

  const new({
    super.key,
    required this.isGrid,
    required super.child,
  });

  static EntitiesPageScope of(BuildContext context) {
    final EntitiesPageScope? result = context
        .dependOnInheritedWidgetOfExactType<EntitiesPageScope>();
    assert(result != null, 'No EntitiesPageScope found in context');
    return result!;
  }

  @override
  bool updateShouldNotify(EntitiesPageScope oldWidget) {
    return isGrid != oldWidget.isGrid;
  }
}
