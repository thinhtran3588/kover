import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:kover/riverpod/providers/reader.dart';
import 'package:kover/riverpod/providers/reader/epub_reader.dart';
import 'package:kover/riverpod/providers/settings/tts_settings.dart';
import 'package:kover/riverpod/providers/tts/native_tts_engine.dart';
import 'package:kover/riverpod/providers/tts/tts_engine.dart';
import 'package:kover/riverpod/providers/tts/tts_segments.dart';
import 'package:kover/utils/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tts_player.freezed.dart';
part 'tts_player.g.dart';

enum TtsStatus { idle, loading, playing, paused, error }

@freezed
class TtsCursor({
  required final int seriesId,
  required final int chapterId,
  required final int? readingListId,
  required final int page,
  required final int segment,
}) with _$TtsCursor;

@freezed
class TtsPlayerState({
  final TtsStatus status = TtsStatus.idle,
  final TtsCursor? cursor,

  /// The chapter ended and the reader is expected to open the next one, which
  /// then calls [TtsPlayer.start].
  final bool pendingAutoStart = false,
}) with _$TtsPlayerState;

@Riverpod(keepAlive: true)
TtsEngine ttsEngine(Ref ref) => NativeTtsEngine();

@riverpod
Future<List<TtsVoice>> ttsVoices(Ref ref) =>
    ref.watch(ttsEngineProvider).voices();

/// Reads an EPUB aloud sentence by sentence.
///
/// The player only moves the reading position through [EpubNavigation], so
/// reading progress is saved by the same path as when turning pages.
@Riverpod(keepAlive: true)
class TtsPlayer extends _$TtsPlayer {
  List<TtsSegment> _segments = const [];
  StreamSubscription<TtsEvent>? _speech;
  ProviderSubscription<AsyncValue<EpubNavigationState>>? _navSubscription;
  var _generation = 0;
  int? _expectedPage;
  int? _expectedSubpage;
  var _awaitingPosition = false;
  var _keepPaused = false;

  @override
  TtsPlayerState build() {
    ref.onDispose(() {
      _speech?.cancel();
      _navSubscription?.close();
    });
    return TtsPlayerState();
  }

  TtsEngine get _engine => ref.read(ttsEngineProvider);

  EpubNavigation _navNotifier(TtsCursor cursor) =>
      ref.read(_navProvider(cursor).notifier);

  static EpubNavigationProvider _navProvider(TtsCursor cursor) =>
      epubNavigationProvider(
        seriesId: cursor.seriesId,
        chapterId: cursor.chapterId,
        readingListId: cursor.readingListId,
      );

  /// Starts reading at the current position of the reader.
  Future<void> start({
    required int seriesId,
    required int chapterId,
    required int? readingListId,
  }) async {
    await _interrupt();
    final generation = _generation;

    final nav = epubNavigationProvider(
      seriesId: seriesId,
      chapterId: chapterId,
      readingListId: readingListId,
    );
    state = TtsPlayerState(
      status: .loading,
      cursor: TtsCursor(
        seriesId: seriesId,
        chapterId: chapterId,
        readingListId: readingListId,
        page: 0,
        segment: 0,
      ),
    );

    final navState = await _readyNavState(nav);
    if (generation != _generation) return;

    final cursor = state.cursor!.copyWith(page: navState.page);
    state = state.copyWith(cursor: cursor);
    _expectedPage = null;
    _expectedSubpage = navState.subpage;
    _awaitingPosition = false;
    _keepPaused = false;
    _navSubscription?.close();
    _navSubscription = ref.listen(nav, (previous, next) {
      final data = next.value;
      if (data != null) _onNavigation(previous?.value, data);
    });

    await _enterPage(navState.page, scrollId: navState.scrollId);
  }

  /// Tells the player which subpage the reader is about to show for the
  /// current segment, so it is not mistaken for the user turning the page.
  void expectSubpage(int subpage) => _expectedSubpage = subpage;

