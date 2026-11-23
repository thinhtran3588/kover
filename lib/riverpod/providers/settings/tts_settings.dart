import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hooks_riverpod/experimental/persist.dart';
import 'package:kover/riverpod/repository/storage_repository.dart';
import 'package:kover/utils/logging.dart';
import 'package:riverpod_annotation/experimental/json_persist.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tts_settings.freezed.dart';
part 'tts_settings.g.dart';

enum TtsEngineType {
  /// The text-to-speech voices installed on the device.
  device,
}

sealed class TtsSettingsLimits {
  static const double rateMin = 0.5;
  static const double rateMax = 2.0;
  static const double rateStep = 0.05;
  static const double pitchMin = 0.5;
  static const double pitchMax = 2.0;
  static const double pitchStep = 0.05;
}

@freezed
sealed class TtsSettingsState with _$TtsSettingsState {
  const factory TtsSettingsState({
    @Default(TtsEngineType.device) TtsEngineType engine,
    String? voiceName,
    String? voiceLocale,
    @Default(1.0) double rate,
    @Default(1.0) double pitch,
    @Default(true) bool continueNextChapter,
  }) = _TtsSettingsState;

  factory TtsSettingsState.fromJson(Map<String, Object?> json) =>
      _$TtsSettingsStateFromJson(json);
}

/// Global read aloud settings, shared by all series.
@riverpod
@JsonPersist()
class TtsSettings extends _$TtsSettings {
  @override
  Future<TtsSettingsState> build() async {
    await persist(
      ref.watch(storageProvider.future),
      options: const StorageOptions(cacheTime: StorageCacheTime.unsafe_forever),
    ).future;

    return state.value ?? const TtsSettingsState();
  }

  Future<void> setEngine(TtsEngineType engine) async {
    final current = await future;

    state = AsyncData(current.copyWith(engine: engine));
    log.info('set engine', attributes: {'value': engine, 'reader': 'tts'});
  }

  /// Sets the voice, or the device default when [name] is null.
  Future<void> setVoice({String? name, String? locale}) async {
    final current = await future;

    state = AsyncData(
      current.copyWith(voiceName: name, voiceLocale: locale),
    );
    log.info(
      'set voice',
      attributes: {'value': name ?? 'default', 'reader': 'tts'},
    );
  }

  Future<void> setRate(double rate) async {
    final current = await future;

    state = AsyncData(
      current.copyWith(
        rate: rate.clamp(TtsSettingsLimits.rateMin, TtsSettingsLimits.rateMax),
      ),
    );
    log.info('set rate', attributes: {'value': rate, 'reader': 'tts'});
  }

  Future<void> setPitch(double pitch) async {
    final current = await future;

    state = AsyncData(
      current.copyWith(
        pitch: pitch.clamp(
          TtsSettingsLimits.pitchMin,
          TtsSettingsLimits.pitchMax,
        ),
      ),
    );
    log.info('set pitch', attributes: {'value': pitch, 'reader': 'tts'});
  }

  Future<void> setContinueNextChapter(bool value) async {
    final current = await future;

    state = AsyncData(current.copyWith(continueNextChapter: value));
    log.info(
      'set continue next chapter',
      attributes: {'value': value, 'reader': 'tts'},
    );
  }

  Future<void> reset() async {
    state = const AsyncData(TtsSettingsState());
    log.info('reset to default settings', attributes: {'reader': 'tts'});
  }
}
