import 'dart:async';
import 'dart:io';

import 'package:kover/utils/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'vieneu_model.g.dart';

const _modelRepository =
    'https://huggingface.co/pnnbao-ump/VieNeu-TTS-v3-Nano/resolve/'
    'aba295eb96a6fa6003ebe417cc1f2802a7adc1dc';

class const VieneuFile({
  required final String name,
  required final String url,
  required final int size,
});

/// The files of the VieNeu-TTS v3 Nano model, at pinned revisions.
const vieneuFiles = [
  VieneuFile(
    name: 'text_encoder.onnx',
    url: '$_modelRepository/text_encoder.onnx',
    size: 26519943,
  ),
  VieneuFile(
    name: 'duration_predictor.onnx',
    url: '$_modelRepository/duration_predictor.onnx',
    size: 727809,
  ),
  VieneuFile(
    name: 'vector_estimator.onnx',
    url: '$_modelRepository/vector_estimator.onnx',
    size: 155132418,
  ),
  VieneuFile(
    name: 'codec_decoder.onnx',
    url: '$_modelRepository/codec_decoder.onnx',
    size: 99319941,
  ),
  VieneuFile(
    name: 'config.json',
    url: '$_modelRepository/config.json',
    size: 2927,
  ),
  VieneuFile(
    name: 'constants.npz',
    url: '$_modelRepository/constants.npz',
    size: 53448,
  ),
  VieneuFile(
    name: 'sea_g2p.bin',
    url:
        'https://github.com/pnnbao97/sea-g2p/releases/download/v0.10.0/'
        'sea_g2p.bin',
    size: 62829820,
  ),
  VieneuFile(
    name: 'voices_v3_nano.json',
    url:
        'https://raw.githubusercontent.com/pnnbao97/VieNeu-TTS/'
        '94ad51605b98a4ac8444e3dd3373b4d86a79d21f/src/vieneu/assets/'
        'voices_v3_nano.json',
    size: 2316799,
  ),
];

Future<Directory> vieneuModelDirectory() async => Directory(
  p.join((await getApplicationSupportDirectory()).path, 'vieneu_v3_nano'),
);

/// Whether every file of [files] is complete in [directory].
bool vieneuFilesComplete(
  Directory directory, [
  List<VieneuFile> files = vieneuFiles,
]) => files.every((file) {
  final stored = File(p.join(directory.path, file.name));
  return stored.existsSync() && stored.lengthSync() == file.size;
});

/// Downloads the missing [files] into [directory], one after the other.
///
/// A file is written to `<name>.part`, which a later call resumes with a
/// range request, and renamed once it has its full size. [onProgress] gets
/// the bytes received and the total of all files. Stops with a
/// [StateError] when [cancelled] turns true.
Future<void> downloadVieneuFiles(
  Directory directory, {
  List<VieneuFile> files = vieneuFiles,
  required void Function(int received, int total) onProgress,
  bool Function()? cancelled,
}) async {
  await directory.create(recursive: true);
  final total = files.fold(0, (sum, file) => sum + file.size);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  var done = 0;
  try {
    for (final file in files) {
      final target = File(p.join(directory.path, file.name));
      if (target.existsSync() && target.lengthSync() == file.size) {
        done += file.size;
        onProgress(done, total);
        continue;
      }
      await _download(client, file, target, cancelled, (received) {
        onProgress(done + received, total);
      });
      done += file.size;
    }
  } finally {
    client.close(force: true);
  }
}

Future<void> _download(
  HttpClient client,
  VieneuFile file,
  File target,
  bool Function()? cancelled,
  void Function(int received) onReceived,
) async {
  final part = File('${target.path}.part');
  var existing = part.existsSync() ? part.lengthSync() : 0;
  if (existing > file.size) {
    await part.delete();
    existing = 0;
  }

  if (existing < file.size) {
    final request = await client.getUrl(Uri.parse(file.url));
    if (existing > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existing-');
    }
    final response = await request.close();
    if (response.statusCode != 200 && response.statusCode != 206) {
      await response.drain<void>();
      throw HttpException('HTTP ${response.statusCode}', uri: request.uri);
    }
    // A server that ignores the range sends the whole file again.
    final resumed = response.statusCode == 206 && existing > 0;
    if (!resumed) existing = 0;

    final sink = part.openWrite(mode: resumed ? .append : .write);
    var received = existing;
    try {
      await for (final chunk in response) {
        if (cancelled?.call() ?? false) throw StateError('cancelled');
        sink.add(chunk);
        received += chunk.length;
        onReceived(received);
      }
    } finally {
      await sink.close();
    }
  }

  if (part.lengthSync() != file.size) {
    throw HttpException(
      '${file.name} is ${part.lengthSync()} bytes, expected ${file.size}',
    );
  }
  await part.rename(target.path);
}

sealed class VieneuModelState {
  const VieneuModelState();
}

final class VieneuModelMissing extends VieneuModelState {
  const VieneuModelMissing();
}

final class const VieneuModelDownloading({
  required final int received,
  required final int total,
}) extends VieneuModelState {}

final class VieneuModelReady extends VieneuModelState {
  const VieneuModelReady();
}

final class const VieneuModelFailed({required final String message})
    extends VieneuModelState {}

/// The files of the VieNeu-TTS voice on the device.
@Riverpod(keepAlive: true)
class VieneuModel extends _$VieneuModel {
  var _cancelled = false;

  @override
  Future<VieneuModelState> build() async =>
      vieneuFilesComplete(await vieneuModelDirectory())
      ? const VieneuModelReady()
      : const VieneuModelMissing();

  Future<void> download() async {
    if (await future case VieneuModelDownloading()) return;

    _cancelled = false;
    state = const AsyncData(VieneuModelDownloading(received: 0, total: 1));
    try {
      await downloadVieneuFiles(
        await vieneuModelDirectory(),
        onProgress: (received, total) => state = AsyncData(
          VieneuModelDownloading(received: received, total: total),
        ),
        cancelled: () => _cancelled,
      );
      state = const AsyncData(VieneuModelReady());
      log.info('vieneu model downloaded', attributes: {'reader': 'tts'});
    } catch (error, stacktrace) {
      if (_cancelled) {
        state = const AsyncData(VieneuModelMissing());
        return;
      }
      log.error('vieneu download failed', error: error, stacktrace: stacktrace);
      state = AsyncData(VieneuModelFailed(message: '$error'));
    }
  }

  /// Stops a download, keeping what was received for a later one.
  void cancel() => _cancelled = true;

  Future<void> delete() async {
    _cancelled = true;
    final directory = await vieneuModelDirectory();
    if (directory.existsSync()) await directory.delete(recursive: true);
    state = const AsyncData(VieneuModelMissing());
    log.info('vieneu model deleted', attributes: {'reader': 'tts'});
  }
}
