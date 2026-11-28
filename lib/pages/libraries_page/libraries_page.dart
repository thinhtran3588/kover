import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/pages/libraries_page/sliver_libraries.dart';
import 'package:kover/riverpod/managers/sync_manager/sync_manager.dart';
import 'package:kover/widgets/util/sliver_adaptive_padding.dart';
import 'package:kover/widgets/util/sliver_bottom_padding.dart';
import 'package:material_ui/material_ui.dart';

class LibrariesPage extends ConsumerWidget {
  const LibrariesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncManagerProvider.notifier).syncLibraries();
    });

    return Scaffold(
      appBar: AppBar(title: Text(l.libraries)),
      body: const CustomScrollView(
        slivers: [
          SliverAdaptivePadding(sliver: SliverLibraries()),
          SliverBottomPadding(),
        ],
      ),
    );
  }
}
