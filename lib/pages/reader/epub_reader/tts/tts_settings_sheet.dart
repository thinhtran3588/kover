import 'package:collection/collection.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/riverpod/providers/series.dart';
import 'package:kover/riverpod/providers/settings/tts_settings.dart';
import 'package:kover/riverpod/providers/tts/tts_engine.dart';
import 'package:kover/riverpod/providers/tts/tts_player.dart';
import 'package:kover/utils/constants/kover_icons.dart';
import 'package:kover/utils/constants/layout_constants.dart';
import 'package:kover/widgets/settings/boolean_option.dart';
import 'package:kover/widgets/settings/choice_option.dart';
import 'package:kover/widgets/settings/numeric_option.dart';
import 'package:kover/widgets/settings/select_option.dart';
import 'package:kover/widgets/util/async_value.dart';
import 'package:material_ui/material_ui.dart';

class TtsSettingsBottomSheet extends ConsumerWidget {
  final int seriesId;
  const TtsSettingsBottomSheet({super.key, required this.seriesId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final notifier = ref.read(ttsSettingsProvider.notifier);
    final language = ref.watch(
      seriesMetadataProvider(
        seriesId: seriesId,
      ).select((state) => state.value?.language),
    );
    final voices = ref.watch(ttsVoicesProvider).value ?? const <TtsVoice>[];

    return Async(
      asyncValue: ref.watch(ttsSettingsProvider),
      data: (settings) {
        final shown = _voicesFor(voices, language, settings.voiceName);

        return Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: LayoutConstants.largePadding,
                    right: LayoutConstants.largePadding,
                    bottom: LayoutConstants.largePadding,
                  ),
                  child: Column(
                    crossAxisAlignment: .start,
                    spacing: LayoutConstants.largePadding,
                    children: [
                      Text(
                        l.readAloud,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      ChoiceOption<TtsEngineType>(
                        title: l.ttsEngine,
                        description: edgeTtsSupported
                            ? l.ttsEngineEdgeDescription
                            : null,
                        value: settings.engine,
                        options: [
                          ChoiceOptionEntry(
                            value: .device,
                            label: l.ttsEngineDevice,
                            icon: KoverIcons.readAloud,
                          ),
                          if (edgeTtsSupported)
                            ChoiceOptionEntry(
                              value: .edge,
                              label: l.ttsEngineEdge,
                              icon: KoverIcons.ttsOnline,
                            ),
                        ],
                        onChanged: notifier.setEngine,
                      ),
                      SelectOption<String?>(
                        icon: KoverIcons.ttsVoice,
                        title: l.ttsVoice,
                        value: settings.voiceName,
                        options: [
                          SelectOptionEntry(
                            value: null,
                            label: l.ttsVoiceDefault,
                          ),
                          for (final voice in shown)
                            SelectOptionEntry(
                              value: voice.name,
                              label: '${voice.name} (${voice.locale})',
                            ),
                        ],
                        onChanged: (name) {
                          final voice = shown.firstWhereOrNull(
                            (voice) => voice.name == name,
                          );
                          notifier.setVoice(
                            name: voice?.name,
                            locale: voice?.locale,
                          );
                        },
                      ),
                      NumericOption(
                        icon: KoverIcons.ttsRate,
                        title: l.ttsRate,
                        value: settings.rate,
                        min: TtsSettingsLimits.rateMin,
                        max: TtsSettingsLimits.rateMax,
                        step: TtsSettingsLimits.rateStep,
                        decimalPlaces: 2,
                        onChanged: notifier.setRate,
                      ),
                      NumericOption(
                        icon: KoverIcons.ttsPitch,
                        title: l.ttsPitch,
                        value: settings.pitch,
                        min: TtsSettingsLimits.pitchMin,
                        max: TtsSettingsLimits.pitchMax,
                        step: TtsSettingsLimits.pitchStep,
                        decimalPlaces: 2,
                        onChanged: notifier.setPitch,
                      ),
                      BooleanOption(
                        icon: KoverIcons.ttsNextChapter,
                        title: l.ttsContinueNextChapter,
                        description: l.ttsContinueNextChapterDescription,
                        value: settings.continueNextChapter,
                        onChanged: notifier.setContinueNextChapter,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.only(
                left: LayoutConstants.largePadding,
                right: LayoutConstants.largePadding,
                bottom: LayoutConstants.largePadding,
                top: LayoutConstants.mediumPadding,
              ),
              child: FilledButton.tonalIcon(
                onPressed: notifier.reset,
                icon: const Icon(KoverIcons.reset),
                label: Text(l.reset),
              ),
            ),
          ],
        );
      },
    );
  }

  /// The voices matching the series [language], or all of them when none do.
  /// The selected voice is always kept.
  static List<TtsVoice> _voicesFor(
    List<TtsVoice> voices,
    String? language,
    String? selected,
  ) {
    final primary = language?.split(RegExp('[-_]')).first.toLowerCase();
    if (primary == null || primary.isEmpty) return voices;

    final matching = voices
        .where(
          (voice) =>
              voice.name == selected ||
              voice.locale.split(RegExp('[-_]')).first.toLowerCase() == primary,
        )
        .toList();
    return matching.length > (selected == null ? 0 : 1) ? matching : voices;
  }
}
