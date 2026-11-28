import 'dart:isolate';

/// Placeholder for platforms without `dart:ffi`; never called there because
/// `vieneuTtsSupported` is false.
void vieneuWorkerMain((SendPort, String) args) =>
    throw UnsupportedError('VieNeu is not available on this platform');
