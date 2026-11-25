import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/models/enums/local_book_source.dart';
import 'package:kover/models/local_book_model.dart';
import 'package:kover/pages/local_library/local_book_card.dart';
import 'package:kover/pages/local_library/local_library_page.dart';
import 'package:kover/riverpod/providers/local_library.dart';
import 'package:kover/riverpod/providers/theme.dart' hide Theme;
import 'package:material_ui/material_ui.dart';

LocalBookModel _book(int id, String title, {int pagesRead = 0}) {
  return LocalBookModel(
    id: id,
    title: title,
    author: null,
    language: null,
    format: .epub,
    source: LocalBookSource.device,
    remoteId: null,
    fileName: '$title.epub',
    filePath: 'local_books/$title.epub',
    fileSize: 1,
    pages: 10,
    pagesRead: pagesRead,
    bookScrollId: null,
    lastRead: null,
    created: DateTime(2026),
  );
}

void main() {
  Future<void> pumpPage(
    WidgetTester tester,
    List<LocalBookModel> books,
  ) async {
    tester.view.physicalSize = const Size(600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localBooksProvider().overrideWith((_) => Stream.value(books)),
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
          home: LocalLibraryPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('shows the empty state with an import button', (tester) async {
    await pumpPage(tester, const []);

    expect(find.text('No books on this device yet'), findsOneWidget);
    expect(find.text('Import files'), findsOneWidget);
    expect(find.byType(LocalBookCard), findsNothing);
  });

  testWidgets('shows a card per book', (tester) async {
    await pumpPage(tester, [_book(1, 'Dune'), _book(2, 'Emma')]);

    expect(find.byType(LocalBookCard), findsNWidgets(2));
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Emma'), findsOneWidget);
    expect(find.text('No books on this device yet'), findsNothing);
  });

  testWidgets('filters books by title', (tester) async {
    await pumpPage(tester, [_book(1, 'Dune'), _book(2, 'Emma')]);

    await tester.enterText(find.byType(TextField), 'emm');
    await tester.pump();

    expect(find.text('Dune'), findsNothing);
    expect(find.text('Emma'), findsOneWidget);
  });
}
