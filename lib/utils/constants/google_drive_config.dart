import 'package:googleapis/drive/v3.dart' as drive;
import 'package:kover/utils/safe_platform.dart';

/// Build-time configuration for Google Drive. The client IDs are supplied with
/// `--dart-define-from-file=config/google_drive.json`, see
/// `docs/google-drive-setup.md`.
abstract class GoogleDriveConfig {
  static const iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  /// Web application OAuth client ID; required by google_sign_in on Android.
  static const serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  static const scopes = [drive.DriveApi.driveReadonlyScope];

  static bool get isSupportedPlatform =>
      SafePlatform.isAndroid || SafePlatform.isIOS;

  /// Whether sign in can be attempted. Google Sign-In is never called when
  /// this is false.
  static bool get isConfigured =>
      isSupportedPlatform &&
      (SafePlatform.isIOS ? iosClientId.isNotEmpty : serverClientId.isNotEmpty);
}
