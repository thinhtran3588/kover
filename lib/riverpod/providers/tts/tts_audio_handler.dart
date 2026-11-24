import 'dart:io';
import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/riverpod/providers/chapter.dart';
import 'package:kover/riverpod/providers/reader/reader.dart';
import 'package:kover/riverpod/providers/series.dart';
import 'package:kover/riverpod/providers/tts/tts_player.dart';
import 'package:kover/utils/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tts_audio_handler.g.dart';

/// Exposes the read aloud [TtsPlayer] to the system media session, so the
/// notification, lock screen and hardware media buttons control it.
class TtsAudioHandler extends BaseAudioHandler {
  final TtsPlayer _player;

  TtsAudioHandler(this._player);

  /// Mirrors the player [state] into the media session.
  void update(TtsPlayerState state) {
    final playing = state.status == .playing;
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        androidCompactActionIndices: const [0, 1, 2],
        processingState: switch (state.status) {
          .idle => AudioProcessingState.idle,
          .loading => AudioProcessingState.loading,
          .playing || .paused => AudioProcessingState.ready,
          .error => AudioProcessingState.error,
        },
        playing: playing,
      ),
    );
  }

  @override
  Future<void> play() => _player.resume();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> skipToNext() => _player.next();

  @override
  Future<void> skipToPrevious() => _player.previous();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  /// Stops reading when the app is swiped away from the recent apps, which
  /// otherwise leaves the media service running.
  @override
  Future<void> onTaskRemoved() => stop();
}

/// The media session of the read aloud player, started on first use.
@Riverpod(keepAlive: true)
Future<TtsAudioHandler> ttsAudioHandler(Ref ref) async {
  final player = ref.read(ttsPlayerProvider.notifier);
  final handler = await AudioService.init(
    builder: () => TtsAudioHandler(player),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.rodonisi.kover.tts',
      androidNotificationIcon: 'drawable/ic_stat_kover',
      androidNotificationChannelName:
          _localizations().readAloudNotificationChannel,
      androidStopForegroundOnPause: true,
    ),
  );

  final session = await AudioSession.instance;
  // The TTS engine takes transient focus for every utterance. Ducking events
  // are kept as such, instead of pauses, so they can be told apart below.
  await session.configure(
    const AudioSessionConfiguration.speech().copyWith(
      androidWillPauseWhenDucked: false,
    ),
  );
  var interrupted = false;
  final subscriptions = [
    session.interruptionEventStream.listen((event) {
      // Includes the TTS engine's own focus requests.
      if (event.type == AudioInterruptionType.duck) return;
      final status = ref.read(ttsPlayerProvider).status;
      if (event.begin) {
        if (status == .playing) {
          interrupted = true;
          player.pause();
        }
      } else if (interrupted && event.type == AudioInterruptionType.pause) {
        interrupted = false;
        player.resume();
      } else {
        interrupted = false;
      }
    }),
    session.becomingNoisyEventStream.listen((_) => player.pause()),
  ];
  ref.onDispose(() {
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
  });

  ref.listen(ttsPlayerProvider, (previous, next) {
    handler.update(next);
    if (next.status == .playing && previous?.status != .playing) {
      session.setActive(true);
    } else if (next.status == .idle) {
      session.setActive(false);
    }
  }, fireImmediately: true);

  ref.listen(
    ttsPlayerProvider.select(
      (state) => state.cursor == null
          ? null
          : (state.cursor!.seriesId, state.cursor!.chapterId),
    ),
    (previous, next) async {
      if (next == null) return;
      try {
        handler.mediaItem.add(await _mediaItem(ref, next.$1, next.$2));
      } catch (error, stacktrace) {
        log.error(
          'tts media item failed',
          error: error,
          stacktrace: stacktrace,
        );
      }
    },
    fireImmediately: true,
  );

  return handler;
}

/// Reads [provider], keeping it alive while it loads.
Future<T> _load<T>(Ref ref, ProviderListenable<Future<T>> provider) async {
  final keepAlive = ref.listen(provider, (_, _) {});
  try {
    return await keepAlive.read();
  } finally {
    keepAlive.close();
  }
}

Future<MediaItem> _mediaItem(Ref ref, int seriesId, int chapterId) async {
  final series = await _load(
    ref,
    readerSeriesProvider(seriesId: seriesId).future,
  );
  final chapter = await _load(
    ref,
    readerChapterProvider(seriesId: seriesId, chapterId: chapterId).future,
  );
  var writers = chapter.writers;
  if (writers.isEmpty) {
    try {
      writers = (await _load(
        ref,
        seriesMetadataProvider(seriesId: seriesId).future,
      )).writers;
    } catch (error, stacktrace) {
      log.error('tts writers failed', error: error, stacktrace: stacktrace);
    }
  }
  final author = writers.map((writer) => writer.name).join(', ');

  // Shown as the book title and its author, with the chapter when it differs.
  return MediaItem(
    id: 'kover:$chapterId',
    title: series.name,
    artist: author.isEmpty ? null : author,
    album: chapter.title == series.name ? null : chapter.title,
    artUri: await _coverUri(ref, chapterId),
  );
}

/// The cover is stored in the database, so it is written to a file the media
/// session can read. The media item is shown without it when it fails.
Future<Uri?> _coverUri(Ref ref, int chapterId) async {
  try {
    final cover = await _load(
      ref,
      chapterCoverProvider(chapterId: chapterId).future,
    );
    if (cover == null) return null;

    final directory = await getTemporaryDirectory();
    final file = File(p.join(directory.path, 'tts_cover_$chapterId'));
    await file.writeAsBytes(cover.data);
    return file.uri;
  } catch (error, stacktrace) {
    log.error('tts cover failed', error: error, stacktrace: stacktrace);
    return null;
  }
}

AppLocalizations _localizations() {
  final locale = PlatformDispatcher.instance.locale;
  return lookupAppLocalizations(
    AppLocalizations.supportedLocales.firstWhere(
      (supported) => supported.languageCode == locale.languageCode,
      orElse: () => const Locale('en'),
    ),
  );
}
