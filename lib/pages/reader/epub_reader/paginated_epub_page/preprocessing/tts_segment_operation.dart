import 'package:equatable/equatable.dart';
import 'package:html/dom.dart' as dom;
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/preprocessing/epub_page_preprocessor_operation.dart';
import 'package:kover/utils/constants/html_constants.dart';
import 'package:kover/utils/extensions/element.dart';

/// Longest sentence handed to a speech engine before it is split further.
const ttsMaxSegmentLength = 300;

/// A sentence-sized piece of text that is read aloud as one utterance.
class const TtsSegment({
  required final int index,
  required final String text,
  required final String? blockScrollId,
}) extends Equatable {
  @override
  List<Object?> get props => [index, text, blockScrollId];
}

/// The slice `[start, end)` of [node]'s data that belongs to [segment].
class TtsTextPart({
  required final dom.Text node,
  required final int start,
  required final int end,
  required final int segment,
});

class TtsSegmentation({
  required final List<TtsSegment> segments,
  required final List<TtsTextPart> parts,
});

const _blockTags = {
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'li',
  'blockquote',
  'dd',
  'dt',
  'td',
  'th',
  'figcaption',
  'pre',
  'div',
};

/// Elements that end the text of the enclosing block.
const _containerTags = {
  ..._blockTags,
  'ul',
  'ol',
  'dl',
  'table',
  'thead',
  'tbody',
  'tfoot',
  'tr',
  'section',
  'article',
  'aside',
  'header',
  'footer',
  'figure',
  'nav',
  'main',
  'hr',
  'details',
  'summary',
};

const _skippedTags = {'rt', 'rp', 'style', 'script', 'svg'};

/// Stands in for a `<br>` in the text of a block.
const _lineBreak = ' ';

const _abbreviations = {
  'mr',
  'mrs',
  'ms',
  'dr',
  'prof',
  'sr',
  'jr',
  'st',
  'vs',
  'fig',
  'vol',
  'inc',
  'ltd',
  'e.g',
  'i.e',
};

final _speakable = RegExp(r'[\p{L}\p{N}]', unicode: true);
final _whitespace = RegExp(r'\s+');
const _closers = '"\'”’)]}»›」』）】';
final _openers = RegExp('^[("\u201c\u2018\\[]+');
final _initial = RegExp(r'^\p{Lu}$', unicode: true);
final _lowercase = RegExp(r'^\p{Ll}$', unicode: true);

class _Piece({required final dom.Text node, required final int offset});

/// Splits the text of every block in [root] into sentence segments.
///
/// This does not modify [root]. Segment indexes run in document order.
TtsSegmentation segmentBlocks(dom.Node root) {
  final segments = <TtsSegment>[];
  final parts = <TtsTextPart>[];

  final blocks = switch (root) {
    dom.DocumentFragment() => root.querySelectorAll(_blockTags.join(',')),
    dom.Element() => root.querySelectorAll(_blockTags.join(',')),
    _ => const <dom.Element>[],
  };

  for (final block in blocks) {
    final buffer = StringBuffer();
    final pieces = <_Piece>[];
    _collect(block, buffer, pieces);

    final text = buffer.toString();
    final ranges = splitSentences(
      text,
      splitOnNewline: block.localName == 'pre',
    );
    String? scrollId;

    for (final (start, end) in ranges) {
      final spoken = text
          .substring(start, end)
          .replaceAll(_lineBreak, ' ')
          .replaceAll(_whitespace, ' ')
          .trim();
      if (!_speakable.hasMatch(spoken)) continue;

      scrollId ??= block.xpath();
      final index = segments.length;
      segments.add(
        TtsSegment(index: index, text: spoken, blockScrollId: scrollId),
      );

      for (var i = 0; i < pieces.length; i++) {
        final piece = pieces[i];
        final pieceEnd = piece.offset + piece.node.data.length;
        final from = start > piece.offset ? start : piece.offset;
        final to = end < pieceEnd ? end : pieceEnd;
        if (from >= to) continue;
        parts.add(
          TtsTextPart(
            node: piece.node,
            start: from - piece.offset,
            end: to - piece.offset,
            segment: index,
          ),
        );
      }
    }
  }

  return TtsSegmentation(segments: segments, parts: parts);
}

void _collect(
  dom.Element element,
  StringBuffer buffer,
  List<_Piece> pieces,
) {
  for (final node in element.nodes) {
    if (node is dom.Text) {
      if (node.data.isEmpty) continue;
      pieces.add(_Piece(node: node, offset: buffer.length));
      buffer.write(node.data);
    } else if (node is dom.Element) {
      final name = node.localName;
      if (_skippedTags.contains(name)) continue;
      if (name == 'br') {
        buffer.write(_lineBreak);
      } else if (!_containerTags.contains(name)) {
        _collect(node, buffer, pieces);
      }
    }
  }
}

