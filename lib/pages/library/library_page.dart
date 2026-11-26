import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/models/enums/local_book_source.dart';
import 'package:kover/models/enums/reading_source.dart';
import 'package:kover/pages/local_library/local_library_page.dart';
import 'package:kover/pages/series_page/series_page.dart';
import 'package:kover/riverpod/providers/settings/general_settings.dart';
import 'package:kover/widgets/sources/source_gate.dart';
import 'package:kover/widgets/sources/source_tabs_scaffold.dart';
import 'package:kover/widgets/util/async_value.dart';
import 'package:material_ui/material_ui.dart';

/// The books of every reading source, one tab each.
class LibraryPage extends ConsumerWidget {
  final ReadingSource? source;

  const LibraryPage({super.key, this.source});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);

    return Async(
      asyncValue: ref.watch(generalSettingsProvider),
      data: (settings) => SourceTabsScaffold(
        title: l.library,
        initialSource: source,
        savedSource: settings.librarySource,
        onSourceChanged: (value) =>
            ref.read(generalSettingsProvider.notifier).setLibrarySource(value),
        tabBuilder: (source) => SourceGate(
          source: source,
          child: switch (source) {
            .kavita => SeriesPage(title: l.allSeries, showAppBar: false),
            .googleDrive => const LocalBooksView(
              source: LocalBookSource.googleDrive,
            ),
            .device => const LocalBooksView(source: LocalBookSource.device),
          },
        ),
      ),
    );
  }
}
