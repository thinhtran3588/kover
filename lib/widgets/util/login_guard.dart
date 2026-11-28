import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/models/enums/reading_source.dart';
import 'package:kover/riverpod/providers/auth.dart';
import 'package:kover/riverpod/providers/router.dart';
import 'package:kover/riverpod/providers/settings/credentials.dart';
import 'package:kover/utils/constants/kover_icons.dart';
import 'package:kover/utils/constants/layout_constants.dart';
import 'package:kover/widgets/sources/source_connect_state.dart';
import 'package:kover/widgets/sources/source_tile.dart';

class LoginGuard extends ConsumerWidget {
  final Widget child;

  /// Whether the not-connected state lists every source (onboarding) or only
  /// Kavita (inside a source tab).
  final bool showAllSources;

  const LoginGuard({
    super.key,
    required this.child,
    this.showAllSources = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final loginStatus = ref.watch(loginStatusProvider);

    return switch (loginStatus) {
      .loggedIn => child,
      .loading => const Center(child: CircularProgressIndicator()),
      .noCredentials =>
        showAllSources
            ? Scaffold(
                body: Center(
                  child: SingleChildScrollView(
                    padding: LayoutConstants.mediumEdgeInsets,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        mainAxisSize: .min,
                        spacing: LayoutConstants.smallPadding,
                        children: [
                          Text(
                            l.notSignedIn,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: .bold),
                            textAlign: .center,
                          ),
                          Text(l.chooseSourceDescription, textAlign: .center),
                          for (final source in ReadingSource.values)
                            SourceTile(source: source),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            : const SourceConnectState(source: .kavita),
      .invalidCredentials => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: .min,
            children: [
              Icon(
                KoverIcons.error,
                size: LayoutConstants.largerIcon,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: LayoutConstants.smallPadding),
              Text(
                l.invalidCredentials,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: .bold,
                ),
                textAlign: .center,
              ),
              const SizedBox(height: LayoutConstants.smallerPadding),
              Padding(
                padding: const .symmetric(
                  horizontal: LayoutConstants.mediumPadding,
                ),
                child: Text(
                  l.invalidCredentialsDescription,
                  textAlign: .center,
                ),
              ),
              const SizedBox(height: LayoutConstants.smallPadding),
              FilledButton.icon(
                onPressed: () =>
                    const SettingsRoute(section: .kavita).go(context),
                icon: Icon(
                  KoverIcons.settings,
                  size: LayoutConstants.smallIcon,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
                label: Text(l.openSettings),
              ),
            ],
          ),
        ),
      ),
      .certificateError => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                KoverIcons.invalidCertificate,
                size: LayoutConstants.largerIcon,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: LayoutConstants.smallPadding),
              Text(
                l.invalidCertificate,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: LayoutConstants.smallerPadding),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: LayoutConstants.mediumPadding,
                ),
                child: Text(
                  l.invalidCertificateDescription,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: LayoutConstants.smallPadding),
              FilledButton.icon(
                onPressed: () =>
                    const SettingsRoute(section: .kavita).go(context),
                icon: Icon(
                  KoverIcons.settings,
                  size: LayoutConstants.smallIcon,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
                label: Text(l.openSettings),
              ),
            ],
          ),
        ),
      ),
      .error => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                KoverIcons.alert,
                size: LayoutConstants.largerIcon,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: LayoutConstants.smallPadding),
              Text(
                l.connectionError,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: LayoutConstants.smallerPadding),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: LayoutConstants.mediumPadding,
                ),
                child: Text(
                  l.connectionErrorDescription,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: LayoutConstants.smallPadding),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    onPressed: () => ref.invalidate(currentUserProvider),
                    icon: Icon(
                      KoverIcons.retry,
                      size: LayoutConstants.smallIcon,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                    label: Text(l.retry),
                  ),
                  const SizedBox(height: LayoutConstants.smallPadding),
                  FilledButton.icon(
                    onPressed: () =>
                        const SettingsRoute(section: .kavita).go(context),
                    icon: Icon(
                      KoverIcons.settings,
                      size: LayoutConstants.smallIcon,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                    label: Text(l.openSettings),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    };
  }
}
