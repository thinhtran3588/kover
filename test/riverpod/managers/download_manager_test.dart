import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/experimental/persist.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/riverpod/managers/download_manager/download_manager.dart';
import 'package:kover/riverpod/managers/download_manager/download_worker.dart';
import 'package:kover/riverpod/providers/connectivity.dart';
import 'package:kover/riverpod/repository/download_repository.dart';
import 'package:kover/riverpod/repository/storage_repository.dart';

class _FakeWorker implements DownloadWorker {
  /// Called for every download request, the first call is attempt 1.
  Future<void> Function(int chapterId, int attempt) onDownload = (
    _,
    _,
  ) async {};
  final calls = <int, int>{};
  final canceled = <int>[];
  final _requestToChapter = <int, int>{};

  @override
  Future<void> downloadChapter({
    required int requestId,
    required int chapterId,
  }) {
    final attempt = (calls[chapterId] ?? 0) + 1;
    calls[chapterId] = attempt;
    _requestToChapter[requestId] = chapterId;
    return onDownload(chapterId, attempt);
  }

  @override
  void cancel(int requestId) {
    canceled.add(_requestToChapter[requestId]!);
  }

  @override
  void close() {}
}

class _FakeRepo extends Fake implements DownloadRepository {
  final complete = <int>{};

  @override
  Future<bool> isChapterDownloaded({required int chapterId}) async =>
      complete.contains(chapterId);

  @override
  Future<void> deleteChapter({required int chapterId}) async {}
}

