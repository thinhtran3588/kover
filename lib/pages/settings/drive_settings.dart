import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/riverpod/providers/google_drive_auth.dart';
import 'package:kover/utils/constants/kover_icons.dart';
import 'package:kover/utils/constants/layout_constants.dart';
import 'package:kover/widgets/util/async_value.dart';
import 'package:material_ui/material_ui.dart';

class DriveSettings extends HookConsumerWidget {
  const DriveSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final busy = useState(false);

    return Card(
      margin: .zero,
      child: Padding(
        padding: LayoutConstants.mediumEdgeInsets,
        child: Async(
          asyncValue: ref.watch(googleDriveAuthProvider),
          data: (state) => Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            spacing: LayoutConstants.mediumPadding,
            children: [
              Text(
                l.googleAccount,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              switch (state) {
                DriveNotSupported() => Text(l.driveNotSupported),
                DriveNotConfigured() => Text(l.driveNotSetUp),
                DriveSignedOut() => FilledButton.icon(
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
                  icon: const Icon(KoverIcons.cloud),
                  label: Text(l.signInWithGoogle),
                ),
                DriveSignedIn(:final email) => Row(
                  mainAxisAlignment: .spaceBetween,
                  children: [
                    Flexible(child: Text(email)),
                    FilledButton(
                      onPressed: () =>
                          ref.read(googleDriveAuthProvider.notifier).signOut(),
                      child: Text(l.signOutGoogle),
                    ),
                  ],
                ),
              },
            ],
          ),
        ),
      ),
    );
  }
}
