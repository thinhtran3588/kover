import 'package:kover/pages/favorites/favorites_page.dart';
import 'package:kover/pages/recently_added_page/recently_added_page.dart';
import 'package:kover/pages/recently_updated_page/recently_updated_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:kover/pages/download_queue/download_queue_page.dart';
import 'package:kover/models/enums/reading_source.dart';
import 'package:kover/pages/google_drive/google_drive_page.dart';
import 'package:kover/pages/library/library_page.dart';
import 'package:kover/pages/libraries_page/libraries_page.dart';
import 'package:kover/pages/on_deck_page/on_deck_page.dart';
import 'package:kover/pages/collections_page/collections_page.dart';
import 'package:kover/pages/reading_list_details_page/reading_lists_details_page.dart';
import 'package:kover/pages/reading_lists_page/reading_lists_page.dart';
import 'package:kover/pages/series_page/series_page.dart';
import 'package:kover/pages/smart_filter_page/smart_filter_page.dart';
import 'package:kover/pages/bookmarks/bookmark_viewer_page.dart';
import 'package:kover/pages/bookmarks/bookmarks_grid_page.dart';
import 'package:kover/pages/bookmarks/bookmarks_page.dart';
import 'package:kover/pages/reader/reader_page.dart';
import 'package:kover/pages/series_detail_page/chapter_detail_page/chapter_detail_page.dart';
import 'package:kover/pages/series_detail_page/chapters_page/chapters_page.dart';
import 'package:kover/pages/series_detail_page/series_detail_page.dart';
import 'package:kover/pages/series_detail_page/volume_detail_page/volume_detail_page.dart';
import 'package:kover/pages/series_detail_page/volumes_page/volumes_page.dart';
import 'package:kover/pages/settings/local_logs/local_logs_page.dart';
import 'package:kover/pages/settings/settings_page.dart';
import 'package:kover/pages/settings/settings_section.dart';
import 'package:kover/widgets/util/navigator_container.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

part 'router.g.dart';

final navigatorKey = GlobalKey<NavigatorState>();

@riverpod
GoRouter router(Ref ref) {
  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/',
    routes: $appRoutes,
    observers: [SentryNavigatorObserver()],
  );
}

@TypedStatefulShellRoute<AppShellRoute>(
  branches: [
    TypedStatefulShellBranch<LibraryBranch>(
      routes: [
        TypedGoRoute<LibraryRoute>(
          path: '/',
          routes: [
            TypedGoRoute<SeriesDetailRoute>(
              path: 'series/:seriesId',
              routes: [
                TypedGoRoute<VolumesRoute>(
                  path: 'volumes',
                  routes: [
                    TypedGoRoute<VolumeDetailRoute>(
                      path: ':volumeId',
                      routes: [
                        TypedGoRoute<VolumeBookmarksRoute>(path: 'bookmarks'),
                      ],
                    ),
                  ],
                ),
                TypedGoRoute<SeriesBookmarksRoute>(path: 'bookmarks'),
                TypedGoRoute<ChaptersRoute>(
                  path: 'chapters',
                  routes: [
                    TypedGoRoute<ChapterDetailRoute>(
                      path: ':chapterId',
                      routes: [
                        TypedGoRoute<ChapterBookmarksRoute>(
                          path: 'bookmarks',
                        ),
                      ],
                    ),
                  ],
                ),
                TypedGoRoute<StorylineRoute>(path: 'storyline'),
                TypedGoRoute<SpecialsRoute>(path: 'specials'),
              ],
            ),
            TypedGoRoute<OnDeckRoute>(path: 'on-deck'),
            TypedGoRoute<RecentlyAddedRoute>(path: 'recently-added'),
            TypedGoRoute<RecentlyUpdatedRoute>(path: 'recently-updated'),
            TypedGoRoute<SmartFilterRoute>(
              path: 'smart-filters/:smartFilterId',
            ),
            TypedGoRoute<SeriesRoute>(path: 'library/:libraryId'),
            TypedGoRoute<LibrariesRoute>(path: 'libraries'),
            TypedGoRoute<CollectionsRoute>(
              path: 'collections',
              routes: [
                TypedGoRoute<CollectionSeriesRoute>(
                  path: ':collectionId',
                ),
              ],
            ),
            TypedGoRoute<ReadingListsRoute>(
              path: 'reading-lists',
              routes: [
                TypedGoRoute<ReadingListDetailsRoute>(
                  path: ':readingListId',
                ),
              ],
            ),
            TypedGoRoute<BookmarksRoute>(path: 'bookmarks'),
            TypedGoRoute<DownloadQueueRoute>(path: 'download-queue'),
            TypedGoRoute<GoogleDriveRoute>(
              path: 'drive',
              routes: [
                TypedGoRoute<GoogleDriveFolderRoute>(path: ':folderId'),
              ],
            ),
          ],
        ),
      ],
    ),
    TypedStatefulShellBranch<WantToReadBranch>(
      routes: [
        TypedGoRoute<FavoritesRoute>(path: '/favorites'),
      ],
    ),
    TypedStatefulShellBranch<SettingsBranch>(
      routes: [
        TypedGoRoute<SettingsRoute>(
          path: '/settings',
          routes: [
            TypedGoRoute<LocalLogsRoute>(path: 'local-logs'),
          ],
        ),
      ],
    ),
  ],
)
class AppShellRoute extends StatefulShellRouteData {
  const AppShellRoute();

