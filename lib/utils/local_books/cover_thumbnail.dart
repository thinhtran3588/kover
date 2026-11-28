import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:kover/utils/logging.dart';

const _coverWidth = 300;

/// PNG encodes [image].
Future<Uint8List?> encodePng(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data?.buffer.asUint8List();
}

/// Scales the encoded image [bytes] down to a cover thumbnail and PNG encodes
/// it. Returns null if the image cannot be decoded.
Future<Uint8List?> createCoverThumbnail(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: _coverWidth,
    );
    try {
      final frame = await codec.getNextFrame();
      try {
        return await encodePng(frame.image);
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  } catch (e) {
    log.warning(
      'failed to create cover thumbnail',
      attributes: {'error': e},
    );
    return null;
  }
}
