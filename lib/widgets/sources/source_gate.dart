import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/models/enums/local_book_source.dart';
import 'package:kover/models/enums/reading_source.dart';
import 'package:kover/riverpod/providers/google_drive_auth.dart';
import 'package:kover/riverpod/providers/local_library.dart';
import 'package:kover/riverpod/providers/settings/credentials.dart';
import 'package:kover/utils/safe_platform.dart';
import 'package:kover/widgets/sources/source_connect_state.dart';
import 'package:kover/widgets/util/login_guard.dart';
import 'package:material_ui/material_ui.dart';

/// Shows [child] when [source] is usable, otherwise a state that explains how
/// to connect it. Downloaded Google Drive books stay readable when signed out.
class SourceGate extends ConsumerWidget {
  final ReadingSource source;
  final Widget child;

  /// Shown instead of the connect state, e.g. to hide header controls.
  final Widget? fallback;

  const SourceGate({
    super.key,
    required this.source,
    required this.child,
    this.fallback,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (source) {
      case .kavita:
        return fallback != null
            ? (ref.watch(loginStatusProvider) == .loggedIn ? child : fallback!)
            : LoginGuard(showAllSources: false, child: child);
      case .device:
        return SafePlatform.supportsLocalLibrary
            ? child
            : fallback ?? const SourceConnectState(source: .device);
      case .googleDrive:
        final hasBooks =
            ref
                .watch(localBooksProvider(source: LocalBookSource.googleDrive))
                .value
                ?.isNotEmpty ??
            false;
        final signedIn =
            ref.watch(googleDriveAuthProvider).value is DriveSignedIn;
        return hasBooks || signedIn
            ? child
            : fallback ?? const SourceConnectState(source: .googleDrive);
    }
  }
}
