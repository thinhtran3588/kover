import 'package:kover/utils/constants/kover_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/pages/reader/epub_reader/epub_reader_controls.dart';
import 'package:kover/pages/reader/image_reader/image_reader_controls.dart';
import 'package:kover/pages/reader/overlay/page_slider.dart';
import 'package:kover/pages/reader/pdf_reader/pdf_reader_controls.dart';
import 'package:kover/riverpod/providers/tts/tts_audio_handler.dart';
import 'package:kover/riverpod/providers/tts/tts_engine.dart';
import 'package:kover/riverpod/providers/tts/tts_player.dart';
import 'package:kover/riverpod/providers/reader/reader.dart';
import 'package:kover/riverpod/providers/reader/reader_navigation.dart';
import 'package:kover/riverpod/providers/theme.dart';
import 'package:kover/utils/constants/layout_constants.dart';

class ReaderControls extends HookConsumerWidget {
  final int seriesId;
  final int chapterId;
  final int? readingListId;
  final void Function(int page)? onJumpToPage;
  final Widget? extraControls;

  const ReaderControls({
    super.key,
    required this.seriesId,
    required this.chapterId,
    required this.readingListId,
    this.onJumpToPage,
    this.extraControls,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final format = ref.watch(
      readerProvider(
        seriesId: seriesId,
        chapterId: chapterId,
        readingListId: readingListId,
      ).select(
        (state) => state.value?.series.format,
      ),
    );

    return SafeArea(
      // Sits at the bottom, and the dock above is placed by its height.
      top: false,
      minimum: .only(
        bottom: MediaQuery.systemGestureInsetsOf(context).bottom,
      ),
      child: Card.filled(
        margin: LayoutConstants.mediumEdgeInsets,
        child: Padding(
          padding: LayoutConstants.smallEdgeInsets,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: .end,
            children: [
              ?extraControls,
              Row(
                children: [
                  Expanded(
                    child: PageSlider(
                      seriesId: seriesId,
                      chapterId: chapterId,
                      readingListId: readingListId,
                      onJumpToPage: (page) => ref
                          .read(
                            readerNavigationProvider(
                              seriesId: seriesId,
                              chapterId: chapterId,
                              readingListId: readingListId,
                            ).notifier,
                          )
                          .jumpToPage(page),
                    ),
                  ),
                  if (format == .epub && ttsSupported)
                    IconButton(
                      icon: const Icon(KoverIcons.readAloud),
                      tooltip: AppLocalizations.of(context).readAloud,
                      onPressed: () {
                        // Started here, as the media session depends on the
                        // player.
                        ref.read(ttsAudioHandlerProvider.future).ignore();
                        ref
                            .read(ttsPlayerProvider.notifier)
                            .start(
                              seriesId: seriesId,
                              chapterId: chapterId,
                              readingListId: readingListId,
                            );
                      },
                    ),
                  if (format == .epub)
                    ReaderSettingsButton(
                      child: EpubReaderSettingsBottomSheet(seriesId: seriesId),
                    ),
                  if (format == .archive || format == .image)
                    ReaderSettingsButton(
                      child: ImageReaderSettingsBottomSheet(seriesId: seriesId),
                    ),
                  if (format == .pdf)
                    ReaderSettingsButton(
                      child: PdfReaderSettingsBottomSheet(seriesId: seriesId),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReaderSettingsButton extends ConsumerWidget {
  final Widget child;
  const ReaderSettingsButton({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return IconButton(
      icon: const Icon(KoverIcons.readerSettings),
      tooltip: l.readerSettings,
      onPressed: () => showReaderBottomSheet(context, ref, child),
    );
  }
}

/// Shows [child] in the modal bottom sheet used by the reader settings.
void showReaderBottomSheet(BuildContext context, WidgetRef ref, Widget child) {
  final reduceAnimations =
      ref.read(themeProvider).value?.reduceAnimations ??
      const ThemeModel().reduceAnimations;

  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      maxWidth: LayoutBreakpoints.medium,
    ),
    sheetAnimationStyle: reduceAnimations
        ? const AnimationStyle(duration: .zero, reverseDuration: .zero)
        : null,
    builder: (context) => child,
  );
}
