# Kover patch

Upstream: flutter_tts 4.2.5.

Patched `FlutterTtsPlugin.kt` (Android): `onProgress` returns early on a missing utterance or out-of-range offsets, and `onStart` (SDK < 26) no longer uses `!!`. Some head-unit TTS engines report bad ids/offsets, and the uncaught exception on the binder thread crashed the app.

Drop this copy and the `dependency_overrides` entry in `pubspec.yaml` once upstream fixes it.
