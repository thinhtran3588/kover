import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/css_engine.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/measure/epub_measurements_collector.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/paginated_epub_page_settings.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/pagination/epub_paginator.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/preprocessing/epub_page_preprocessor.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/preprocessing/node_indexing_operation.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/preprocessing/tts_segment_operation.dart';
import 'package:material_ui/material_ui.dart';

const _settings = PaginatedEpubPageSettings(
  horizontalMarginSize: 0,
  verticalMarginSize: 0,
  fontSize: 14,
  paragraphSpacing: 0,
  lineHeight: 1.5,
  wordSpacing: 0,
  letterSpacing: 0,
  fontFamily: null,
  removeParagraphIndent: false,
  highlightResumePoint: false,
  canScroll: true,
  reduceAnimations: false,
  ignoreSafeArea: false,
  textAlignment: .left,
  mode: .horizontal,
);

final _html =
    '<p>${List.filled(6, 'Some words in a sentence that wraps around. ').join()}'
    'An <em>emphasised</em> end.</p><p>Second paragraph. It has two.</p>'
    '<p>${List.filled(8, 'More text to fill the page and wrap. ').join()}</p>';

void main() {
  testWidgets('wrapping text does not change pagination', (tester) async {
    final plain = await _paginate(tester, withTts: false);
    final wrapped = await _paginate(tester, withTts: true);

    expect(plain.subpageCount, greaterThan(1));
    expect(wrapped.subpageCount, plain.subpageCount);
    for (var i = 0; i < plain.subpageCount; i++) {
      expect(
        dom.DocumentFragment.html(wrapped.getSubpage(i)).text,
        dom.DocumentFragment.html(plain.getSubpage(i)).text,
      );
    }
    expect(wrapped.subpageForSegment(0), 0);
    expect(wrapped.subpageForSegment(1000), isNull);
  });
}

Future<EpubPaginator> _paginate(
  WidgetTester tester, {
  required bool withTts,
}) async {
  final root = EpubPagePreprocessor(
    html: dom.DocumentFragment.html(_html),
    operations: [if (withTts) TtsSegmentOperation(), NodeIndexingOperation()],
  ).process();

  const size = Size(200, 120);
  EpubMeasurements? measurements;
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox.fromSize(
          size: size,
          child: EpubMeasurementsCollector(
            html: root,
            settings: _settings,
            cssEngine: CssEngine(root: root),
            constraints: BoxConstraints.tight(size),
            onMeasured: (value, _) => measurements = value,
          ),
        ),
      ),
    ),
  );
  await tester.pump();

  return EpubPaginator(root: root)..paginate(measurements!.units, size.height);
}
