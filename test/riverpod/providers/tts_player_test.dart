import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/models/chapter_model.dart';
import 'package:kover/models/enums/format.dart';
import 'package:kover/models/series_model.dart';
import 'package:kover/riverpod/managers/sync_manager/sync_manager.dart';
import 'package:kover/riverpod/providers/reader.dart';
import 'package:kover/riverpod/providers/reader/epub_reader.dart';
import 'package:kover/riverpod/providers/reader/reader.dart';
import 'package:kover/riverpod/providers/settings/epub_reader_settings.dart';
import 'package:kover/riverpod/providers/settings/tts_settings.dart';
import 'package:kover/riverpod/providers/tts/tts_audio_handler.dart';
import 'package:kover/riverpod/providers/tts/tts_engine.dart';
import 'package:kover/riverpod/providers/tts/tts_player.dart';
import 'package:kover/riverpod/providers/tts/tts_segments.dart';

const _series = SeriesModel(
  id: 1,
  libraryId: 1,
  name: 'Series',
  format: Format.epub,
  pages: 2,
  avgHoursToRead: 0,
  wordCount: null,
  primaryColor: null,
  secondaryColor: null,
  lastSynced: null,
);

const _chapter = ChapterModel(
  id: 2,
  seriesId: 1,
  volumeId: 1,
  title: 'Chapter',
  pages: 2,
);

const _nextChapter = ChapterModel(
  id: 3,
  seriesId: 1,
  volumeId: 1,
  title: 'Next',
  pages: 2,
);

const _nextReaderState = ReaderState(
  libraryId: 1,
  series: _series,
  chapter: _nextChapter,
  readingListId: null,
  volumeId: 1,
  title: 'Next',
  totalPages: 2,
  initialPage: 0,
  bookScrollId: null,
);

const _readerState = ReaderState(
  libraryId: 1,
  series: _series,
  chapter: _chapter,
  readingListId: null,
  volumeId: 1,
  title: 'Chapter',
  totalPages: 2,
  initialPage: 0,
  bookScrollId: null,
);

final _nav = epubNavigationProvider(
  seriesId: 1,
  chapterId: 2,
  readingListId: null,
);

