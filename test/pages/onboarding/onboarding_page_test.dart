import 'package:flutter_test/flutter_test.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/pages/onboarding/onboarding_page.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<void> pumpPage(WidgetTester tester, VoidCallback onDone) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: OnboardingPage(onDone: onDone),
      ),
    );
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
  }

  testWidgets('starts on the Kavita page', (tester) async {
    await pumpPage(tester, () {});

    expect(find.text('Kavita'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Get started'), findsNothing);
  });

  testWidgets('Next twice reaches On this device with Get started', (
    tester,
  ) async {
    await pumpPage(tester, () {});

    await next(tester);
    expect(find.text('Google Drive'), findsOneWidget);
    await next(tester);

    expect(find.text('On this device'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
  });

  testWidgets('swiping changes the page', (tester) async {
    await pumpPage(tester, () {});

    await tester.fling(find.byType(TabBarView), const Offset(-500, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('Google Drive'), findsOneWidget);
    expect(find.text('Kavita'), findsNothing);
  });

  testWidgets('Skip calls onDone', (tester) async {
    var done = 0;
    await pumpPage(tester, () => done++);

    await tester.tap(find.text('Skip'));

    expect(done, 1);
  });

  testWidgets('Get started calls onDone', (tester) async {
    var done = 0;
    await pumpPage(tester, () => done++);

    await next(tester);
    await next(tester);
    await tester.tap(find.text('Get started'));

    expect(done, 1);
  });
}
