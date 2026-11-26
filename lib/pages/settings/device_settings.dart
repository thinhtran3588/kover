import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/models/enums/local_book_source.dart';
import 'package:kover/pages/local_library/add_books_sheet.dart';
import 'package:kover/riverpod/providers/local_library.dart';
import 'package:kover/utils/constants/kover_icons.dart';
import 'package:kover/utils/constants/layout_constants.dart';
import 'package:kover/utils/extensions/int.dart';
import 'package:kover/utils/safe_platform.dart';
import 'package:kover/widgets/util/async_value.dart';
import 'package:material_ui/material_ui.dart';

class DeviceSettings extends ConsumerWidget {
  const DeviceSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);

    return Card(
      margin: .zero,
      child: Padding(
        padding: LayoutConstants.mediumEdgeInsets,
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          spacing: LayoutConstants.mediumPadding,
          children: [
            Text(
              l.onThisDevice,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (!SafePlatform.supportsLocalLibrary)
              Text(l.sourceNotAvailable)
            else ...[
              Async(
                asyncValue: ref.watch(
                  localBooksProvider(source: LocalBookSource.device),
                ),
                data: (books) => Text(
                  l.deviceStorageSummary(
                    books.length,
                    books
                        .fold<int>(0, (sum, b) => sum + b.fileSize)
                        .prettyBytes(),
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: () => importBooks(context, ref),
                icon: const Icon(KoverIcons.add),
                label: Text(l.importFiles),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
