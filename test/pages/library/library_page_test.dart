import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/models/enums/local_book_source.dart';
import 'package:kover/models/enums/reading_source.dart';
import 'package:kover/models/local_book_model.dart';
import 'package:kover/pages/library/library_page.dart';
import 'package:kover/pages/local_library/local_book_card.dart';
import 'package:kover/riverpod/providers/google_drive_auth.dart';
import 'package:kover/riverpod/providers/local_library.dart';
import 'package:kover/riverpod/providers/settings/credentials.dart';
import 'package:kover/riverpod/providers/settings/general_settings.dart';
import 'package:kover/riverpod/providers/theme.dart' hide Theme;
import 'package:kover/utils/constants/kover_icons.dart';
import 'package:kover/widgets/actions_app_bar/search_button.dart';
import 'package:kover/widgets/details/filter_input_field.dart';
import 'package:kover/widgets/list_page/list_layout_toggle_button.dart';
import 'package:kover/widgets/lists/cover_list_entry.dart';
import 'package:material_ui/material_ui.dart';

class _FakeSettings extends GeneralSettings {
  final ReadingSource? initial;
  final List<ReadingSource> saved;

  _FakeSettings(this.initial, this.saved);

  @override
  Future<GeneralSettingsState> build() async =>
      GeneralSettingsState(librarySource: initial);

  @override
  Future<void> setLibrarySource(ReadingSource value) async {
    saved.add(value);
  }
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
  Future<void> pumpPage(
    WidgetTester tester, {
    ReadingSource? initial,
    List<ReadingSource>? saved,
  }) async {
    tester.view.physicalSize = const Size(600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          loginStatusProvider.overrideWithValue(LoginStatus.noCredentials),
          generalSettingsProvider.overrideWith(
            () => _FakeSettings(initial, saved ?? []),
          ),
          googleDriveAuthProvider.overrideWith(_FakeAuth.new),
          localBooksProvider(source: LocalBookSource.device).overrideWith(
            (_) => Stream.value([_book(1, 'Dune'), _book(2, 'Emma')]),
          ),
          localBooksProvider(
            source: LocalBookSource.googleDrive,
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
          home: LibraryPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('shows the three source tabs and starts on this device', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.widgetWithText(Tab, 'Kavita'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Google Drive'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'On this device'), findsOneWidget);
    expect(find.byType(LocalBookCard), findsNWidgets(2));
  });

  testWidgets('offers search without a Kavita server and no filter', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.byType(SearchButton), findsOneWidget);
    expect(find.byType(FilterInputField), findsNothing);
  });

  testWidgets('the header holds the layout toggle and sort of the tab', (
    tester,
  ) async {
    await pumpPage(tester);

    final header = find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(ListLayoutToggleButton),
    );
    expect(header, findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(KoverIcons.sort),
      ),
      findsOneWidget,
    );
    // Nothing is left in the tab body.
    expect(find.byType(ListLayoutToggleButton), findsOneWidget);
  });

  testWidgets('the header toggle switches the books to a list', (tester) async {
    await pumpPage(tester);

    expect(find.byType(CoverListEntry), findsNothing);

    await tester.tap(find.byType(ListLayoutToggleButton));
    await tester.pump();
    await tester.pump();

    expect(find.byType(CoverListEntry), findsNWidgets(2));
    expect(find.byType(LocalBookCard), findsNWidgets(2));

    await tester.tap(find.byType(ListLayoutToggleButton));
    await tester.pump();
    await tester.pump();

    expect(find.byType(CoverListEntry), findsNothing);
  });

  testWidgets('the header controls follow the selected tab', (tester) async {
    await pumpPage(tester);
    expect(find.byType(ListLayoutToggleButton), findsOneWidget);

    // Google Drive is not set up, so its tab shows no list to control.
    await tester.tap(find.widgetWithText(Tab, 'Google Drive'));
    await tester.pumpAndSettle();
    expect(find.byType(ListLayoutToggleButton), findsNothing);
    expect(find.byIcon(KoverIcons.sort), findsNothing);

    await tester.tap(find.widgetWithText(Tab, 'On this device'));
    await tester.pumpAndSettle();
    expect(find.byType(ListLayoutToggleButton), findsOneWidget);
  });

  testWidgets('the Kavita tab offers to connect a server', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.widgetWithText(Tab, 'Kavita'));
    await tester.pumpAndSettle();

    expect(
      find.text('Connect your Kavita server to read its libraries.'),
      findsNothing,
    );
    expect(
      find.text('Connect to your Kavita server to read its libraries.'),
      findsOneWidget,
    );
    expect(find.byType(ActionChip), findsNothing);
  });

  testWidgets('the Google Drive tab offers setup without downloads', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.tap(find.widgetWithText(Tab, 'Google Drive'));
    await tester.pumpAndSettle();

    expect(find.text('Not set up'), findsOneWidget);
    expect(find.byType(LocalBookCard), findsNothing);
  });

  testWidgets('swiping switches tabs', (tester) async {
    await pumpPage(tester);

    await tester.fling(find.byType(TabBarView), const Offset(500, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.byType(LocalBookCard), findsNothing);
    expect(find.text('Not set up'), findsOneWidget);
  });

  testWidgets('starts on the saved tab', (tester) async {
    await pumpPage(tester, initial: ReadingSource.googleDrive);

    expect(find.text('Not set up'), findsOneWidget);
    expect(find.byType(LocalBookCard), findsNothing);
  });

  testWidgets('changing tab saves it', (tester) async {
    final saved = <ReadingSource>[];
    await pumpPage(tester, saved: saved);

    await tester.tap(find.widgetWithText(Tab, 'Google Drive'));
    await tester.pumpAndSettle();

    expect(saved, [ReadingSource.googleDrive]);
  });
}
