import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/riverpod/providers/settings/credentials.dart';
import 'package:kover/widgets/util/login_guard.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'offers to connect a server or import files without credentials',
    (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            loginStatusProvider.overrideWithValue(LoginStatus.noCredentials),
          ],
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: LoginGuard(child: SizedBox()),
          ),
        ),
      );

      expect(find.text('Connect to Kavita server'), findsOneWidget);
      expect(find.text('Import files'), findsOneWidget);
    },
  );
}
