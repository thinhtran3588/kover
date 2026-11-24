import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:kover/riverpod/providers/reader.dart';
import 'package:kover/riverpod/managers/sync_manager/sync_manager.dart';
import 'package:kover/riverpod/providers/reader/epub_reader.dart';
import 'package:kover/riverpod/providers/reader/reader.dart';
import 'package:kover/riverpod/providers/series.dart';
import 'package:kover/riverpod/providers/settings/tts_settings.dart';
import 'package:kover/riverpod/providers/tts/edge_tts_engine.dart';
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
TtsEngine ttsEngine(Ref ref) {
  final type = ref.watch(ttsSettingsProvider.select((s) => s.value?.engine));
  if (type == .edge && edgeTtsSupported) {
    final engine = EdgeTtsEngine();
    ref.onDispose(engine.dispose);
    return engine;
  }
  final engine = NativeTtsEngine();
  ref.onDispose(engine.stop);
  return engine;
}

/// The language of the series, which picks the voice when none is selected.
@riverpod
Future<String?> ttsLanguage(Ref ref, {required int seriesId}) async =>
    (await ref.watch(seriesMetadataProvider(seriesId: seriesId).future))
        .language;

/// Kept, as the online voice list is a download.
@Riverpod(keepAlive: true)
Future<List<TtsVoice>> ttsVoices(Ref ref) =>
    ref.watch(ttsEngineProvider).voices();

/// Reads an EPUB aloud sentence by sentence.
///
/// While the reader is on screen the player only moves the reading position
/// through [EpubNavigation], so reading progress is saved by the same path as
/// when turning pages. Without a visible reader (screen off, app in the
/// background) nothing updates that position, so the player saves progress,
/// completes chapters and opens the next one itself.
@Riverpod(keepAlive: true)
class TtsPlayer extends _$TtsPlayer {
  static const _lookahead = 2;

  List<TtsSegment> _segments = const [];
  StreamSubscription<TtsEvent>? _speech;
  ProviderSubscription<AsyncValue<EpubNavigationState>>? _navSubscription;
  ProviderSubscription<AsyncValue<ReaderState>>? _readerSubscription;
  var _background = false;
  var _generation = 0;
  int? _expectedPage;
  int? _expectedSubpage;
  var _awaitingPosition = false;
  var _keepPaused = false;
  String? _language;

  /// Finds the first segment shown on a subpage of a page on screen.
  final segmentLocators = <int? Function(int chapter, int page, int subpage)>{};

  @override
  TtsPlayerState build() {
    final lifecycle = AppLifecycleListener(
      onStateChange: (state) => _background = switch (state) {
        .hidden || .paused || .detached => true,
        .resumed || .inactive => false,
      },
    );
    ref.onDispose(() {
      lifecycle.dispose();
      _speech?.cancel();
      _navSubscription?.close();
      _readerSubscription?.close();
    });
    // The engine changed, so continue with the new one.
    ref.listen(ttsEngineProvider, (_, _) {
      if (state.status == .playing) unawaited(resume());
    });
    // Replays the sentence with the new voice, speed or pitch.
    ref.listen(
      ttsSettingsProvider.select(
        (s) => (s.value?.voiceName, s.value?.rate, s.value?.pitch),
      ),
      (previous, _) {
        // Settings that just loaded are not a change.
        if (previous?.$2 != null && state.status == .playing) {
          unawaited(resume());
        }
      },
    );
    return TtsPlayerState();
  }

  /// Whether no reader is on screen to follow the reading position.
  bool get _detached => _background || _navSubscription == null;

  @visibleForTesting
  set background(bool value) => _background = value;

  ReaderProvider _readerProvider(TtsCursor cursor) => readerProvider(
    seriesId: cursor.seriesId,
    chapterId: cursor.chapterId,
    readingListId: cursor.readingListId,
  );

  TtsEngine get _engine => ref.read(ttsEngineProvider);

  EpubNavigation _navNotifier(TtsCursor cursor) =>
      ref.read(_navProvider(cursor).notifier);