  Future<void> pause() async {
    if (state.status != .playing) return;
    await _interrupt();
    state = state.copyWith(status: .paused);
  }

  /// Replays the current segment.
  Future<void> resume() async {
    final cursor = state.cursor;
    if (cursor == null || state.status == .idle) return;

    _awaitingPosition = false;
    _keepPaused = false;
    if (_segments.isEmpty) {
      await _enterPage(cursor.page);
      return;
    }
    await _interrupt();
    _speakAt(cursor.segment);
  }

  Future<void> togglePlayPause() =>
      state.status == .playing ? pause() : resume();

  Future<void> next() async {
    final cursor = state.cursor;
    if (cursor == null) return;

    await _interrupt();
    if (cursor.segment + 1 < _segments.length) {
      _speakAt(cursor.segment + 1);
    } else {
      await _pageEnded();
    }
  }

  Future<void> previous() async {
    final cursor = state.cursor;
    if (cursor == null) return;

    await _interrupt();
    _speakAt(cursor.segment > 0 ? cursor.segment - 1 : 0);
  }

  Future<void> stop() async {
    await _interrupt();
    _navSubscription?.close();
    _navSubscription = null;
    _segments = const [];
    state = TtsPlayerState();
  }

  /// Stops reading when the reader of [chapterId] goes away, unless the
  /// player is handing over to the next chapter's reader.
  Future<void> onReaderDisposed(int chapterId) async {
    if (state.pendingAutoStart) return;
    if (state.cursor?.chapterId != chapterId) return;

    await stop();
  }

  Future<void> _interrupt() async {
    _generation++;
    await _speech?.cancel();
    _speech = null;
    await _engine.stop();
  }

  Future<EpubNavigationState> _readyNavState(
    EpubNavigationProvider nav,
  ) async {
    final completer = Completer<EpubNavigationState>();
    final subscription = ref.listen(nav, (_, next) {
      final data = next.value;
      if (data != null && data.ready && !completer.isCompleted) {
        completer.complete(data);
      }
    }, fireImmediately: true);

    try {
      await completer.future;
    } finally {
      subscription.close();
    }

    // The scroll id is reported right after the subpage count.
    await Future<void>.delayed(Duration.zero);
    return ref.read(nav).requireValue;
  }

  Future<void> _enterPage(
    int page, {
    String? scrollId,
    bool play = true,
  }) async {
    final generation = _generation;
    final cursor = state.cursor;
    if (cursor == null) return;

    final segmentsProvider = ttsSegmentsProvider(
      chapterId: cursor.chapterId,
      page: page,
    );
    // Keeps the auto-disposed provider alive while it loads.
    final keepAlive = ref.listen(segmentsProvider, (_, _) {});
    final List<TtsSegment> segments;
    try {
      segments = await ref.read(segmentsProvider.future);
    } finally {
      keepAlive.close();
    }
    if (generation != _generation) return;

    _segments = segments;
    if (segments.isEmpty && !play) {
      state = state.copyWith(
        status: .paused,
        cursor: cursor.copyWith(page: page, segment: 0),
      );
      return;
    }
    if (segments.isEmpty) {
      state = state.copyWith(cursor: cursor.copyWith(page: page, segment: 0));
      await _pageEnded();
      return;
    }

    final index = scrollId == null
        ? 0
        : segments.indexWhere((s) => s.blockScrollId == scrollId);
    final segment = index < 0 ? 0 : index;
    if (!play) {
      state = state.copyWith(
        status: .paused,
        cursor: cursor.copyWith(page: page, segment: segment),
      );
      return;
    }
    state = state.copyWith(cursor: cursor.copyWith(page: page, segment: 0));
    _speakAt(segment);
  }

