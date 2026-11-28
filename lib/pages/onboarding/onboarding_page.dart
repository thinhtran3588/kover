import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/models/enums/reading_source.dart';
import 'package:kover/utils/constants/layout_constants.dart';
import 'package:kover/utils/extensions/reading_source.dart';
import 'package:material_ui/material_ui.dart';

/// A swipeable one-time introduction to the three reading sources.
class OnboardingPage extends HookWidget {
  final VoidCallback onDone;

  const OnboardingPage({super.key, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final vsync = useSingleTickerProvider();
    final controller = useMemoized(
      () => TabController(length: ReadingSource.values.length, vsync: vsync),
    );
    useEffect(() => controller.dispose, [controller]);
    // Rebuilds when the page changes, to swap Next for Get started.
    useListenable(controller);
    final isLast = controller.index == ReadingSource.values.length - 1;

    String description(ReadingSource source) => switch (source) {
      .kavita => l.onboardingKavitaDescription,
      .googleDrive => l.onboardingDriveDescription,
      .device => l.onboardingDeviceDescription,
    };

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: TabBarView(
                controller: controller,
                children: [
                  for (final source in ReadingSource.values)
                    Padding(
                      padding: LayoutConstants.largeEdgeInsets,
                      child: Column(
                        mainAxisAlignment: .center,
                        children: [
                          Icon(
                            source.icon,
                            size: LayoutConstants.largestIcon,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: LayoutConstants.mediumPadding),
                          Text(
                            source.getLabel(l),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: .bold,
                            ),
                            textAlign: .center,
                          ),
                          const SizedBox(
                            height: LayoutConstants.smallerPadding,
                          ),
                          Text(description(source), textAlign: .center),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const .symmetric(
                horizontal: LayoutConstants.largePadding,
              ),
              child: Text(
                l.onboardingSetupHint,
                style: theme.textTheme.bodySmall,
                textAlign: .center,
              ),
            ),
            const SizedBox(height: LayoutConstants.mediumPadding),
            TabPageSelector(controller: controller),
            Padding(
              padding: LayoutConstants.mediumEdgeInsets,
              child: Row(
                mainAxisAlignment: .spaceBetween,
                children: [
                  TextButton(onPressed: onDone, child: Text(l.onboardingSkip)),
                  FilledButton(
                    onPressed: isLast
                        ? onDone
                        : () => controller.animateTo(controller.index + 1),
                    child: Text(
                      isLast ? l.onboardingGetStarted : l.onboardingNext,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
