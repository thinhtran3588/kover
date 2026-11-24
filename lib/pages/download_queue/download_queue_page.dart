import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/riverpod/managers/download_manager/download_manager.dart';
import 'package:kover/riverpod/providers/chapter.dart';
import 'package:kover/riverpod/providers/download.dart';
import 'package:kover/riverpod/providers/series.dart';
import 'package:kover/utils/constants/kover_icons.dart';
import 'package:kover/utils/constants/layout_constants.dart';
import 'package:kover/widgets/cards/cover_image.dart';
import 'package:kover/widgets/lists/cover_list_entry.dart';
import 'package:kover/widgets/util/async_value.dart';
import 'package:kover/widgets/util/sliver_adaptive_padding.dart';
import 'package:kover/widgets/util/sliver_bottom_padding.dart';
import 'package:material_ui/material_ui.dart';

class DownloadQueuePage extends ConsumerWidget {
  const DownloadQueuePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final hasDls = ref.watch(
      downloadManagerProvider.select(
        (state) =>
            state.value != null &&
            (state.value!.downloadQueue.isNotEmpty ||
                state.value!.failed.isNotEmpty ||
                state.value!.paused.isNotEmpty),
      ),
    );
    final hasFailed = ref.watch(
      downloadManagerProvider.select(
        (state) => state.value?.failed.isNotEmpty ?? false,
      ),
    );

    return Scaffold(
      body: CustomScrollView(
        physics: hasDls ? null : const NeverScrollableScrollPhysics(),
        slivers: [
          SliverAppBar.large(
            title: Text(l.downloadQueue),
            actions: [
              if (hasFailed)
                TextButton(
                  onPressed: () async {
                    await ref.read(downloadManagerProvider.notifier).retryAll();
                  },
                  child: Text(l.retryAll),
                ),
              if (hasDls) const CancellAllAction(),
            ],
          ),
          const SliverSafeArea(
            top: false,
            bottom: false,
            sliver: SliverAdaptivePadding(
              sliver: DownloadQueueList(),
            ),
          ),
          const SliverBottomPadding(),
        ],
      ),
    );
  }
}

class CancellAllAction extends ConsumerWidget {
  const CancellAllAction({
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return TextButton(
      onPressed: () async {
        await ref.read(downloadManagerProvider.notifier).cancelAll();
      },
      child: Text(l.cancelAll),
    );
  }
}

class DownloadQueueList extends ConsumerWidget {
  const DownloadQueueList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queued = ref.watch(downloadManagerProvider);
    return AsyncSliver(
      asyncValue: queued,
      data: (data) {
        final l = AppLocalizations.of(context);
        final ids = {
          ...data.downloadQueue,
          ...data.failed.keys,
          ...data.paused,
        }.toList();
        if (ids.isEmpty) {
          return SliverFillRemaining(
            child: Center(child: Text(l.noDownloadsInQueue)),
          );
        }
        return SliverList.separated(
          itemCount: ids.length,
          itemBuilder: (context, index) {
            return DownloadQueueItem(chapterId: ids[index]);
          },
          separatorBuilder: (context, index) {
            return const SizedBox(height: LayoutConstants.listSpacing);
          },
        );
      },
    );
  }
}

class DownloadQueueItem extends ConsumerWidget {
  final int chapterId;

  const DownloadQueueItem({
    super.key,
    required this.chapterId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chapter = ref.watch(chapterProvider(chapterId: chapterId));
    final series = ref.watch(seriesForChapterProvider(chapterId: chapterId));

    final progress = ref.watch(
      chapterDownloadProgressProvider(chapterId: chapterId),
    );
    final l = AppLocalizations.of(context);
    final manager = ref.read(downloadManagerProvider.notifier);
    final isFailed = ref.watch(
      downloadManagerProvider.select(
        (state) => state.value?.failed.containsKey(chapterId) ?? false,
      ),
    );
    final isPaused = ref.watch(
      downloadManagerProvider.select(
        (state) => state.value?.paused.contains(chapterId) ?? false,
      ),
    );

    return Async(
      asyncValue: chapter,
      data: (data) {
        return CoverListEntry(
          cover: ChapterCoverImage(chapterId: chapterId),
          title: data.title,
          subtitle: isFailed ? l.downloadFailed : series.value?.name,
          progress: progress.value,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isFailed)
                IconButton(
                  tooltip: l.retry,
                  onPressed: () => manager.retry(chapterId),
                  icon: const Icon(KoverIcons.retry),
                )
              else if (isPaused)
                IconButton(
                  tooltip: l.resume,
                  onPressed: () => manager.resume(chapterId),
                  icon: const Icon(KoverIcons.resume),
                )
              else
                IconButton(
                  tooltip: l.pause,
                  onPressed: () => manager.pause(chapterId),
                  icon: const Icon(KoverIcons.downloadPaused),
                ),
              IconButton(
                tooltip: l.cancel,
                onPressed: () => manager.cancel(chapterId),
                icon: const Icon(KoverIcons.cancel),
              ),
            ],
          ),
        );
      },
      loading: () {
        return const CoverListEntryPlaceholder();
      },
    );
  }
}
