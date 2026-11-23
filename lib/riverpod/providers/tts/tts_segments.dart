import 'package:kover/pages/reader/epub_reader/paginated_epub_page/preprocessing/epub_page_preprocessor.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/preprocessing/tts_segment_operation.dart';
import 'package:kover/riverpod/providers/book.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

export 'package:kover/pages/reader/epub_reader/paginated_epub_page/preprocessing/tts_segment_operation.dart'
    show TtsSegment;

part 'tts_segments.g.dart';

/// The sentence segments of an EPUB page, in reading order.
///
/// They come from the same preprocessing that wraps the text in the reader, so
/// segment indexes match the highlight wrappers in the rendered page.
@riverpod
Future<List<TtsSegment>> ttsSegments(
  Ref ref, {
  required int chapterId,
  required int page,
}) async {
  final content = await ref.watch(
    epubPageProvider(chapterId: chapterId, page: page).future,
  );

  final operation = TtsSegmentOperation();
  EpubPagePreprocessor(html: content.root, operations: [operation]).process();

  return operation.segments;
}