  void _speakAt(int index) {
    final cursor = state.cursor;
    if (cursor == null) return;
    final generation = ++_generation;
    final settings =
        ref.read(ttsSettingsProvider).value ?? const TtsSettingsState();

    state = state.copyWith(
      status: .playing,
      cursor: cursor.copyWith(segment: index),
    );

    _speech = _engine
        .speak(
          TtsUtterance(
            text: _segments[index].text,
            voiceName: settings.voiceName,
            voiceLocale: settings.voiceLocale,
            rate: settings.rate,
            pitch: settings.pitch,
          ),
        )
        .listen(
          (event) {
            if (generation != _generation) return;
            switch (event) {
              case TtsDone():
                _segmentDone(index);
              case TtsError(:final message):
                _fail(message);
              case TtsStarted() || TtsWord():
                break;
            }
          },
          onError: (Object error, StackTrace stacktrace) {
            if (generation != _generation) return;
            log.error('tts failed', error: error, stacktrace: stacktrace);
            _fail('$error');
          },
        );
  }

  void _segmentDone(int index) {
    if (index + 1 < _segments.length) {
      _speakAt(index + 1);
    } else {
      _pageEnded();
    }
  }

  void _fail(String message) {
    log.error('tts failed', attributes: {'message': message});
    _generation++;
    state = state.copyWith(status: .error);
  }

  /// Moves on to the next page, or the next chapter when the chapter is done.
  Future<void> _pageEnded() async {
    final cursor = state.cursor;
    if (cursor == null) return;
    final generation = _generation;
    final nav = _navNotifier(cursor);
    final navState = await ref.read(_navProvider(cursor).future);
    if (generation != _generation) return;

    if (cursor.page + 1 < navState.totalPages) {
      _expectedPage = cursor.page + 1;
      _expectedSubpage = 0;
      await nav.jumpToPage(cursor.page + 1, force: true);
      if (generation != _generation) return;
      await _enterPage(cursor.page + 1);
      return;
    }

    final settings =
        ref.read(ttsSettingsProvider).value ?? const TtsSettingsState();
    final nextProvider = nextChapterProvider(
      seriesId: cursor.seriesId,
      chapterId: cursor.chapterId,
      readingListId: cursor.readingListId,
    );
    final keepAlive = ref.listen(nextProvider, (_, _) {});
    final nextChapter = settings.continueNextChapter
        ? await ref.read(nextProvider.future)
        : null;
    keepAlive.close();
    if (generation != _generation) return;

    if (nextChapter == null) {
      await stop();
      return;
    }

    state = state.copyWith(status: .loading, pendingAutoStart: true);
  }

  void _onNavigation(EpubNavigationState? previous, EpubNavigationState next) {
    final cursor = state.cursor;
    if (cursor == null || state.status == .idle) return;

    if (_awaitingPosition) {
      if (next.page == cursor.page && next.scrollId != null) {
        _awaitingPosition = false;
        _expectedSubpage = next.subpage;
        unawaited(_restart(next.page, next.scrollId));
      }
      return;
    }

    if (next.page != cursor.page) {
      if (next.page == _expectedPage) {
        _expectedPage = null;
        return;
      }
      _manualNavigation(next);
      return;
    }

    if (previous?.page == next.page && previous?.subpage == next.subpage) {
      return;
    }
    if (next.subpage != _expectedSubpage) _manualNavigation(next);
  }

  /// The user moved to another page, so read from there instead.
  void _manualNavigation(EpubNavigationState next) {
    _expectedSubpage = next.subpage;
    _keepPaused = state.status == .paused;
    if (next.scrollId == null) {
      // The position is reported once the page is measured.
      _awaitingPosition = true;
      _generation++;
      _speech?.cancel();
      _speech = null;
      unawaited(_engine.stop());
      state = state.copyWith(
        status: .loading,
        cursor: state.cursor!.copyWith(page: next.page, segment: 0),
      );
      return;
    }
    unawaited(_restart(next.page, next.scrollId));
  }

  Future<void> _restart(int page, String? scrollId) async {
    await _interrupt();
    final play = !_keepPaused;
    _keepPaused = false;
    await _enterPage(page, scrollId: scrollId, play: play);
  }
}
