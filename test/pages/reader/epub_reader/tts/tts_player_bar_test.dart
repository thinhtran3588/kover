import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/pages/reader/epub_reader/tts/tts_player_bar.dart';
import 'package:kover/riverpod/providers/settings/tts_settings.dart';
import 'package:kover/riverpod/providers/tts/tts_player.dart';
import 'package:kover/utils/constants/layout_constants.dart';

void main() {
  Future<void> pumpBar(WidgetTester tester, Size size, TtsStatus status) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ttsPlayerProvider.overrideWithBuild(
            (_, _) => TtsPlayerState(status: status),
          ),
          ttsSettingsProvider.overrideWithBuild(
            (_, _) => const TtsSettingsState(),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: TtsPlayerBar(seriesId: 1)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('is hidden while idle', (tester) async {
    await pumpBar(tester, const Size(400, 800), .idle);

    expect(find.byType(Card), findsNothing);
  });

  testWidgets('lays out as a row in portrait', (tester) async {
    await pumpBar(tester, const Size(400, 800), .playing);

    final first = tester.getTopLeft(find.byType(IconButton).first);
    final last = tester.getTopLeft(find.byType(IconButton).last);
    expect(last.dy, first.dy);
  });

  testWidgets('lays out as a vertical rail below 480dp of height', (
    tester,
  ) async {
    await pumpBar(tester, const Size(1024, 400), .playing);

    final first = tester.getTopLeft(find.byType(IconButton).first);
    final last = tester.getTopLeft(find.byType(IconButton).last);
    expect(last.dx, first.dx);
    expect(last.dy, greaterThan(first.dy));
    expect(
      tester.getSize(find.byType(IconButton).first).width,
      greaterThanOrEqualTo(LayoutConstants.minTapTarget),
    );
  });
}
