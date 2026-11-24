import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/experimental/persist.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/riverpod/providers/settings/tts_settings.dart';
import 'package:kover/riverpod/repository/storage_repository.dart';

void main() {
  test('keeps the chosen voice after a restart', () async {
    final storage = Storage<String, String>.inMemory();
    ProviderContainer app() => ProviderContainer.test(
      overrides: [storageProvider.overrideWith((ref) => storage)],
    );

    final first = app();
    await first.read(ttsSettingsProvider.future);
    await first
        .read(ttsSettingsProvider.notifier)
        .setEngine(TtsEngineType.edge);
    await first
        .read(ttsSettingsProvider.notifier)
        .setVoice(name: 'vi-VN-HoaiMyNeural', locale: 'vi-VN');
    await Future<void>.delayed(Duration.zero);
    first.dispose();

    final settings = await app().read(ttsSettingsProvider.future);
    expect(settings.engine, TtsEngineType.edge);
    expect(settings.voiceName, 'vi-VN-HoaiMyNeural');
    expect(settings.voiceLocale, 'vi-VN');
  });
}
