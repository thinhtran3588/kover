import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/models/enums/local_book_source.dart';
import 'package:kover/models/enums/reading_source.dart';
import 'package:kover/riverpod/providers/auth.dart';
import 'package:kover/riverpod/providers/google_drive_auth.dart';
import 'package:kover/riverpod/providers/local_library.dart';
import 'package:kover/riverpod/providers/router.dart';
import 'package:kover/riverpod/providers/settings/credentials.dart';
import 'package:kover/utils/constants/kover_icons.dart';
import 'package:kover/utils/extensions/int.dart';
import 'package:kover/utils/extensions/reading_source.dart';
import 'package:kover/utils/safe_platform.dart';
import 'package:material_ui/material_ui.dart';

/// Takes the user to where [source] is set up or used.
void openSourceSetup(BuildContext context, ReadingSource source) {
  switch (source) {
    case .kavita:
      const SettingsRoute(section: .kavita).go(context);
    case .googleDrive:
      const GoogleDriveRoute().push(context);
    case .device:
      const LocalLibraryRoute().go(context);
  }
}

/// A reading source with its connection status. Tapping it opens the place
/// where the source is set up.
class SourceTile extends ConsumerWidget {
  final ReadingSource source;

  const SourceTile({super.key, required this.source});

  String? _status(AppLocalizations l, WidgetRef ref) {
    switch (source) {
      case .kavita:
        if (ref.watch(loginStatusProvider) != .loggedIn) {
          return l.sourceNotConnected;
        }
        return ref.watch(currentUserProvider).value?.username;
      case .googleDrive:
        return switch (ref.watch(googleDriveAuthProvider).value) {
          null => null,
          DriveNotSupported() => l.driveNotSupported,
          DriveNotConfigured() => l.driveNotSetUp,
          DriveSignedOut() => l.sourceNotConnected,
          DriveSignedIn(:final email) => email,
        };
      case .device:
        if (!SafePlatform.supportsLocalLibrary) return l.sourceNotAvailable;
        final books = ref
            .watch(localBooksProvider(source: LocalBookSource.device))
            .value;
        if (books == null) return null;
        return l.deviceStorageSummary(
          books.length,
          books.fold<int>(0, (sum, b) => sum + b.fileSize).prettyBytes(),
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final status = _status(l, ref);

    return Card.filled(
      margin: .zero,
      child: ListTile(
        leading: Icon(source.icon),
        title: Text(source.getLabel(l)),
        subtitle: status == null ? null : Text(status),
        trailing: const Icon(KoverIcons.chevronRight),
        onTap: () => openSourceSetup(context, source),
      ),
    );
  }
}