  static EpubNavigationProvider _navProvider(TtsCursor cursor) =>
      epubNavigationProvider(
        seriesId: cursor.seriesId,
        chapterId: cursor.chapterId,
        readingListId: cursor.readingListId,
      );

  /// Starts reading at the current position of the reader, or only shows the
  /// player paused there when [play] is false.
  Future<void> start({
    required int seriesId,
    required int chapterId,
    required int? readingListId,
    bool play = true,
  }) async {
    // The player shows before the engine has stopped.
    final interrupted = _interrupt();
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
    await interrupted;

    _language = await _seriesLanguage(seriesId);
    final navState = await _readyNavState(nav);
    if (generation != _generation) return;

    final cursor = state.cursor!.copyWith(page: navState.page);
    state = state.copyWith(cursor: cursor);
    _expectedPage = null;
    _expectedSubpage = navState.subpage;
    _awaitingPosition = false;
    _keepPaused = false;
    _readerSubscription?.close();
    _readerSubscription = null;
    _listenNavigation(nav);

    await _enterPage(
      navState.page,
      scrollId: navState.scrollId,
      segment: _locateSegment(navState.page, navState.subpage),
      play: play,
    );
  }

  int? _locateSegment(int page, int subpage) {
    final chapter = state.cursor?.chapterId;
    if (chapter == null) return null;
    for (final locate in segmentLocators) {
      final segment = locate(chapter, page, subpage);
      if (segment != null) return segment;
    }
    return null;
  }

  Future<String?> _seriesLanguage(int seriesId) async {
    final provider = ttsLanguageProvider(seriesId: seriesId);
    // Keeps the auto-disposed provider alive while it loads.
    final keepAlive = ref.listen(provider, (_, _) {});
    try {
      return await ref.read(provider.future);
    } catch (error, stacktrace) {
      log.error('tts language failed', error: error, stacktrace: stacktrace);
      return null;
    } finally {
      keepAlive.close();
    }
  }

  /// Follows the reader of the chapter being read when it comes on screen
  /// again after the player carried on without it.
  Future<void> attachReader({
    required int seriesId,
    required int chapterId,
    required int? readingListId,
  }) async {
    final cursor = state.cursor;
    if (cursor == null ||
        state.status == .idle ||
        cursor.chapterId != chapterId ||
        _navSubscription != null) {
      return;
    }
    final generation = _generation;
    final nav = epubNavigationProvider(
      seriesId: seriesId,
      chapterId: chapterId,
      readingListId: readingListId,
    );

    final navState = await _readyNavState(nav);
    if (generation != _generation || _navSubscription != null) return;

    final page = state.cursor!.page;
    _expectedPage = navState.page == page ? null : page;
    _expectedSubpage = navState.subpage;
    _listenNavigation(nav);
    if (navState.page != page) {
      await _navNotifier(state.cursor!).jumpToPage(page, force: true);
    }
  }

  void _listenNavigation(EpubNavigationProvider nav) {
    _navSubscription?.close();
    _navSubscription = ref.listen(nav, (previous, next) {
      final data = next.value;
      if (data != null) _onNavigation(previous?.value, data);
    });
  }

  /// Tells the player which subpage the reader is about to show for the
  /// current segment, so it is not mistaken for the user turning the page.
  void expectSubpage(int subpage) => _expectedSubpage = subpage;

  Future<void> pause() async {
    if (state.status != .playing) return;
    final interrupted = _interrupt();
    state = state.copyWith(status: .paused);
    await interrupted;
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
    final interrupted = _interrupt();
    state = state.copyWith(status: .playing);
    await interrupted;
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
    final wasReading = state.cursor != null;
    final interrupted = _interrupt();
    _navSubscription?.close();
    _navSubscription = null;
    _readerSubscription?.close();
    _readerSubscription = null;
    _segments = const [];
    state = TtsPlayerState();
    await interrupted;
    if (wasReading) _syncProgress();
  }

  void _syncProgress() => ref.read(syncManagerProvider.notifier).syncProgress();

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
    int? segment,
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

