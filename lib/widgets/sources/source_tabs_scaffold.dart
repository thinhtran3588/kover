import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/models/enums/reading_source.dart';
import 'package:kover/riverpod/providers/settings/credentials.dart';
import 'package:kover/utils/extensions/reading_source.dart';
import 'package:material_ui/material_ui.dart';

/// A page with one tab per [ReadingSource]. The first tab is [initialSource],
/// else [savedSource], else Kavita when connected, else this device.
class SourceTabsScaffold extends HookConsumerWidget {
  final String title;
  final ReadingSource? initialSource;
  final ReadingSource? savedSource;
  final ValueChanged<ReadingSource> onSourceChanged;
  final Widget Function(ReadingSource source) tabBuilder;
  final List<Widget>? actions;

  /// Actions of the selected tab, shown before [actions].
  final List<Widget> Function(ReadingSource source)? tabActions;

  const SourceTabsScaffold({
    super.key,
    required this.title,
    required this.onSourceChanged,
    required this.tabBuilder,
    this.initialSource,
    this.savedSource,
    this.actions,
    this.tabActions,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final loggedIn = ref.read(loginStatusProvider) == .loggedIn;
    final start =
        initialSource ??
        savedSource ??
        (loggedIn ? ReadingSource.kavita : ReadingSource.device);
    final vsync = useSingleTickerProvider();
    final controller = useMemoized(
      () => TabController(
        length: ReadingSource.values.length,
        initialIndex: start.index,
        vsync: vsync,
      ),
    );
    useEffect(() => controller.dispose, [controller]);

    // Lets `go()` with a new source switch tabs while the page is open.
    useEffect(() {
      final source = initialSource;
      if (source != null && controller.index != source.index) {
        controller.animateTo(source.index);
      }
      return null;
    }, [initialSource]);

    useEffect(() {
      var last = controller.index;
      void listener() {
        if (controller.indexIsChanging || controller.index == last) return;
        last = controller.index;
        onSourceChanged(ReadingSource.values[last]);
      }

      controller.addListener(listener);
      return () => controller.removeListener(listener);
    }, [controller]);

    useListenable(controller);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          ...?tabActions?.call(ReadingSource.values[controller.index]),
          ...?actions,
        ],
        bottom: TabBar(
          controller: controller,
          tabs: [
            for (final source in ReadingSource.values)
              Tab(text: source.getLabel(l)),
          ],
        ),
      ),
      body: TabBarView(
        controller: controller,
        children: [
          for (final source in ReadingSource.values)
            _KeepAlive(child: tabBuilder(source)),
        ],
      ),
    );
  }
}

/// Keeps a tab's state (filter text, scroll) while it is swiped away.
class _KeepAlive extends StatefulWidget {
  final Widget child;

  const _KeepAlive({required this.child});

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
