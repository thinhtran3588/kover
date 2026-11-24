import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/pages/reader/epub_reader/tts/tts_settings_sheet.dart';
import 'package:kover/pages/reader/overlay/reader_controls.dart';
import 'package:kover/riverpod/providers/settings/tts_settings.dart';
import 'package:kover/riverpod/providers/tts/tts_engine.dart';
import 'package:kover/riverpod/providers/tts/tts_player.dart';
import 'package:kover/utils/constants/kover_icons.dart';
import 'package:kover/utils/constants/layout_constants.dart';
import 'package:material_ui/material_ui.dart';

const _rateSteps = [0.75, 1.0, 1.25, 1.5, 2.0];

/// The mini player docked to the reader while reading aloud.
///
/// A row at the bottom, or a vertical rail on the end edge when the screen is
/// too short for a row to leave room for the text.
class TtsPlayerBar extends ConsumerWidget {
  final int seriesId;

  const TtsPlayerBar({super.key, required this.seriesId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final status = ref.watch(ttsPlayerProvider.select((s) => s.status));
    if (status == .idle) return const SizedBox.shrink();

    final player = ref.read(ttsPlayerProvider.notifier);
    final rate = ref.watch(
      ttsSettingsProvider.select(
        (s) => s.value?.rate ?? const TtsSettingsState().rate,
      ),
    );
    final online = ref.watch(
      ttsSettingsProvider.select((s) => s.value?.engine == .edge),
    );
    final rail =
        MediaQuery.sizeOf(context).height < LayoutConstants.dockRailHeight;
    final playing = status == .playing;

    final controls = [
      _BarButton(
        icon: KoverIcons.ttsPrevious,
        tooltip: l.readAloudPreviousSentence,
        onPressed: player.previous,
      ),
      IconButton.filled(
        iconSize: LayoutConstants.largeIcon,
        constraints: const BoxConstraints.tightFor(
          width: LayoutConstants.minTapTarget,
          height: LayoutConstants.minTapTarget,
        ),
        icon: Icon(playing ? KoverIcons.ttsPause : KoverIcons.ttsPlay),
        tooltip: playing ? l.readAloudPause : l.readAloudPlay,
        onPressed: player.togglePlayPause,
      ),
      _BarButton(
        icon: KoverIcons.ttsNext,
        tooltip: l.readAloudNextSentence,
        onPressed: player.next,
      ),
      TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size.square(LayoutConstants.minTapTarget),
          padding: EdgeInsets.zero,
        ),
        onPressed: () => ref
            .read(ttsSettingsProvider.notifier)
            .setRate(
              _rateSteps.firstWhere(
                (step) => step > rate + 0.001,
                orElse: () => _rateSteps.first,
              ),
            ),
        child: Tooltip(
          message: l.readAloudSpeed('$rate'),
          child: Text('${rate}x'),
        ),
      ),
      _BarButton(
        icon: KoverIcons.readerSettings,
        tooltip: l.readAloudSettings,
        onPressed: () => showReaderBottomSheet(
          context,
          ref,
          TtsSettingsBottomSheet(seriesId: seriesId),
        ),
      ),
      _BarButton(
        icon: KoverIcons.close,
        tooltip: l.readAloudStop,
        onPressed: player.stop,
      ),
    ];

    final statusText = switch (status) {
      .loading => l.readAloudLoading,
      .playing => l.readAloudPlaying,
      .paused => l.readAloudPaused,
      .error =>
        online && edgeTtsSupported ? l.readAloudErrorOnline : l.readAloudError,
      .idle => '',
    };

    // Only the screen edges the dock sits on are padded.
    return SafeArea(
      top: rail,
      left: !rail,
      child: Card.filled(
        margin: LayoutConstants.mediumEdgeInsets,
        child: Padding(
          padding: LayoutConstants.smallEdgeInsets,
          child: rail
              ? SingleChildScrollView(
                  child: Column(mainAxisSize: .min, children: controls),
                )
              : Column(
                  mainAxisSize: .min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(children: controls),
                    ),
                    Text(
                      statusText,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _BarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      constraints: const BoxConstraints.tightFor(
        width: LayoutConstants.minTapTarget,
        height: LayoutConstants.minTapTarget,
      ),
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }
}
