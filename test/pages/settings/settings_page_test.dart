import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/models/enums/local_book_source.dart';
import 'package:kover/pages/settings/settings_page.dart';
import 'package:kover/pages/settings/settings_section.dart';
import 'package:kover/riverpod/providers/google_drive_auth.dart';
import 'package:kover/riverpod/providers/local_library.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<void> pumpPage(WidgetTester tester, SettingsSection section) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localBooksProvider(
            source: LocalBookSource.device,
          ).overrideWith((_) => Stream.value(const [])),
          googleDriveAuthProvider.overrideWith(GoogleDriveAuthSignedOut.new),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsPage(section: section),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('shows the four source tabs', (tester) async {
    await pumpPage(tester, .device);

    expect(find.text('General'), findsOneWidget);
    expect(find.text('Kavita'), findsOneWidget);
    expect(find.text('Google Drive'), findsOneWidget);
    expect(find.text('On this device'), findsWidgets);
  });

  testWidgets('opens the requested section', (tester) async {
    await pumpPage(tester, .device);

    expect(find.text('Import files'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsNothing);
  });

  testWidgets('switching to the Google Drive tab shows the account', (
    tester,
  ) async {
    await pumpPage(tester, .device);

    await tester.tap(find.text('Google Drive'));
    await tester.pumpAndSettle();

    expect(find.text('Google account'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
  });
}

class GoogleDriveAuthSignedOut extends GoogleDriveAuth {
  @override
  Future<DriveAuthState> build() async => const .signedOut();
}
