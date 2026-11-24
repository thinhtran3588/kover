import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/preprocessing/epub_page_preprocessor.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/preprocessing/scroll_id_operation.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/preprocessing/tts_segment_operation.dart';
import 'package:kover/utils/constants/html_constants.dart';
import 'package:kover/utils/extensions/element.dart';

void main() {
  group('segmentBlocks', () {
    test('splits sentences of a paragraph', () {
      expect(_texts('<p>One. Two! Three?</p>'), ['One.', 'Two!', 'Three?']);
    });

    test('does not split after abbreviations or initials', () {
      expect(
        _texts('<p>Dr. Smith met J. Doe. They left.</p>'),
        ['Dr. Smith met J. Doe.', 'They left.'],
      );
    });

    test('does not split before a lowercase continuation', () {
      expect(_texts('<p>He said "wait." then left. Done.</p>'), [
        'He said "wait." then left.',
        'Done.',
      ]);
    });

    test('splits CJK sentences without whitespace', () {
      expect(_texts('<p>今日は晴れ。明日は雨！本当？</p>'), [
        '今日は晴れ。',
        '明日は雨！',
        '本当？',
      ]);
    });

    test('keeps closing quotes with their sentence', () {
      expect(_texts('<p>"Go away." She left.</p>'), [
        '"Go away."',
        'She left.',
      ]);
    });

    test('keeps a sentence spanning inline elements as one segment', () {
      final result = segmentBlocks(
        dom.DocumentFragment.html('<p>A <em>very</em> long day. Next.</p>'),
      );

      expect(result.segments.map((s) => s.text), ['A very long day.', 'Next.']);
      expect(result.parts.where((p) => p.segment == 0).length, 3);
    });

    test('treats br as a sentence break', () {
      expect(_texts('<p>Line one<br>Line two</p>'), ['Line one', 'Line two']);
    });

    test('splits preformatted text at newlines', () {
      expect(_texts('<pre>first line\nsecond line</pre>'), [
        'first line',
        'second line',
      ]);
    });

    test('skips ruby annotations, scripts, styles and svg', () {
      expect(
        _texts(
          '<p>漢<rt>kan</rt><rp>(</rp>字. <script>x()</script>'
          '<style>p{}</style><svg><text>no</text></svg>Done.</p>',
        ),
        ['漢字.', 'Done.'],
      );
    });

    test('skips blocks without speakable text', () {
      expect(_texts('<p>   </p><p>* * *</p><p>Hi.</p>'), ['Hi.']);
    });

    test('reads nested blocks separately', () {
      expect(_texts('<ul><li>Item <p>Inner.</p></li></ul>'), [
        'Item',
        'Inner.',
      ]);
    });

    test('reads a div with direct text', () {
      expect(_texts('<div>Hello there.<div>Inner.</div></div>'), [
        'Hello there.',
        'Inner.',
      ]);
    });

    test('caps long sentences at commas, then whitespace', () {
      final clause = '${'word ' * 40}clause,';
      final result = segmentBlocks(
        dom.DocumentFragment.html('<p>${'$clause ' * 3}end.</p>'),
      );

      expect(result.segments.length, greaterThan(1));
      expect(
        result.segments.every((s) => s.text.length <= ttsMaxSegmentLength),
        isTrue,
      );
      expect(result.segments.first.text, endsWith(','));

      final noCommas = segmentBlocks(
        dom.DocumentFragment.html('<p>${'word ' * 200}</p>'),
      );
      expect(noCommas.segments.length, greaterThan(1));
    });

    test('records the scroll id of the block', () {
      final root = _process('<p>One.</p><p>Two.</p>');
      final op = TtsSegmentOperation();
      EpubPagePreprocessor(
        html: dom.DocumentFragment.html('<p>One.</p><p>Two.</p>'),
        operations: [op],
      ).process();

      expect(op.segments.map((s) => s.blockScrollId), [
        root.querySelectorAll('p')[0].xpath(),
        root.querySelectorAll('p')[1].xpath(),
      ]);
    });
  });

  group('TtsSegmentOperation', () {
    const html =
        '<h1>Title</h1><p>One <b>bold</b>. Two.</p>'
        '<div><p id="x">Three.</p><ul><li>A.</li><li>B. C.</li></ul></div>';

    test('wraps only text, so existing XPaths are unchanged', () {
      final plain = _scrollIds(html, withTts: false);
      final wrapped = _scrollIds(html, withTts: true);

      expect(wrapped, plain);
    });

    test('wraps every segment text node with the segment index', () {
      final root = _process(html, withTts: true);
      final wrappers = root.querySelectorAll(HtmlConstants.ttsSegmentTag);

      expect(wrappers, isNotEmpty);
      expect(
        wrappers.every(
          (e) => e.attributes[HtmlConstants.ttsSegmentAttribute] != null,
        ),
        isTrue,
      );
      expect(root.text, _process(html).text);
    });

    test('provider-style run produces the same segments as the wrappers', () {
      final op = TtsSegmentOperation();
      final root = EpubPagePreprocessor(
        html: dom.DocumentFragment.html(html),
        operations: [op],
      ).process();

      final indexes = root
          .querySelectorAll(HtmlConstants.ttsSegmentTag)
          .map(
            (e) => int.parse(e.attributes[HtmlConstants.ttsSegmentAttribute]!),
          )
          .toSet();

      expect(indexes, {for (final s in op.segments) s.index});

      for (final segment in op.segments) {
        final text = root
            .querySelectorAll(
              '[${HtmlConstants.ttsSegmentAttribute}="${segment.index}"]',
            )
            .map((e) => e.text)
            .join()
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        expect(text, segment.text);
      }
    });

    test('is deterministic', () {
      List<TtsSegment> run() {
        final op = TtsSegmentOperation();
        EpubPagePreprocessor(
          html: dom.DocumentFragment.html(html),
          operations: [op],
        ).process();
        return op.segments;
      }

      expect(run(), run());
    });
  });
}

List<String> _texts(String html) => segmentBlocks(
  dom.DocumentFragment.html(html),
).segments.map((s) => s.text).toList();

dom.DocumentFragment _process(String html, {bool withTts = false}) {
  return EpubPagePreprocessor(
    html: dom.DocumentFragment.html(html),
    operations: [if (withTts) TtsSegmentOperation()],
  ).process();
}

List<String> _scrollIds(String html, {required bool withTts}) {
  final root = EpubPagePreprocessor(
    html: dom.DocumentFragment.html(html),
    operations: [if (withTts) TtsSegmentOperation(), ScrollIdOperation()],
  ).process();

  return [
    for (final element in root.querySelectorAll('*'))
      if (element.localName != HtmlConstants.ttsSegmentTag)
        element.attributes[HtmlConstants.scrollIdAttribute]!,
  ];
}
