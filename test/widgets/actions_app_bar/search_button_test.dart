import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/models/chapter_model.dart';
import 'package:kover/models/enums/local_book_source.dart';
import 'package:kover/models/local_book_model.dart';
import 'package:kover/models/series_model.dart';
import 'package:kover/models/volume_model.dart';
import 'package:kover/riverpod/providers/library.dart';
import 'package:kover/riverpod/providers/local_library.dart';
import 'package:kover/riverpod/providers/series.dart';
import 'package:kover/riverpod/providers/settings/credentials.dart';
import 'package:kover/riverpod/providers/theme.dart' hide Theme;
import 'package:kover/riverpod/providers/volume.dart';
import 'package:kover/riverpod/providers/chapter.dart';
import 'package:kover/widgets/actions_app_bar/search_button.dart';
import 'package:material_ui/material_ui.dart';

LocalBookModel _book(
  int id,
  String title,
  LocalBookSource source, {
  String? author,
}) {
  return LocalBookModel(
    id: id,
    title: title,
    author: author,
    language: null,
    format: .epub,
    source: source,
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

SeriesModel _series(int id, String name) {
  return SeriesModel(
    id: id,
    libraryId: 1,
    name: name,
    format: .epub,
    pages: 10,
    avgHoursToRead: 0,
    wordCount: null,
    primaryColor: null,
    secondaryColor: null,
    lastSynced: null,
  );
}

void main() {
  var kavitaReads = 0;
  String? openedPath;

  Future<void> pumpSearch(
    WidgetTester tester, {
    LoginStatus status = LoginStatus.loggedIn,
    List<LocalBookModel> books = const [],
    List<SeriesModel> series = const [],
  }) async {
    kavitaReads = 0;
    openedPath = null;
    tester.view.physicalSize = const Size(600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              const Scaffold(body: Center(child: SearchButton())),
        ),
        GoRoute(
          path: '/reader/:seriesId',
          builder: (_, state) {
            openedPath = state.uri.toString();
            return const Scaffold();
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          loginStatusProvider.overrideWithValue(status),
          searchSeriesProvider.overrideWith((_, _) async {
            kavitaReads++;
            return series;
          }),
          searchVolumesProvider.overrideWith((_, _) async {
            kavitaReads++;
            return const <VolumeModel>[];
          }),
          searchChaptersProvider.overrideWith((_, _) async {
            kavitaReads++;
            return const <ChapterModel>[];
          }),
          seriesProgressProvider.overrideWith((_, _) => Stream.value(0.0)),
          seriesCoverProvider.overrideWith((_, _) => Stream.value(null)),
          libraryProvider.overrideWith((_, _) => const Stream.empty()),
          searchLocalBooksProvider.overrideWith((ref, query) async {
            final needle = query.toLowerCase();
            final result = <LocalBookSource, List<LocalBookModel>>{};
            for (final book in books) {
              if (book.title.toLowerCase().contains(needle)) {
                result.putIfAbsent(book.source, () => []).add(book);
              }
            }
            return result;
          }),
          localBookCoverProvider.overrideWith((_, _) async => null),
          themeProvider.overrideWithBuild(
            (_, _) async => const ThemeModel(reduceAnimations: true),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.pumpAndSettle();
  }

  testWidgets('shows Kavita and book sections, hiding empty ones', (
    tester,
  ) async {
    await pumpSearch(
      tester,
      series: [_series(1, 'Dune series')],
      books: [_book(1, 'Dune', .device, author: 'Frank Herbert')],
    );

    expect(find.text('Search all sources'), findsOneWidget);
    await search(tester, 'dune');

    expect(find.text('Kavita - Series'), findsOneWidget);
    expect(find.text('Dune series'), findsOneWidget);
    expect(find.text('On this device'), findsOneWidget);
    expect(find.text('Frank Herbert'), findsOneWidget);
    expect(find.text('Kavita - Volumes'), findsNothing);
    expect(find.text('Kavita - Chapters'), findsNothing);
    expect(find.text('Google Drive'), findsNothing);
  });

  testWidgets('without Kavita credentials only books are searched', (
    tester,
  ) async {
    await pumpSearch(
      tester,
      status: LoginStatus.noCredentials,
      series: [_series(1, 'Dune series')],
      books: [_book(2, 'Dune', .googleDrive)],
    );

    await search(tester, 'dune');

    expect(kavitaReads, 0);
    expect(find.text('Kavita - Series'), findsNothing);
    expect(find.text('Dune series'), findsNothing);
    expect(find.text('Google Drive'), findsOneWidget);
  });

  testWidgets('says so when nothing matches', (tester) async {
    await pumpSearch(
      tester,
      books: [_book(1, 'Dune', .device)],
    );

    await search(tester, 'zzz');

    expect(find.text('No results'), findsOneWidget);
  });

  testWidgets('tapping a book opens it in the reader', (tester) async {
    await pumpSearch(
      tester,
      status: LoginStatus.noCredentials,
      books: [_book(7, 'Dune', .device)],
    );

    await search(tester, 'dune');
    await tester.tap(find.byType(SearchBookEntry));
    await tester.pumpAndSettle();

    expect(openedPath, startsWith('/reader/-7'));
  });
}
