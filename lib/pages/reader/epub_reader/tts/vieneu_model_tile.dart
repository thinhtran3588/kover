import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/riverpod/providers/tts/vieneu/vieneu_model.dart';
import 'package:kover/utils/constants/layout_constants.dart';
import 'package:material_ui/material_ui.dart';

const _megabyte = 1000 * 1000;

/// Downloads and deletes the VieNeu voice model.
class VieneuModelTile extends ConsumerWidget {
  const VieneuModelTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final model = ref.watch(vieneuModelProvider).value;
    final notifier = ref.read(vieneuModelProvider.notifier);
    final total = vieneuFiles.fold(0, (sum, file) => sum + file.size);

    return Column(
      crossAxisAlignment: .start,
      spacing: LayoutConstants.mediumPadding,
      children: [
        switch (model) {
          VieneuModelDownloading(:final received, :final total) => Column(
            crossAxisAlignment: .start,
            spacing: LayoutConstants.smallPadding,
            children: [
              LinearProgressIndicator(value: received / total),
              Text(
                l.vieneuDownloading(
                  received ~/ _megabyte,
                  total ~/ _megabyte,
                ),
              ),
              TextButton(onPressed: notifier.cancel, child: Text(l.cancel)),
            ],
          ),
          VieneuModelReady() => Column(
            crossAxisAlignment: .start,
            spacing: LayoutConstants.smallPadding,
            children: [
              Text(l.vieneuReady),
              TextButton(
                onPressed: notifier.delete,
                child: Text(l.vieneuDelete),
              ),
            ],
          ),
          _ => Column(
            crossAxisAlignment: .start,
            spacing: LayoutConstants.smallPadding,
            children: [
              if (model case VieneuModelFailed(:final message))
                Text(l.vieneuFailed(message)),
              FilledButton.tonal(
                onPressed: model == null ? null : notifier.download,
                child: Text(l.vieneuDownload(total ~/ _megabyte)),
              ),
            ],
          ),
        },
      ],
    );
  }
}
