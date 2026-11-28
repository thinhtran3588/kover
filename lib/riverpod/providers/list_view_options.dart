import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:kover/models/enums/local_book_source.dart';
import 'package:kover/models/enums/order_by_option.dart';
import 'package:kover/models/enums/sort_direction.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'list_view_options.freezed.dart';
part 'list_view_options.g.dart';

/// The page whose source tabs share their view controls with the app bar.
enum ViewScope { library, favorites }

enum LocalSort { lastRead, name, dateAdded }

/// Layout and sort of the Kavita series list of a [ViewScope].
@freezed
sealed class SeriesViewState with _$SeriesViewState {
  const factory SeriesViewState({
    @Default(true) bool isGrid,
    @Default(UnorderedSortOption.name) UnorderedSortOption orderBy,
    @Default(SortDirection.ascending) SortDirection direction,
    @Default(false) bool hideRead,
    @Default(false) bool downloadedOnly,
  }) = _SeriesViewState;
}

@Riverpod(keepAlive: true)
class SeriesView extends _$SeriesView {
  @override
  SeriesViewState build(ViewScope scope) => const SeriesViewState();

  void update(SeriesViewState value) => state = value;
}

/// Layout and sort of the books of one local source tab.
@freezed
sealed class LocalViewState with _$LocalViewState {
  const factory LocalViewState({
    @Default(true) bool isGrid,
    @Default(LocalSort.lastRead) LocalSort sort,
  }) = _LocalViewState;
}

@Riverpod(keepAlive: true)
class LocalView extends _$LocalView {
  @override
  LocalViewState build(LocalBookSource source, bool favoritesOnly) =>
      const LocalViewState();

  void update(LocalViewState value) => state = value;
}
