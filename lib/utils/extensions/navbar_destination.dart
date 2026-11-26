import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/riverpod/providers/router.dart';
import 'package:kover/riverpod/providers/settings/general_settings.dart';
import 'package:kover/utils/constants/kover_icons.dart';

extension NavbarDestinationsExtension on NavbarDestinations {
  IconData get icon {
    return switch (this) {
      .home => KoverIcons.home,
      .allSeries => KoverIcons.series,
      .wantToRead => KoverIcons.wantToRead,
      .collections => KoverIcons.collection,
      .readingLists => KoverIcons.readingList,
      .bookmarks => KoverIcons.bookmarkOn,
      .localLibrary => KoverIcons.library,
    };
  }

  /// Whether the destination can be shown on the current platform.
  bool get isSupported => true;

  String getLabel(AppLocalizations l) {
    return switch (this) {
      .home => l.home,
      .allSeries => l.allSeries,
      .wantToRead => l.wantToRead,
      .collections => l.collections,
      .readingLists => l.readingLists,
      .bookmarks => l.bookmarks,
      .localLibrary => l.library,
    };
  }

  GoRouteData get route {
    return switch (this) {
      .home => const HomeRoute(),
      .allSeries => const AllSeriesRoute(),
      .wantToRead => const WantToReadRoute(),
      .collections => const CollectionsRoute(),
      .readingLists => const ReadingListsRoute(),
      .bookmarks => const BookmarksRoute(),
      .localLibrary => const LibraryRoute(),
    };
  }
}