  @override
  Widget builder(
    BuildContext context,
    GoRouterState state,
    StatefulNavigationShell navigationShell,
  ) {
    return NavigatorContainer(navigationShell: navigationShell);
  }
}

class WantToReadBranch extends StatefulShellBranchData {
  const WantToReadBranch();
}

class LibraryBranch extends StatefulShellBranchData {
  const LibraryBranch();
}

class SettingsBranch extends StatefulShellBranchData {
  const SettingsBranch();
}

class FavoritesRoute extends GoRouteData with $FavoritesRoute {
  final ReadingSource? source;

  const FavoritesRoute({this.source});

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      FavoritesPage(source: source);
}

class LibraryRoute extends GoRouteData with $LibraryRoute {
  final ReadingSource? source;

  const LibraryRoute({this.source});

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      LibraryPage(source: source);
}

class GoogleDriveRoute extends GoRouteData with $GoogleDriveRoute {
  const GoogleDriveRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const DriveBrowserPage();
}

class GoogleDriveFolderRoute extends GoRouteData with $GoogleDriveFolderRoute {
  final String folderId;
  final String? name;

  const GoogleDriveFolderRoute({required this.folderId, this.name});

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      DriveBrowserPage(folderId: folderId, title: name);
}

class LibrariesRoute extends GoRouteData with $LibrariesRoute {
  const LibrariesRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const LibrariesPage();
}

class BookmarksRoute extends GoRouteData with $BookmarksRoute {
  const BookmarksRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const BookmarksPage();
}

class OnDeckRoute extends GoRouteData with $OnDeckRoute {
  const new();

  @override
  Widget build(BuildContext context, GoRouterState state) => const OnDeckPage();
}

class RecentlyAddedRoute extends GoRouteData with $RecentlyAddedRoute {
  const new();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const RecentlyAddedPage();
}

class RecentlyUpdatedRoute extends GoRouteData with $RecentlyUpdatedRoute {
  const new();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const RecentlyUpdatedPage();
}

class SmartFilterRoute extends GoRouteData with $SmartFilterRoute {
  final int smartFilterId;

  const new({required this.smartFilterId});

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      SmartFilterPage(smartFilterId: smartFilterId);
}

class CollectionsRoute extends GoRouteData with $CollectionsRoute {
  const CollectionsRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const CollectionsPage();
}

class CollectionSeriesRoute extends GoRouteData with $CollectionSeriesRoute {
  final int collectionId;

  const CollectionSeriesRoute({required this.collectionId});

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      CollectionSeriesPage(collectionId: collectionId);
}

class ReadingListsRoute extends GoRouteData with $ReadingListsRoute {
  const ReadingListsRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const ReadingListsPage();
}

class ReadingListDetailsRoute extends GoRouteData
    with $ReadingListDetailsRoute {
  final int readingListId;

  const ReadingListDetailsRoute({required this.readingListId});

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      ReadingListsDetailsPage(readingListId: readingListId);
}

class SeriesRoute extends GoRouteData with $SeriesRoute {
  final int libraryId;

  const SeriesRoute({required this.libraryId});

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      LibrarySeriesPage(libraryId: libraryId);
}

class SeriesDetailRoute extends GoRouteData with $SeriesDetailRoute {
  const SeriesDetailRoute({required this.seriesId});

  final int seriesId;

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      SeriesDetailPage(seriesId: seriesId);
}

class VolumesRoute extends GoRouteData with $VolumesRoute {
  const VolumesRoute({required this.seriesId});

  final int seriesId;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return VolumesPage(
      seriesId: seriesId,
    );
  }
}

class ChaptersRoute extends GoRouteData with $ChaptersRoute {
  const ChaptersRoute({required this.seriesId, this.volumeId});

  final int seriesId;
  final int? volumeId;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return ChaptersPage(seriesId: seriesId, volumeId: volumeId);
  }
}

class SpecialsRoute extends GoRouteData with $SpecialsRoute {
  const SpecialsRoute({required this.seriesId});

  final int seriesId;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return SpecialsPage(seriesId: seriesId);
  }
}

class StorylineRoute extends GoRouteData with $StorylineRoute {
  const StorylineRoute({required this.seriesId});

