import 'package:kover/utils/safe_platform.dart';

/// Whether the platform has a native text-to-speech engine.
bool get ttsSupported => !SafePlatform.isLinux;

/// Whether the Edge online voices can be used: they need custom WebSocket
/// headers, which the web cannot send, and an audio player that is not
/// available on Windows.
bool get edgeTtsSupported =>
    SafePlatform.isAndroid || SafePlatform.isIOS || SafePlatform.isMacOS;

class const TtsVoice({
  required final String name,
  required final String locale,
});

class const TtsUtterance({
  required final String text,
  final String? voiceName,
  final String? voiceLocale,

  /// The language of the text, used to pick a voice when none is selected.
  final String? language,

  /// Speed multiplier, 1.0 being the normal speed.
  final double rate = 1.0,
  final double pitch = 1.0,
});

sealed class TtsEvent {
  const TtsEvent();
}

final class TtsStarted extends TtsEvent {
  const TtsStarted();
}

/// The word at `[start, end)` of the utterance text is being spoken.
final class const TtsWord({required final int start, required final int end})
    extends TtsEvent {}

final class TtsDone extends TtsEvent {
  const TtsDone();
}

final class const TtsError({required final String message}) extends TtsEvent {}

abstract interface class TtsEngine {
  /// Whether [TtsWord] events are emitted while speaking.
  bool get supportsWordBoundaries;

  Future<List<TtsVoice>> voices();

  /// Speaks [utterance]. The stream ends after [TtsDone] or [TtsError], or
  /// silently when [stop] interrupts it.
  Stream<TtsEvent> speak(TtsUtterance utterance);

  /// Starts preparing an utterance that is likely spoken soon; never throws.
  void prefetch(TtsUtterance utterance);

  Future<void> stop();
}
