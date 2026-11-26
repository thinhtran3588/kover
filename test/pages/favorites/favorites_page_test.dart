import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/models/enums/local_book_source.dart';
import 'package:kover/models/local_book_model.dart';
import 'package:kover/pages/favorites/favorites_page.dart';
import 'package:kover/pages/local_library/local_book_card.dart';
import 'package:kover/riverpod/providers/google_drive_auth.dart';
import 'package:kover/riverpod/providers/local_library.dart';
import 'package:kover/riverpod/providers/settings/credentials.dart';
import 'package:kover/riverpod/providers/settings/general_settings.dart';
import 'package:kover/riverpod/providers/theme.dart' hide Theme;
import 'package:material_ui/material_ui.dart';

class _FakeSettings extends GeneralSettings {
  @override
  Future<GeneralSettingsState> build() async => const GeneralSettingsState();
}

class _FakeAuth extends GoogleDriveAuth {
  @override
  Future<DriveAuthState> build() async => const .notConfigured();
}

LocalBookModel _book(int id, String title) {
  return LocalBookModel(
    id: id,
    title: title,
    author: null,
    language: null,
    format: .epub,
    source: .device,
    remoteId: null,
    fileName: '$title.epub',
    filePath: 'local_books/$title.epub',
    fileSize: 1,
    pages: 10,
    pagesRead: 0,
    bookScrollId: null,
    lastRead: null,
    created: DateTime(2026),
  );
}

void main() {
  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          loginStatusProvider.overrideWithValue(LoginStatus.noCredentials),
          generalSettingsProvider.overrideWith(_FakeSettings.new),
          googleDriveAuthProvider.overrideWith(_FakeAuth.new),
          localBooksProvider(
            source: LocalBookSource.device,
            favoritesOnly: true,
          ).overrideWith((_) => Stream.value([_book(1, 'Dune')])),
          // The gate shows the Drive tab only when books were downloaded.
          localBooksProvider(source: LocalBookSource.googleDrive).overrideWith(
            (_) => Stream.value([_book(3, 'Drive')]),
          ),
          localBooksProvider(
            source: LocalBookSource.googleDrive,
            favoritesOnly: true,
          ).overrideWith((_) => Stream.value(const [])),
          localContinueReadingProvider.overrideWith(
            (_) => Stream.value(const []),
          ),
          localBookCoverProvider.overrideWith((_, _) async => null),
          themeProvider.overrideWithBuild(
            (_, _) async => const ThemeModel(reduceAnimations: true),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: FavoritesPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('the device tab lists favorite books', (tester) async {
    await pumpPage(tester);

    expect(find.widgetWithText(Tab, 'Kavita'), findsOneWidget);
    expect(find.byType(LocalBookCard), findsOneWidget);
  });

  testWidgets('the Kavita tab offers to connect a server', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.widgetWithText(Tab, 'Kavita'));
    await tester.pumpAndSettle();

    expect(
      find.text('Connect to your Kavita server to read its libraries.'),
      findsOneWidget,
    );
  });

  testWidgets('an empty favorites tab says so', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.widgetWithText(Tab, 'Google Drive'));
    await tester.pumpAndSettle();

    expect(find.text('No favorites yet'), findsOneWidget);
  });
}
