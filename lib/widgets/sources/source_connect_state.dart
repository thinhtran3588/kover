import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/models/enums/reading_source.dart';
import 'package:kover/riverpod/providers/google_drive_auth.dart';
import 'package:kover/utils/constants/layout_constants.dart';
import 'package:kover/utils/extensions/reading_source.dart';
import 'package:kover/widgets/sources/source_tile.dart';
import 'package:material_ui/material_ui.dart';

/// Shown where the content of [source] would appear but the source is not
/// connected.
class SourceConnectState extends HookConsumerWidget {
  final ReadingSource source;

  const SourceConnectState({super.key, required this.source});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final busy = useState(false);
    final signedOut =
        source == ReadingSource.googleDrive &&
        ref.watch(googleDriveAuthProvider).value is DriveSignedOut;

    final description = switch (source) {
      .kavita => l.kavitaConnectDescription,
      .googleDrive => l.driveSignedOutDescription,
      .device => l.sourceNotAvailable,
    };

    return Center(
      child: SingleChildScrollView(
        padding: LayoutConstants.mediumEdgeInsets,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: .min,
            spacing: LayoutConstants.smallPadding,
            children: [
              Icon(
                source.icon,
                size: LayoutConstants.largerIcon,
                color: theme.colorScheme.primary,
              ),
              Text(
                source.getLabel(l),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: .bold,
                ),
                textAlign: .center,
              ),
              Text(description, textAlign: .center),
              SourceTile(source: source),
              if (signedOut)
                FilledButton(
                  onPressed: busy.value
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          busy.value = true;
                          try {
                            await ref
                                .read(googleDriveAuthProvider.notifier)
                                .signIn();
                          } catch (e) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('$e')),
                            );
                          }
                          if (context.mounted) busy.value = false;
                        },
                  child: Text(l.signInWithGoogle),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
