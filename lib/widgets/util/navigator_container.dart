import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:kover/utils/constants/kover_icons.dart';
import 'package:kover/widgets/util/breakpoint_builder.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/pages/onboarding/onboarding_page.dart';
import 'package:kover/riverpod/providers/settings/oneoffs.dart';
import 'package:kover/riverpod/providers/theme.dart' hide Theme;
import 'package:kover/utils/constants/layout_constants.dart';
import 'package:kover/utils/safe_platform.dart';
import 'package:kover/widgets/util/async_value.dart';
import 'package:kover/widgets/util/monitoring_opt_out_popup.dart';

/// The fixed destinations, in the order of the shell branches.
enum _Destination {
  library(KoverIcons.library),
  favorites(KoverIcons.wantToRead),
  settings(KoverIcons.settings);

  const _Destination(this.icon);

  final IconData icon;

  String getLabel(AppLocalizations l) => switch (this) {
    .library => l.library,
    .favorites => l.wantToRead,
    .settings => l.settings,
  };
}

class NavigatorContainer extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const NavigatorContainer({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oneOffs = ref.watch(oneOffsProvider);

    if (oneOffs.isLoading && !oneOffs.hasValue) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (oneOffs.value?.onboardingShown == false) {
      return OnboardingPage(
        onDone: () => ref.read(oneOffsProvider.notifier).setOnboardingShown(),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      oneOffs.whenData((oneOffs) async {
        if (!oneOffs.monitoringOptOutPopupShown) {
          await showDialog(
            context: context,
            builder: (context) => const MonitoringOptOutPopup(),
          );
          await ref
              .read(oneOffsProvider.notifier)
              .setMonitoringOptOutPopupShown();
        }
      });
    });

    final selectedIndex = navigationShell.currentIndex;
    void onDestinationSelected(int index) {
      navigationShell.goBranch(index, initialLocation: true);
    }

    return BreakpointBuilder(
      compactBuilder: (context) {
        return _CompactNavigationShell(
          navigationShell: navigationShell,
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
        );
      },
      // Landscape phones and car screens get the side rail too.
      mediumBuilder: (context) {
        return _ExpandedNavigationLayout(
          key: const ValueKey('expanded_navigation_layout'),
          navigationShell: navigationShell,
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
        );
      },
      expandedBuilder: (context) {
        return _ExpandedNavigationLayout(
          key: const ValueKey('expanded_navigation_layout'),
          navigationShell: navigationShell,
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
        );
      },
      largestBuilder: (context) {
        return _ExpandedNavigationLayout(
          key: const ValueKey('largest_navigation_layout'),
          navigationShell: navigationShell,
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          startExtended: true,
        );
      },
    );
  }
}

class _CompactNavigationShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  final int selectedIndex;
  final void Function(int) onDestinationSelected;

  const new({
    required this.navigationShell,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = ref.watch(themeProvider);

    return Scaffold(
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(
          left: LayoutConstants.mediumPadding,
          right: LayoutConstants.mediumPadding,
          bottom: LayoutConstants.mediumPadding,
        ),
        child: SafeArea(
          bottom: !SafePlatform.isIOS, // iOS safe area is way too aggressive
          child: MediaQuery.removePadding(
            context: context,
            removeBottom: true,
            removeTop: true,
            child: Async(
              asyncValue: theme,
              data: (theme) {
                return Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: .hardEdge,
                  shape: RoundedRectangleBorder(
                    side: theme.outlined
                        ? BorderSide(
                            color: Theme.of(context).colorScheme.outline,
                            width: 2.0,
                          )
                        : BorderSide.none,
                    borderRadius: BorderRadius.circular(24.0),
                  ),
                  child: NavigationBar(
                    selectedIndex: selectedIndex,
                    onDestinationSelected: onDestinationSelected,
                    destinations: [
                      for (final destination in _Destination.values)
                        NavigationDestination(
                          icon: Icon(destination.icon),
                          label: destination.getLabel(l),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpandedNavigationLayout extends HookWidget {
  final StatefulNavigationShell navigationShell;
  final int selectedIndex;
  final void Function(int) onDestinationSelected;
  final bool startExtended;

  const new({
    super.key,
    required this.navigationShell,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.startExtended = false,
  });

  @override
  Widget build(BuildContext context) {
    final extended = useState(startExtended);

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: extended.value,
            labelType: extended.value ? .none : .all,
            scrollable: true,
            trailingAtBottom: true,
            trailing: Padding(
              padding: LayoutConstants.smallestEdgeInsets,
              child: IconButton(
                icon: Icon(
                  extended.value
                      ? KoverIcons.collapsePanel
                      : KoverIcons.expandPanel,
                ),
                onPressed: () {
                  extended.value = !extended.value;
                },
              ),
            ),
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            destinations: [
              for (final destination in _Destination.values)
                NavigationRailDestination(
                  icon: Icon(destination.icon),
                  label: Text(
                    destination.getLabel(AppLocalizations.of(context)),
                  ),
                ),
            ],
          ),
          const VerticalDivider(width: 1.0, thickness: 1.0),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}
