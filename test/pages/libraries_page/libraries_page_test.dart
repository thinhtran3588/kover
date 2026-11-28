import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/models/library_model.dart';
import 'package:kover/pages/libraries_page/libraries_page.dart';
import 'package:kover/pages/libraries_page/sliver_libraries.dart';
import 'package:kover/riverpod/managers/sync_manager/sync_manager.dart';
import 'package:kover/riverpod/providers/library.dart';
import 'package:material_ui/material_ui.dart';

class _FakeSync extends SyncManager {
  @override
  SyncState build() => const SyncState.idle();

  @override
  void syncLibraries() {}
}

void main() {
  testWidgets('lists every library', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          syncManagerProvider.overrideWith(_FakeSync.new),
          librariesProvider.overrideWith(
            (_) => Stream.value(const [
              LibraryModel(id: 1, name: 'Manga', type: .manga),
              LibraryModel(id: 2, name: 'Novels', type: .book),
            ]),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: LibrariesPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(LibraryListTile), findsNWidgets(2));
    expect(find.text('Manga'), findsOneWidget);
    expect(find.text('Novels'), findsOneWidget);
  });
}
