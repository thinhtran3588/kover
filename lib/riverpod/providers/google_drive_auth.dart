import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:kover/utils/constants/google_drive_config.dart';
import 'package:kover/utils/logging.dart';
import 'package:kover/utils/safe_platform.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'google_drive_auth.freezed.dart';
part 'google_drive_auth.g.dart';

@freezed
sealed class DriveAuthState with _$DriveAuthState {
  const factory DriveAuthState.notSupported() = DriveNotSupported;
  const factory DriveAuthState.notConfigured() = DriveNotConfigured;
  const factory DriveAuthState.signedOut() = DriveSignedOut;
  const factory DriveAuthState.signedIn({
    required String email,
    String? displayName,
    String? photoUrl,
  }) = DriveSignedIn;
}

/// The Google Drive account. Google Sign-In is only touched when the platform
/// is supported and the client IDs are configured.
@Riverpod(keepAlive: true)
class GoogleDriveAuth extends _$GoogleDriveAuth {
  static Future<void>? _initialized;

  GoogleSignInAccount? _account;

  @override
  Future<DriveAuthState> build() async {
    if (!GoogleDriveConfig.isSupportedPlatform) {
      return const .notSupported();
    }
    if (!GoogleDriveConfig.isConfigured) return const .notConfigured();

    try {
      await _initialize();
      _account = await GoogleSignIn.instance.attemptLightweightAuthentication();
    } catch (e, stacktrace) {
      log.error(
        'failed to restore google drive session',
        error: e,
        stacktrace: stacktrace,
      );
    }
    return _stateFor(_account);
  }

  /// `initialize` may only be called once per process.
  static Future<void> _initialize() {
    return _initialized ??= GoogleSignIn.instance.initialize(
      clientId: SafePlatform.isIOS ? GoogleDriveConfig.iosClientId : null,
      serverClientId: GoogleDriveConfig.serverClientId.isEmpty
          ? null
          : GoogleDriveConfig.serverClientId,
    );
  }

  static DriveAuthState _stateFor(GoogleSignInAccount? account) {
    if (account == null) return const .signedOut();
    return .signedIn(
      email: account.email,
      displayName: account.displayName,
      photoUrl: account.photoUrl,
    );
  }

  /// Signs in, returns false if the user cancelled.
  Future<bool> signIn() async {
    await _initialize();
    try {
      _account = await GoogleSignIn.instance.authenticate(
        scopeHint: GoogleDriveConfig.scopes,
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      rethrow;
    }
    state = AsyncData(_stateFor(_account));
    return true;
  }

  /// Downloaded books stay on the device.
  Future<void> signOut() async {
    await GoogleSignIn.instance.disconnect();
    _account = null;
    state = const AsyncData(.signedOut());
  }

  /// A client that authorizes requests with the read-only Drive scope. The
  /// caller must close it.
  Future<http.Client> authClient() async {
    final account = _account;
    if (account == null) throw StateError('Not signed in to Google Drive');

    final client = account.authorizationClient;
    final authorization =
        await client.authorizationForScopes(GoogleDriveConfig.scopes) ??
        await client.authorizeScopes(GoogleDriveConfig.scopes);
    return authorization.authClient(scopes: GoogleDriveConfig.scopes);
  }
}
