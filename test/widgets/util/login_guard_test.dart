import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/models/enums/local_book_source.dart';
import 'package:kover/riverpod/providers/local_library.dart';
import 'package:kover/riverpod/providers/settings/credentials.dart';
import 'package:kover/widgets/sources/source_tile.dart';
import 'package:kover/widgets/util/login_guard.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<void> pumpGuard(WidgetTester tester, {bool showAllSources = true}) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          loginStatusProvider.overrideWithValue(LoginStatus.noCredentials),
          localBooksProvider(
            source: LocalBookSource.device,
          ).overrideWith((_) => Stream.value(const [])),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: LoginGuard(
            showAllSources: showAllSources,
            child: const SizedBox(),
          ),
        ),
      ),
    );
  }

  testWidgets('offers every source without credentials', (tester) async {
    await pumpGuard(tester);

    expect(find.byType(SourceTile), findsNWidgets(3));
    expect(find.text('Kavita'), findsOneWidget);
    expect(find.text('Google Drive'), findsOneWidget);
    expect(find.text('On this device'), findsOneWidget);
  });

  testWidgets('offers only Kavita inside a source tab', (tester) async {
    await pumpGuard(tester, showAllSources: false);

    expect(find.byType(SourceTile), findsOneWidget);
    expect(find.text('Kavita'), findsWidgets);
    expect(find.text('Google Drive'), findsNothing);
  });
}
