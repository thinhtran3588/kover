import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/models/enums/reading_source.dart';
import 'package:kover/riverpod/providers/google_drive_auth.dart';
import 'package:kover/widgets/sources/source_tile.dart';
import 'package:material_ui/material_ui.dart';

class _FakeAuth extends GoogleDriveAuth {
  final DriveAuthState value;

  _FakeAuth(this.value);

  @override
  Future<DriveAuthState> build() async => value;
}

void main() {
  Future<void> pumpTile(WidgetTester tester, DriveAuthState auth) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          googleDriveAuthProvider.overrideWith(() => _FakeAuth(auth)),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SourceTile(source: ReadingSource.googleDrive)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('shows the account email when signed in', (tester) async {
    await pumpTile(tester, const .signedIn(email: 'me@example.com'));
    expect(find.text('me@example.com'), findsOneWidget);
  });

  testWidgets('shows not connected when signed out', (tester) async {
    await pumpTile(tester, const .signedOut());
    expect(find.text('Not connected'), findsOneWidget);
  });

  testWidgets('shows not set up when not configured', (tester) async {
    await pumpTile(tester, const .notConfigured());
    expect(find.text('Not set up'), findsOneWidget);
  });

  testWidgets('shows unsupported platforms', (tester) async {
    await pumpTile(tester, const .notSupported());
    expect(
      find.text('Google Drive is available on Android and iOS'),
      findsOneWidget,
    );
  });
}
