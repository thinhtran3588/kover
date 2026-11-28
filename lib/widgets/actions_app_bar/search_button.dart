import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/models/chapter_model.dart';
import 'package:kover/models/enums/local_book_source.dart';
import 'package:kover/models/local_book_model.dart';
import 'package:kover/pages/local_library/local_book_card.dart';
import 'package:kover/models/series_model.dart';
import 'package:kover/models/volume_model.dart';
import 'package:kover/riverpod/providers/chapter.dart';
import 'package:kover/riverpod/providers/library.dart';
import 'package:kover/riverpod/providers/local_library.dart';
import 'package:kover/riverpod/providers/router.dart';
import 'package:kover/riverpod/providers/series.dart';
import 'package:kover/riverpod/providers/settings/credentials.dart';
import 'package:kover/riverpod/providers/volume.dart';
import 'package:kover/utils/constants/kover_icons.dart';
import 'package:kover/utils/constants/layout_constants.dart';
import 'package:kover/widgets/cards/cover_image.dart';
import 'package:kover/widgets/lists/cover_list_entry.dart';
import 'package:kover/widgets/util/async_value.dart';
import 'package:kover/widgets/util/sliver_bottom_padding.dart';
import 'package:material_ui/material_ui.dart';

class SearchButton extends HookConsumerWidget {
  const SearchButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useMemoized(() => SearchController(), []);

    return SearchAnchor(
      searchController: controller,
      isFullScreen: true,
      viewHintText: AppLocalizations.of(context).searchAllSources,
      headerHeight: 45.0,
      headerTextStyle: Theme.of(context).textTheme.bodyLarge,
      viewLeading: IconButton(
        style: IconButton.styleFrom(
          visualDensity: .compact,
        ),
        icon: const Icon(
          KoverIcons.chevronLeft,
          size: LayoutConstants.mediumIcon,
        ),
        onPressed: () => controller.closeView(null),
      ),
      viewTrailing: [
        IconButton(
          style: IconButton.styleFrom(visualDensity: .compact),
          icon: const Icon(
            KoverIcons.close,
            size: LayoutConstants.mediumIcon,
          ),
          onPressed: () => controller.clear(),
        ),
      ],
      builder: (BuildContext context, SearchController controller) {
        return IconButton(
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            tapTargetSize: .shrinkWrap,
            visualDensity: .compact,
          ),
          icon: const Icon(
            KoverIcons.search,
            size: LayoutConstants.smallIcon,
          ),
          onPressed: () {
            controller.openView(); // Manually opens the search view
          },
        );
      },
      suggestionsBuilder: (context, controller) async {
        final query = controller.text.trim();
        if (query.isEmpty) return const [];

        final l = AppLocalizations.of(context);
        final theme = Theme.of(context);
        final kavitaSetUp =
            ref.read(loginStatusProvider) != LoginStatus.noCredentials;
        // Keep the auto-dispose book search alive until it has a value.
        final booksSub = ref.listenManual(
          searchLocalBooksProvider(query),
          (_, _) {},
        );
        final (
          seriesResults,
          volumesResults,
          chaptersResults,
          books,
        ) = await (
          kavitaSetUp
              ? ref.read(searchSeriesProvider(query).future)
              : Future.value(const <SeriesModel>[]),
          kavitaSetUp
              ? ref.read(searchVolumesProvider(query).future)
              : Future.value(const <VolumeModel>[]),
          kavitaSetUp
              ? ref.read(searchChaptersProvider(query).future)
              : Future.value(const <ChapterModel>[]),
          ref.read(searchLocalBooksProvider(query).future),
        ).wait.whenComplete(booksSub.close);
        final driveBooks = books[LocalBookSource.googleDrive] ?? const [];
        final deviceBooks = books[LocalBookSource.device] ?? const [];

        if (seriesResults.isEmpty &&
            volumesResults.isEmpty &&
            chaptersResults.isEmpty &&
            driveBooks.isEmpty &&
            deviceBooks.isEmpty) {
          return [
            Padding(
              padding: LayoutConstants.largeEdgeInsets,
              child: Text(
                l.noSearchResults,
                textAlign: .center,
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ];
        }

        return [
          if (seriesResults.isNotEmpty) ...[
            Text(
              '${l.sourceKavita} - ${l.series}',
              style: theme.textTheme.headlineSmall,
            ),
            ...seriesResults.map(
              (series) => SearchSeriesEntry(
                series: series,
                controller: controller,
              ),
            ),
          ],
          if (volumesResults.isNotEmpty) ...[
            Text(
              '${l.sourceKavita} - ${l.volumes}',
              style: theme.textTheme.headlineSmall,
            ),
            ...volumesResults.map(
              (volume) => SearchVolumeEntry(
                volume: volume,
                controller: controller,
              ),
            ),
          ],
          if (chaptersResults.isNotEmpty) ...[
            Text(
              '${l.sourceKavita} - ${l.chapters}',
              style: theme.textTheme.headlineSmall,
            ),
            ...chaptersResults.map(
              (chapter) => SearchChapterEntry(
                chapter: chapter,
                controller: controller,
              ),
            ),
          ],
          for (final (title, list) in [
            (l.sourceGoogleDrive, driveBooks),
            (l.onThisDevice, deviceBooks),
          ])
            if (list.isNotEmpty) ...[
              Text(
                title,
                style: theme.textTheme.headlineSmall,
              ),
              ...list.map(
                (book) => SearchBookEntry(book: book, controller: controller),
              ),
            ],
          const ListBottomPadding(),
        ].map(
          (entry) => Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: LayoutConstants.mediumPadding,
              vertical: LayoutConstants.smallerPadding,
            ),
            child: entry,
          ),
        );
      },
    );
  }
}

