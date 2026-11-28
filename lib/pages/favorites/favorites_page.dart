import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/models/enums/local_book_source.dart';
import 'package:kover/models/enums/reading_source.dart';
import 'package:kover/pages/local_library/local_library_page.dart';
import 'package:kover/pages/want_to_read_page/want_to_read_page.dart';
import 'package:kover/riverpod/providers/settings/general_settings.dart';
import 'package:kover/widgets/actions_app_bar/search_button.dart';
import 'package:kover/widgets/list_page/series_view_actions.dart';
import 'package:kover/widgets/sources/source_gate.dart';
import 'package:kover/widgets/sources/source_tabs_scaffold.dart';
import 'package:kover/widgets/util/async_value.dart';
import 'package:material_ui/material_ui.dart';

/// The favorite books of every reading source, one tab each.
class FavoritesPage extends ConsumerWidget {
  final ReadingSource? source;

  const FavoritesPage({super.key, this.source});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);

    return Async(
      asyncValue: ref.watch(generalSettingsProvider),
      data: (settings) => SourceTabsScaffold(
        title: l.wantToRead,
        tabActions: (source) => [
          SourceGate(
            source: source,
            fallback: const SizedBox.shrink(),
            child: switch (source) {
              .kavita => const SeriesViewActions(scope: .favorites),
              .googleDrive => const LocalViewActions(
                source: LocalBookSource.googleDrive,
                favoritesOnly: true,
              ),
              .device => const LocalViewActions(
                source: LocalBookSource.device,
                favoritesOnly: true,
              ),
            },
          ),
        ],
        actions: const [SearchButton()],
        initialSource: source,
        savedSource: settings.favoritesSource,
        onSourceChanged: (value) => ref
            .read(generalSettingsProvider.notifier)
            .setFavoritesSource(value),
        tabBuilder: (source) => SourceGate(
          source: source,
          child: switch (source) {
            .kavita => const WantToReadPageContent(
              showAppBar: false,
              showFilter: false,
              viewScope: .favorites,
            ),
            .googleDrive => const LocalBooksView(
              source: LocalBookSource.googleDrive,
              favoritesOnly: true,
              showFilter: false,
            ),
            .device => const LocalBooksView(
              source: LocalBookSource.device,
              favoritesOnly: true,
              showFilter: false,
            ),
          },
        ),
      ),
    );
  }
}