/// Splits [text] into sentence ranges `[start, end)`.
///
/// Ranges are in order, never overlap and include the whitespace following
/// the sentence. Sentences longer than [ttsMaxSegmentLength] are split at
/// `,;:`, then at whitespace.
List<(int, int)> splitSentences(String text, {bool splitOnNewline = false}) {
  final ranges = <(int, int)>[];
  final length = text.length;
  var start = 0;
  var i = 0;

  void emit(int from, int to) {
    for (final (a, b) in _capped(text, from, to)) {
      if (text.substring(a, b).trim().isNotEmpty) ranges.add((a, b));
    }
  }

  while (i < length) {
    final char = text[i];

    if (char == _lineBreak || (splitOnNewline && char == '\n')) {
      emit(start, i);
      start = i + 1;
      i++;
      continue;
    }

    if (!_isTerminator(char)) {
      i++;
      continue;
    }

    var j = i + 1;
    while (j < length && _isTerminator(text[j])) {
      j++;
    }
    while (j < length && _closers.contains(text[j])) {
      j++;
    }

    final cjk = '。！？'.contains(char);
    final atBoundary =
        j >= length || _isSpace(text[j]) || text[j] == _lineBreak || cjk;
    if (!atBoundary || (!cjk && _isNotSentenceEnd(text, start, i, j))) {
      i = j;
      continue;
    }

    while (j < length && _isSpace(text[j])) {
      j++;
    }
    emit(start, j);
    start = j;
    i = j;
  }

  emit(start, length);
  return ranges;
}

bool _isTerminator(String char) => '.!?…。！？'.contains(char);

bool _isSpace(String char) => char != _lineBreak && _whitespace.hasMatch(char);

/// Whether the period at [i] belongs to an abbreviation or an initial, or the
/// sentence visibly continues in lowercase after it.
bool _isNotSentenceEnd(String text, int start, int i, int end) {
  if (text[i] != '.' || (i + 1 < text.length && _isTerminator(text[i + 1]))) {
    return false;
  }

  var wordStart = i;
  while (wordStart > start && !_isSpace(text[wordStart - 1])) {
    wordStart--;
  }
  final word = text.substring(wordStart, i).replaceFirst(_openers, '');

  if (_abbreviations.contains(word.toLowerCase()) || _initial.hasMatch(word)) {
    return true;
  }

  var next = end;
  while (next < text.length && _isSpace(text[next])) {
    next++;
  }
  return next < text.length && _lowercase.hasMatch(text[next]);
}

/// Splits `[from, to)` into pieces of at most [ttsMaxSegmentLength].
Iterable<(int, int)> _capped(String text, int from, int to) sync* {
  var start = from;
  while (to - start > ttsMaxSegmentLength) {
    final limit = start + ttsMaxSegmentLength;
    var cut = -1;
    for (var k = limit; k > start + ttsMaxSegmentLength ~/ 2; k--) {
      if (',;:'.contains(text[k - 1])) {
        cut = k;
        break;
      }
    }
    if (cut < 0) {
      for (var k = limit; k > start + ttsMaxSegmentLength ~/ 2; k--) {
        if (_isSpace(text[k - 1])) {
          cut = k;
          break;
        }
      }
    }
    if (cut < 0) cut = limit;

    while (cut < to && _isSpace(text[cut])) {
      cut++;
    }
    yield (start, cut);
    start = cut;
  }
  if (start < to) yield (start, to);
}

/// Wraps the text of every sentence in `<kover-tts kover-tts-seg="N">`.
///
/// Only text nodes are wrapped, so the XPath of every existing element, and
/// with it every Kavita scroll id, stays the same.
final class TtsSegmentOperation extends EpubPagePreprocessorOperation {
  var _segments = const <TtsSegment>[];

  /// The segments found by the last run, in document order.
  List<TtsSegment> get segments => _segments;

  @override
  void start(dom.DocumentFragment root) {
    final result = segmentBlocks(root);
    _segments = result.segments;

    final byNode = <dom.Text, List<TtsTextPart>>{};
    for (final part in result.parts) {
      byNode.putIfAbsent(part.node, () => []).add(part);
    }

    for (final MapEntry(key: node, value: parts) in byNode.entries) {
      final parent = node.parentNode;
      if (parent == null) continue;

      final data = node.data;
      var cursor = 0;
      void plain(int to) {
        if (to > cursor) {
          parent.insertBefore(dom.Text(data.substring(cursor, to)), node);
        }
      }

      for (final part in parts) {
        plain(part.start);
        parent.insertBefore(
          dom.Element.tag(HtmlConstants.ttsSegmentTag)
            ..attributes[HtmlConstants.ttsSegmentAttribute] = '${part.segment}'
            ..append(dom.Text(data.substring(part.start, part.end))),
          node,
        );
        cursor = part.end;
      }
      plain(data.length);
      node.remove();
    }
  }
}