    final index = segment != null && segment < segments.length
        ? segment
        : scrollId == null
        ? 0
        : segments.indexWhere((s) => s.blockScrollId == scrollId);
    final start = index < 0 ? 0 : index;
    if (!play) {
      state = state.copyWith(
        status: .paused,
        cursor: cursor.copyWith(page: page, segment: start),
      );
      return;
    }
    state = state.copyWith(cursor: cursor.copyWith(page: page, segment: 0));
    _speakAt(start);
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
    if (_detached) unawaited(_saveProgress(cursor, _segments[index]));

    _speech = _engine
        .speak(_utterance(_segments[index], settings))
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
    for (final next in _segments.skip(index + 1).take(_lookahead)) {
      _engine.prefetch(_utterance(next, settings));
    }
  }

  TtsUtterance _utterance(TtsSegment segment, TtsSettingsState settings) =>
      TtsUtterance(
        text: segment.text,
        voiceName: settings.voiceName,
        voiceLocale: settings.voiceLocale,
        language: _language,
        rate: settings.rate,
        pitch: settings.pitch,
      );

  Future<void> _saveProgress(TtsCursor cursor, TtsSegment segment) async {
    try {
      await ref
          .read(_readerProvider(cursor).notifier)
          .saveProgress(
            page: cursor.page,
            scrollId: segment.blockScrollId,
            handleCompletion: false,
          );
    } catch (error, stacktrace) {
      log.error(
        'tts save progress failed',
        error: error,
        stacktrace: stacktrace,
      );
    }
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
    final reader = await ref.read(_readerProvider(cursor).future);
    if (generation != _generation) return;

    if (cursor.page + 1 < reader.totalPages) {
      if (_navSubscription != null) {
        _expectedPage = cursor.page + 1;
        _expectedSubpage = 0;
        await _navNotifier(cursor).jumpToPage(cursor.page + 1, force: true);
        if (generation != _generation) return;
      }
      await _enterPage(cursor.page + 1);
      return;
    }

    // The reader marks the chapter complete when it reaches its end.
    final detached = _detached;
    if (detached) {
      await ref.read(_readerProvider(cursor).notifier).markComplete();
      if (generation != _generation) return;
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

    _syncProgress();
    if (detached) {
      await _openChapter(cursor, nextChapter.id);
      return;
    }
    state = state.copyWith(status: .loading, pendingAutoStart: true);
  }

  /// Carries on with [chapterId] without a reader, which is opened when the
  /// app comes back to the foreground.
  Future<void> _openChapter(TtsCursor from, int chapterId) async {
    final generation = _generation;
    final cursor = TtsCursor(
      seriesId: from.seriesId,
      chapterId: chapterId,
      readingListId: from.readingListId,
      page: 0,
      segment: 0,
    );
    _navSubscription?.close();
    _navSubscription = null;
    _expectedPage = null;
    _expectedSubpage = 0;
    _awaitingPosition = false;
    _segments = const [];
    state = TtsPlayerState(status: .loading, cursor: cursor);

    // Saving progress needs the chapter's reader, which nothing else keeps.
    _readerSubscription?.close();
    _readerSubscription = ref.listen(_readerProvider(cursor), (_, _) {});
    await ref.read(_readerProvider(cursor).future);
    if (generation != _generation) return;

    await _enterPage(0);
  }

  void _onNavigation(EpubNavigationState? previous, EpubNavigationState next) {
    final cursor = state.cursor;
    if (cursor == null || state.status == .idle) return;

    if (_awaitingPosition) {
      if (next.page == cursor.page && next.scrollId != null) {
        _awaitingPosition = false;
        _expectedSubpage = next.subpage;
        unawaited(_restart(next.page, next.subpage, next.scrollId));
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
    unawaited(_restart(next.page, next.subpage, next.scrollId));
  }

  Future<void> _restart(int page, int subpage, String? scrollId) async {
    await _interrupt();
    final play = !_keepPaused;
    _keepPaused = false;
    await _enterPage(
      page,
      scrollId: scrollId,
      segment: _locateSegment(page, subpage),
      play: play,
    );
  }
}