List<TtsSegment> _segments(String prefix, List<String> blocks) => [
  for (var i = 0; i < blocks.length; i++)
    TtsSegment(index: i, text: '$prefix$i', blockScrollId: blocks[i]),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeEngine engine;
  late _FakeReader reader;
  late _FakeReader nextReader;
  late _FakeSync sync;
  late ProviderContainer container;
  late TtsPlayer player;

  Future<void> startReading({String? scrollId}) async {
    await container.pump();
    final started = player.start(
      seriesId: 1,
      chapterId: 2,
      readingListId: null,
    );
    final nav = container.read(_nav.notifier);
    nav.updateSubpageCount(0, 2);
    nav.restorePosition(page: 0, subpage: 0, scrollId: scrollId);
    await started;
  }

  void setUpContainer({bool continueNext = true, bool hasNext = true}) {
    engine = _FakeEngine();
    reader = _FakeReader(_readerState);
    nextReader = _FakeReader(_nextReaderState);
    sync = _FakeSync();
    container = ProviderContainer.test(
      overrides: [
        readerProvider(
          seriesId: 1,
          chapterId: 2,
          readingListId: null,
        ).overrideWith(() => reader),
        readerProvider(
          seriesId: 1,
          chapterId: 3,
          readingListId: null,
        ).overrideWith(() => nextReader),
        syncManagerProvider.overrideWith(() => sync),
        ttsLanguageProvider(seriesId: 1).overrideWith((_) async => null),
        ttsSegmentsProvider(chapterId: 3, page: 0).overrideWith(
          (_) => _segments('n0-', ['x', 'y']),
        ),
        epubReaderSettingsProvider(
          seriesId: 1,
        ).overrideWithBuild((_, _) => const EpubReaderSettingsState()),
        ttsEngineProvider.overrideWithValue(engine),
        ttsSettingsProvider.overrideWithBuild(
          (_, _) => TtsSettingsState(continueNextChapter: continueNext),
        ),
        ttsSegmentsProvider(chapterId: 2, page: 0).overrideWith(
          (_) => _segments('p0-', ['a', 'a', 'b']),
        ),
        ttsSegmentsProvider(chapterId: 2, page: 1).overrideWith(
          (_) => _segments('p1-', ['c', 'c']),
        ),
        nextChapterProvider(
          seriesId: 1,
          chapterId: 2,
          readingListId: null,
        ).overrideWith(
          (_) => Stream.value(hasNext ? _nextChapter : null),
        ),
      ],
    );
    final sub = container.listen(_nav, (_, _) {});
    addTearDown(sub.close);
    player = container.read(ttsPlayerProvider.notifier);
  }

  Future<void> pump() async {
    for (var i = 0; i < 10; i++) {
      await container.pump();
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(setUpContainer);

  test('starts at the first segment of the current paragraph', () async {
    await container.read(_nav.future);
    await startReading(scrollId: 'b');

    expect(engine.spoken, ['p0-2']);
    expect(container.read(ttsPlayerProvider).status, TtsStatus.playing);
    expect(container.read(ttsPlayerProvider).cursor?.segment, 2);
  });

  test('falls back to the first segment for an unknown scroll id', () async {
    await container.read(_nav.future);
    await startReading(scrollId: 'zzz');

    expect(engine.spoken, ['p0-0']);
  });

  test('advances sentence by sentence and jumps to the next page', () async {
    await container.read(_nav.future);
    await startReading();

    for (var i = 0; i < 3; i++) {
      engine.finish();
      await pump();
    }
    await pump();

    expect(engine.spoken, ['p0-0', 'p0-1', 'p0-2', 'p1-0']);
    expect(container.read(_nav).requireValue.page, 1);
    expect(container.read(ttsPlayerProvider).cursor?.page, 1);

    engine.finish();
    await pump();
    expect(engine.spoken.last, 'p1-1');
  });

  test('prefetches the next two segments of the page', () async {
    await container.read(_nav.future);
    await startReading();

    expect(engine.prefetched.map((u) => u.text), ['p0-1', 'p0-2']);

    engine.finish();
    await pump();
    expect(engine.prefetched.map((u) => u.text), ['p0-1', 'p0-2', 'p0-2']);

    engine.finish();
    await pump();
    // The first segment of the next page is never prefetched.
    expect(engine.prefetched.map((u) => u.text), ['p0-1', 'p0-2', 'p0-2']);
    expect(engine.spoken.last, 'p0-2');
  });

  test('prefetch uses the same settings as speak', () async {
    await container.read(_nav.future);
    await container.read(ttsSettingsProvider.future);
    await pump();
    await startReading();
    engine.prefetched.clear();

    await container.read(ttsSettingsProvider.notifier).setRate(1.5);
    await pump();

    expect(engine.spoken.last, 'p0-0');
    expect(engine.prefetched.map((u) => u.text), ['p0-1', 'p0-2']);
    expect(engine.prefetched.map((u) => u.rate), [1.5, 1.5]);
  });

  test('page advance saves progress through the navigation path', () async {
    await container.read(_nav.future);
    await startReading(scrollId: 'a');
    reader.saved.clear();

    // Moving within the page never writes progress by itself.
    engine.finish();
    await pump();
    expect(reader.saved, isEmpty);

    engine.finish();
    await pump();
    engine.finish();
    await pump();

    expect(container.read(_nav).requireValue.page, 1);
    expect(reader.saved, [1]);
  });

  test('a manual subpage change restarts from the new subpage', () async {
    await container.read(_nav.future);
    await startReading(scrollId: 'a');

    container
        .read(_nav.notifier)
        .updateSubpagePosition(page: 0, subpage: 1, scrollId: 'b');
    await pump();
    await pump();

    expect(engine.spoken.last, 'p0-2');
    expect(container.read(ttsPlayerProvider).status, TtsStatus.playing);
  });

  test('a subpage change requested by the player does not restart', () async {
    await container.read(_nav.future);
    await startReading(scrollId: 'a');

    player.expectSubpage(1);
    container
        .read(_nav.notifier)
        .updateSubpagePosition(page: 0, subpage: 1, scrollId: 'b');
    await pump();

    expect(engine.spoken, ['p0-0']);
  });

  test('pause stops the engine and resume replays the segment', () async {
    await container.read(_nav.future);
    await startReading();
    engine.finish();
    await pump();
    final stops = engine.stops;

    await player.pause();
    expect(container.read(ttsPlayerProvider).status, TtsStatus.paused);
    expect(engine.stops, greaterThan(stops));

    await player.resume();
    expect(engine.spoken.last, 'p0-1');
    expect(container.read(ttsPlayerProvider).status, TtsStatus.playing);
  });

  test('next and previous move one segment', () async {
    await container.read(_nav.future);
    await startReading(scrollId: 'a');

    await player.next();
    expect(engine.spoken.last, 'p0-1');
    await player.previous();
    expect(engine.spoken.last, 'p0-0');
  });

  test('the end of the chapter requests the next chapter', () async {
    await container.read(_nav.future);
    await startReading(scrollId: 'a');

    for (var i = 0; i < 5; i++) {
      engine.finish();
      await pump();
    }
    await pump();

    final state = container.read(ttsPlayerProvider);
    expect(state.pendingAutoStart, isTrue);

    await player.onReaderDisposed(2);
    expect(container.read(ttsPlayerProvider).pendingAutoStart, isTrue);
  });

  test('stops at the end of the chapter when not continuing', () async {
    setUpContainer(continueNext: false);
    await container.read(_nav.future);
    await startReading(scrollId: 'a');

    for (var i = 0; i < 5; i++) {
      engine.finish();
      await pump();
    }
    await pump();

    expect(container.read(ttsPlayerProvider).status, TtsStatus.idle);
  });

  group('without a reader on screen', () {
    Future<void> finishChapter() async {
      for (var i = 0; i < 5; i++) {
        engine.finish();
        await pump();
      }
      await pump();
    }

    test('saves progress per block and turns the page itself', () async {
      await container.read(_nav.future);
      await startReading(scrollId: 'a');
      player.background = true;
      reader.savedScrollIds.clear();

      engine.finish();
      await pump();
      engine.finish();
      await pump();
      expect(reader.savedScrollIds, ['a', 'b']);

      engine.finish();
      await pump();
      expect(reader.saved.take(2), [0, 0]);
      expect(reader.saved.skip(2), everyElement(1));
      expect(container.read(_nav).requireValue.page, 1);
    });

    test('completes the chapter and opens the next one', () async {
      await container.read(_nav.future);
      await startReading(scrollId: 'a');
      player.background = true;

      await finishChapter();

      final state = container.read(ttsPlayerProvider);
      expect(reader.completed, 1);
      expect(state.pendingAutoStart, isFalse);
      expect(state.cursor?.chapterId, 3);
      expect(state.status, TtsStatus.playing);
      expect(engine.spoken.last, 'n0-0');
      expect(nextReader.savedScrollIds, ['x']);
      expect(sync.progressSyncs, 1);

      // The reader opened on return follows the player.
      player.background = false;
      final nextNav = epubNavigationProvider(
        seriesId: 1,
        chapterId: 3,
        readingListId: null,
      );
      final subscription = container.listen(nextNav, (_, _) {});
      addTearDown(subscription.close);
      await container.read(nextNav.future);
      container.read(nextNav.notifier).updateSubpageCount(0, 1);
      await player.attachReader(
        seriesId: 1,
        chapterId: 3,
        readingListId: null,
      );

      expect(engine.spoken.where((s) => s.startsWith('n0-')), ['n0-0']);
      expect(container.read(ttsPlayerProvider).status, TtsStatus.playing);
    });

    test('completes the last chapter and stops', () async {
      setUpContainer(hasNext: false);
      await container.read(_nav.future);
      await startReading(scrollId: 'a');
      player.background = true;

      await finishChapter();

      expect(reader.completed, 1);
      expect(container.read(ttsPlayerProvider).status, TtsStatus.idle);
      expect(sync.progressSyncs, 1);
    });
  });

  group('media session handler', () {
    test('mirrors the player state', () async {
      await container.read(_nav.future);
      await startReading(scrollId: 'a');
      final handler = TtsAudioHandler(player);

      handler.update(container.read(ttsPlayerProvider));
      var state = handler.playbackState.value;
      expect(state.playing, isTrue);
      expect(state.processingState, AudioProcessingState.ready);
      expect(state.controls, [
        MediaControl.skipToPrevious,
        MediaControl.pause,
        MediaControl.skipToNext,
        MediaControl.stop,
      ]);
      expect(state.androidCompactActionIndices, [0, 1, 2]);

      await player.pause();
      handler.update(container.read(ttsPlayerProvider));
      state = handler.playbackState.value;
      expect(state.playing, isFalse);
      expect(state.controls[1], MediaControl.play);
    });

    test('forwards the media buttons to the player', () async {
      await container.read(_nav.future);
      await startReading(scrollId: 'a');
      final handler = TtsAudioHandler(player);

      await handler.skipToNext();
      expect(engine.spoken.last, 'p0-1');
      await handler.skipToPrevious();
      expect(engine.spoken.last, 'p0-0');
      await handler.pause();
      expect(container.read(ttsPlayerProvider).status, TtsStatus.paused);
      await handler.play();
      expect(container.read(ttsPlayerProvider).status, TtsStatus.playing);
      await handler.stop();
      expect(container.read(ttsPlayerProvider).status, TtsStatus.idle);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.idle,
      );
    });
  });

  test('stop goes idle and the reader dispose stops the session', () async {
    await container.read(_nav.future);
    await startReading();

    await player.onReaderDisposed(2);

    expect(container.read(ttsPlayerProvider).status, TtsStatus.idle);
  });
}

class _FakeEngine implements TtsEngine {
  final spoken = <String>[];
  final prefetched = <TtsUtterance>[];
  var stops = 0;
  StreamController<TtsEvent>? _current;

  @override
  bool get supportsWordBoundaries => false;

  @override
  Future<List<TtsVoice>> voices() async => const [];

  @override
  Stream<TtsEvent> speak(TtsUtterance utterance) {
    spoken.add(utterance.text);
    return (_current = StreamController<TtsEvent>()).stream;
  }

  @override
  void prefetch(TtsUtterance utterance) => prefetched.add(utterance);

  @override
  Future<void> stop() async {
    stops++;
    await _current?.close();
    _current = null;
  }

  void finish() {
    _current?.add(const TtsDone());
  }
}

class _FakeSync extends SyncManager {
  // ignore: avoid_public_notifier_properties
  var progressSyncs = 0;

  @override
  SyncState build() => const SyncState.idle();

  @override
  void syncProgress() => progressSyncs++;
}

class _FakeReader extends Reader {
  final ReaderState _state;
  final saved = <int>[];
  final savedScrollIds = <String?>[];
  // ignore: avoid_public_notifier_properties
  var completed = 0;

  _FakeReader(this._state);

  @override
  Future<ReaderState> build({
    required int seriesId,
    required int chapterId,
    required int? readingListId,
  }) async => _state;

  @override
  Future<void> saveProgress({
    required int page,
    String? scrollId,
    bool handleCompletion = true,
  }) async {
    saved.add(page);
    savedScrollIds.add(scrollId);
  }

  @override
  Future<void> markComplete() async => completed++;
}