class SearchBookEntry extends ConsumerWidget {
  final LocalBookModel book;
  final SearchController controller;

  const SearchBookEntry({
    super.key,
    required this.book,
    required this.controller,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CoverListEntry(
      title: book.title,
      subtitle: book.author,
      cover: Async(
        asyncValue: ref.watch(localBookCoverProvider(book.id)),
        data: (image) => PlaceholderCoverImage(image: image),
        loading: () => const LoadingCover(),
      ),
      progress: book.progress,
      trailing: const Icon(KoverIcons.chevronRight),
      margin: EdgeInsets.zero,
      onTap: () {
        controller.closeView(null);
        openLocalBook(context, book.id);
      },
    );
  }
}

class SearchSeriesEntry extends ConsumerWidget {
  final SeriesModel series;
  final SearchController controller;

  const SearchSeriesEntry({
    super.key,
    required this.series,
    required this.controller,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(seriesProgressProvider(seriesId: series.id));
    final libraryName = ref.watch(
      libraryProvider(
        libraryId: series.libraryId,
      ).select((state) => state.value?.name),
    );

    return CoverListEntry(
      title: series.name,
      subtitle: libraryName,
      cover: SeriesCoverImage(seriesId: series.id),
      progress: progress.value,
      trailing: const Icon(KoverIcons.chevronRight),
      margin: EdgeInsets.zero,
      onTap: () {
        controller.closeView(null);
        SeriesDetailRoute(seriesId: series.id).go(context);
      },
    );
  }
}

class SearchVolumeEntry extends ConsumerWidget {
  final VolumeModel volume;
  final SearchController controller;

  const SearchVolumeEntry({
    super.key,
    required this.volume,
    required this.controller,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(volumeProgressProvider(volumeId: volume.id));
    final seriesName = ref.watch(
      seriesProvider(
        seriesId: volume.seriesId,
      ).select((state) => state.value?.name),
    );

    return CoverListEntry(
      title: volume.name,
      subtitle: seriesName,
      cover: VolumeCoverImage(
        volumeId: volume.id,
      ),
      progress: progress.value,
      trailing: const Icon(KoverIcons.chevronRight),
      margin: EdgeInsets.zero,
      onTap: () {
        controller.closeView(null);
        VolumeDetailRoute(
          seriesId: volume.seriesId,
          volumeId: volume.id,
        ).go(context);
      },
    );
  }
}

class SearchChapterEntry extends ConsumerWidget {
  final ChapterModel chapter;
  final SearchController controller;

  const SearchChapterEntry({
    super.key,
    required this.chapter,
    required this.controller,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(chapterProgressProvider(chapterId: chapter.id));
    final seriesName = ref.watch(
      seriesProvider(
        seriesId: chapter.seriesId,
      ).select((state) => state.value?.name),
    );
    final volumeName = ref.watch(
      volumeProvider(
        volumeId: chapter.volumeId,
      ).select((state) => state.value?.name),
    );
    final list = [seriesName, volumeName].whereType<String>();
    final subtitle = list.isEmpty ? '' : list.join(' - ');

    return CoverListEntry(
      title: chapter.title,
      subtitle: subtitle,
      cover: ChapterCoverImage(chapterId: chapter.id),
      progress: progress.value,
      trailing: const Icon(KoverIcons.chevronRight),
      margin: EdgeInsets.zero,
      onTap: () {
        controller.closeView(null);
        ChapterDetailRoute(
          seriesId: chapter.seriesId,
          chapterId: chapter.id,
        ).go(context);
      },
    );
  }
}