  final int seriesId;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return StorylinePage(seriesId: seriesId);
  }
}

class VolumeDetailRoute extends GoRouteData with $VolumeDetailRoute {
  VolumeDetailRoute({required this.seriesId, required this.volumeId});

  final int seriesId;
  final int volumeId;

  @override
  Widget build(BuildContext context, GoRouterState state) => VolumeDetailPage(
    volumeId: volumeId,
  );
}

class ChapterDetailRoute extends GoRouteData with $ChapterDetailRoute {
  const ChapterDetailRoute({required this.seriesId, required this.chapterId});

  final int seriesId;
  final int chapterId;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return ChapterDetailPage(seriesId: seriesId, chapterId: chapterId);
  }
}

class ChapterBookmarksRoute extends GoRouteData with $ChapterBookmarksRoute {
  const ChapterBookmarksRoute({
    required this.seriesId,
    required this.chapterId,
  });

  final int seriesId;
  final int chapterId;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return BookmarksGridPage(seriesId: seriesId, chapterId: chapterId);
  }
}

class SettingsRoute extends GoRouteData with $SettingsRoute {
  final SettingsSection? section;

  const SettingsRoute({this.section});

  @override
  Widget build(BuildContext context, GoRouterState state) => SettingsPage(
    key: ValueKey(section),
    section: section ?? .general,
  );
}

class LocalLogsRoute extends GoRouteData with $LocalLogsRoute {
  const LocalLogsRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const LocalLogsPage();
}

class DownloadQueueRoute extends GoRouteData with $DownloadQueueRoute {
  const DownloadQueueRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const DownloadQueuePage();
}

class SeriesBookmarksRoute extends GoRouteData with $SeriesBookmarksRoute {
  const SeriesBookmarksRoute({required this.seriesId});

  final int seriesId;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return BookmarksGridPage(seriesId: seriesId);
  }
}

class VolumeBookmarksRoute extends GoRouteData with $VolumeBookmarksRoute {
  const VolumeBookmarksRoute({
    required this.seriesId,
    required this.volumeId,
  });

  final int seriesId;
  final int volumeId;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return BookmarksGridPage(seriesId: seriesId, volumeId: volumeId);
  }
}

@TypedGoRoute<SeriesBookmarkViewerRoute>(
  path: '/bookmarks/series/:seriesId/:index',
)
class SeriesBookmarkViewerRoute extends GoRouteData
    with $SeriesBookmarkViewerRoute {
  final int seriesId;
  final int index;

  const SeriesBookmarkViewerRoute({
    required this.seriesId,
    required this.index,
  });

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return MaterialPage(
      key: state.pageKey,
      fullscreenDialog: true,
      child: BookmarkViewerPage(
        seriesId: seriesId,
        initialIndex: index,
      ),
    );
  }
}

@TypedGoRoute<VolumeBookmarkViewerRoute>(
  path: '/bookmarks/volume/:seriesId/:volumeId/:index',
)
class VolumeBookmarkViewerRoute extends GoRouteData
    with $VolumeBookmarkViewerRoute {
  final int seriesId;
  final int volumeId;
  final int index;

  const VolumeBookmarkViewerRoute({
    required this.seriesId,
    required this.volumeId,
    required this.index,
  });

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return MaterialPage(
      key: state.pageKey,
      fullscreenDialog: true,
      child: BookmarkViewerPage(
        seriesId: seriesId,
        volumeId: volumeId,
        initialIndex: index,
      ),
    );
  }
}

@TypedGoRoute<ChapterBookmarkViewerRoute>(
  path: '/bookmarks/chapter/:seriesId/:chapterId/:index',
)
class ChapterBookmarkViewerRoute extends GoRouteData
    with $ChapterBookmarkViewerRoute {
  final int seriesId;
  final int chapterId;
  final int index;

  const ChapterBookmarkViewerRoute({
    required this.seriesId,
    required this.chapterId,
    required this.index,
  });

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return MaterialPage(
      key: state.pageKey,
      fullscreenDialog: true,
      child: BookmarkViewerPage(
        seriesId: seriesId,
        chapterId: chapterId,
        initialIndex: index,
      ),
    );
  }
}

@TypedGoRoute<ReaderRoute>(path: '/reader/:seriesId')
class ReaderRoute extends GoRouteData with $ReaderRoute {
  final int seriesId;
  final int chapterId;
  final int? readingListId;

  const ReaderRoute({
    required this.seriesId,
    required this.chapterId,
    required this.readingListId,
  });

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return MaterialPage(
      key: state.pageKey,
      fullscreenDialog: true,
      child: ReaderPage(
        seriesId: seriesId,
        chapterId: chapterId,
        readingListId: readingListId,
      ),
    );
  }
}
