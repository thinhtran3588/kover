import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/utils/logging.dart';
import 'package:kover/utils/safe_platform.dart';

enum ForegroundAction { none, start, update, stop }

/// Decides what to do with the keep-alive given the number of [active]
/// (queued and not paused) chapters and whether it is [running].
ForegroundAction foregroundAction({
  required int active,
  required bool running,
}) {
  if (active == 0) return running ? .stop : .none;
  return running ? .update : .start;
}

/// Keeps the process alive while downloads are queued: an Android foreground
/// service with a progress notification, an iOS background task elsewhere.
/// The download work itself stays in the download manager.
abstract class DownloadForeground {
  static const _iosChannel = MethodChannel('kover/background_task');
  static const _throttle = Duration(seconds: 1);

  static bool _initialized = false;
  static bool _running = false;
  static bool _permissionAsked = false;
  static int _lastCount = -1;
  static DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  static Future<void> _chain = Future.value();

  /// Reconciles the keep-alive with the number of [active] chapters.
  static void sync(int active) {
    if (!SafePlatform.isAndroid && !SafePlatform.isIOS) return;
    _chain = _chain.then((_) => _sync(active)).catchError((
      Object e,
      StackTrace s,
    ) {
      log.error('download foreground failed', error: e, stacktrace: s);
    });
  }

  static Future<void> _sync(int active) async {
    switch (foregroundAction(active: active, running: _running)) {
      case .none:
        return;
      case .start:
        _running = true;
        _lastCount = active;
        _lastUpdate = DateTime.now();
        await (SafePlatform.isIOS ? _iosBegin() : _androidStart(active));
      case .update:
        final now = DateTime.now();
        if (!SafePlatform.isAndroid ||
            active == _lastCount ||
            now.difference(_lastUpdate) < _throttle) {
          return;
        }
        _lastCount = active;
        _lastUpdate = now;
        await FlutterForegroundTask.updateService(
          notificationText: _text(active),
        );
      case .stop:
        _running = false;
        _lastCount = -1;
        if (SafePlatform.isIOS) {
          await _iosChannel.invokeMethod<void>('end');
        } else if (await FlutterForegroundTask.isRunningService) {
          await FlutterForegroundTask.stopService();
        }
    }
  }

  static Future<void> _iosBegin() => _iosChannel.invokeMethod<void>('begin');

  static Future<void> _androidStart(int active) async {
    if (!_initialized) {
      _initialized = true;
      FlutterForegroundTask.initCommunicationPort();
      FlutterForegroundTask.addTaskDataCallback((_) => _running = false);
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'kover_downloads',
          channelName: _l10n().downloadQueue,
          onlyAlertOnce: true,
        ),
        iosNotificationOptions: const IOSNotificationOptions(),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          stopWithTask: true,
        ),
      );
    }

    if (!_permissionAsked) {
      _permissionAsked = true;
      if (await FlutterForegroundTask.checkNotificationPermission() !=
          NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    }

    final result = await FlutterForegroundTask.startService(
      serviceTypes: [ForegroundServiceTypes.dataSync],
      notificationTitle: _l10n().downloadQueue,
      notificationText: _text(active),
      callback: _startCallback,
    );
    if (result is ServiceRequestFailure) {
      _running = false;
      log.warning('download foreground service failed to start');
    }
  }

  static String _text(int count) => _l10n().chaptersLeft(count);

  static AppLocalizations _l10n() {
    final locale = PlatformDispatcher.instance.locale;
    return lookupAppLocalizations(
      AppLocalizations.supportedLocales.firstWhere(
        (supported) => supported.languageCode == locale.languageCode,
        orElse: () => const Locale('en'),
      ),
    );
  }
}

@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveHandler());
}

/// Only keeps the service alive, the downloads run in the app isolate.
class _KeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // dataSync is capped on Android 15+; tell the app so it can start again.
    if (isTimeout) FlutterForegroundTask.sendDataToMain('timeout');
  }
}