Future<void> _settleEvents() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeWorker worker;
  late _FakeRepo repo;
  late Storage<String, String> storage;

  setUp(() {
    worker = _FakeWorker();
    repo = _FakeRepo();
    storage = Storage<String, String>.inMemory();
    DownloadManager.retryDelays = const [Duration.zero, Duration.zero];
  });

  ProviderContainer app({Stream<bool>? connection}) => ProviderContainer.test(
    overrides: [
      storageProvider.overrideWith((ref) => storage),
      hasConnectionProvider.overrideWith(
        (ref) => connection ?? Stream.value(true),
      ),
      downloadWorkerProvider.overrideWith((ref) async => worker),
      downloadRepositoryProvider.overrideWithValue(repo),
    ],
  );

  Future<ProviderContainer> start({Stream<bool>? connection}) async {
    final container = app(connection: connection);
    // Riverpod pauses providers nobody listens to, as the app's eager
    // providers do for the manager.
    container.listen(hasConnectionProvider, (_, _) {});
    container.listen(downloadManagerProvider, (_, _) {});
    await container.read(hasConnectionProvider.future);
    await container.read(downloadManagerProvider.future);
    return container;
  }

  test('fails after three attempts and leaves the queue', () async {
    worker.onDownload = (_, _) async => throw Exception('boom');
    final container = await start();

    await container.read(downloadManagerProvider.notifier).enqueue(1);
    await _settleEvents();

    final state = container.read(downloadManagerProvider).requireValue;
    expect(worker.calls[1], 3);
    expect(state.downloadQueue, isEmpty);
    expect(state.failed.keys, [1]);
    expect(state.failed[1], contains('boom'));
  });

  test('going offline keeps the chapter queued and resumes it', () async {
    final connection = StreamController<bool>();
    addTearDown(connection.close);
    connection.add(true);
    final container = await start(connection: connection.stream);

    worker.onDownload = (_, _) async {
      connection.add(false);
      await _settleEvents();
      throw Exception('socket closed');
    };
    await container.read(downloadManagerProvider.notifier).enqueue(1);
    await _settleEvents();

    var state = container.read(downloadManagerProvider).requireValue;
    expect(state.downloadQueue, [1]);
    expect(state.failed, isEmpty);

    worker.onDownload = (id, _) async => repo.complete.add(id);
    connection.add(true);
    await _settleEvents();

    state = container.read(downloadManagerProvider).requireValue;
    expect(state.downloadQueue, isEmpty);
    expect(state.failed, isEmpty);
  });

  test('recovers from a transient error', () async {
    worker.onDownload = (id, attempt) async {
      if (attempt < 2) throw Exception('flaky');
      repo.complete.add(id);
    };
    final container = await start();

    await container.read(downloadManagerProvider.notifier).enqueue(1);
    await _settleEvents();

    final state = container.read(downloadManagerProvider).requireValue;
    expect(worker.calls[1], 2);
    expect(state.downloadQueue, isEmpty);
    expect(state.failed, isEmpty);
  });

  test('a download that ends incomplete is failed', () async {
    final container = await start();

    await container.read(downloadManagerProvider.notifier).enqueue(1);
    await _settleEvents();

    final state = container.read(downloadManagerProvider).requireValue;
    expect(worker.calls[1], 3);
    expect(state.downloadQueue, isEmpty);
    expect(state.failed.keys, [1]);
  });

  test('retry re-queues a failed chapter and clears the failure', () async {
    worker.onDownload = (id, attempt) async {
      if (id == 1 && worker.calls[1]! <= 3) throw Exception('boom');
      repo.complete.add(id);
    };
    final container = await start();
    final manager = container.read(downloadManagerProvider.notifier);

    await manager.enqueue(1);
    await _settleEvents();
    expect(
      container.read(downloadManagerProvider).requireValue.failed.keys,
      [1],
    );

    await manager.retry(1);
    await _settleEvents();

    final state = container.read(downloadManagerProvider).requireValue;
    expect(worker.calls[1], 4);
    expect(state.failed, isEmpty);
    expect(state.downloadQueue, isEmpty);
  });

  test('retryAll re-queues every failed chapter', () async {
    worker.onDownload = (id, attempt) async {
      if (worker.calls[id]! <= 3) throw Exception('boom');
      repo.complete.add(id);
    };
    final container = await start();
    final manager = container.read(downloadManagerProvider.notifier);

    await manager.enqueue(1);
    await manager.enqueue(2);
    await _settleEvents();
    expect(
      container.read(downloadManagerProvider).requireValue.failed.keys,
      unorderedEquals([1, 2]),
    );

    await manager.retryAll();
    await _settleEvents();

    final state = container.read(downloadManagerProvider).requireValue;
    expect(state.failed, isEmpty);
    expect(state.downloadQueue, isEmpty);
  });

  test('pause cancels the active download and resume restarts it', () async {
    final hang = Completer<void>();
    worker.onDownload = (id, attempt) {
      if (attempt == 1) return hang.future;
      repo.complete.add(id);
      return Future.value();
    };
    final container = await start();
    final manager = container.read(downloadManagerProvider.notifier);

    await manager.enqueue(1);
    await _settleEvents();
    expect(worker.calls[1], 1);

    await manager.pause(1);
    await _settleEvents();

    var state = container.read(downloadManagerProvider).requireValue;
    expect(worker.canceled, [1]);
    expect(state.paused, {1});
    expect(state.downloadQueue, isEmpty);
    expect(worker.calls[1], 1);

    await manager.resume(1);
    await _settleEvents();

    state = container.read(downloadManagerProvider).requireValue;
    expect(worker.calls[1], 2);
    expect(state.paused, isEmpty);
    expect(state.downloadQueue, isEmpty);
  });

  test('app resume does not cancel or restart active work', () async {
    final hang = Completer<void>();
    worker.onDownload = (id, attempt) => hang.future;
    final container = await start();

    await container.read(downloadManagerProvider.notifier).enqueue(1);
    await _settleEvents();

    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await _settleEvents();

    expect(worker.calls[1], 1);
    expect(worker.canceled, isEmpty);
    expect(
      container.read(downloadManagerProvider).requireValue.downloadQueue,
      {1},
    );
  });

  test('cancel clears failed and paused flags', () async {
    final container = await start();
    final manager = container.read(downloadManagerProvider.notifier);

    await manager.enqueue(1);
    await _settleEvents();
    await manager.pause(2);
    expect(
      container.read(downloadManagerProvider).requireValue.failed.keys,
      [1],
    );

    await manager.cancelAll();
    await _settleEvents();

    final state = container.read(downloadManagerProvider).requireValue;
    expect(state.failed, isEmpty);
    expect(state.paused, isEmpty);
  });

  test('failed chapters are kept but not restarted after a restart', () async {
    final first = await start();
    await first.read(downloadManagerProvider.notifier).enqueue(1);
    await _settleEvents();
    expect(worker.calls[1], 3);
    first.dispose();

    final second = await start();
    await _settleEvents();

    final state = second.read(downloadManagerProvider).requireValue;
    expect(state.failed.keys, [1]);
    expect(worker.calls[1], 3);
  });

  test('queued chapters resume after a restart', () async {
    final hang = Completer<void>();
    worker.onDownload = (id, attempt) => hang.future;
    final first = await start();
    await first.read(downloadManagerProvider.notifier).enqueue(1);
    await _settleEvents();
    first.dispose();
    worker.calls.clear();

    final second = await start();
    await _settleEvents();

    expect(worker.calls[1], 1);
    expect(
      second.read(downloadManagerProvider).requireValue.downloadQueue,
      {1},
    );
  });

  test('old persisted state without failed and paused still decodes', () {
    final state = DownloadManagerState.fromJson({
      'downloadQueue': [1, 2],
    });
    expect(state.downloadQueue, {1, 2});
    expect(state.failed, isEmpty);
    expect(state.paused, isEmpty);
  });
}
