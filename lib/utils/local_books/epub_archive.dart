import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:kover/models/book_chapter_model.dart';
import 'package:kover/utils/constants/html_constants.dart';
import 'package:kover/utils/epub_html.dart';
import 'package:path/path.dart' as p;

typedef EpubInfo = ({
  String? title,
  String? author,
  String? language,

  /// Zip paths of the spine documents in reading order.
  List<String> spine,

  /// Zip path of the cover image.
  String? coverHref,
});

typedef _ManifestItem = ({String href, String mediaType, String properties});

final _fontFace = RegExp(r'@font-face\s*\{[^}]*\}', caseSensitive: false);
final _selfClosing = RegExp(r'<([A-Za-z][^\s/>]*)([^<>]*?)/>');

/// A reader for EPUB files that produces page HTML in the shape the Kavita
/// server serves, so the EPUB reader can display it unchanged.
class EpubArchive {
  final InputFileStream _input;
  final Archive _archive;

  EpubInfo? _info;
  Map<String, _ManifestItem>? _manifest;
  String? _opfPath;

  EpubArchive._(this._input, this._archive);

  static EpubArchive open(String path) {
    final input = InputFileStream(path);
    try {
      return EpubArchive._(input, ZipDecoder().decodeStream(input));
    } catch (_) {
      input.closeSync();
      rethrow;
    }
  }

  void close() {
    _archive.clearSync();
    _input.closeSync();
  }

  Uint8List? readEntry(String path) => _archive.findFile(path)?.readBytes();

  String? _readText(String path) {
    final bytes = readEntry(path);
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }

  /// Parses XML leniently with the HTML parser. Self-closing tags are expanded
  /// first, as the HTML parser would otherwise nest the following siblings.
  static Document _parseXml(String xml) => parse(
    xml.replaceAllMapped(_selfClosing, (m) => '<${m[1]}${m[2]}></${m[1]}>'),
  );

  static Iterable<Element> _named(Node node, String name) =>
      (node is Document
              ? node.querySelectorAll('*')
              : (node as Element).querySelectorAll('*'))
          .where((e) => e.localName == name);

  static String? _attribute(Element element, String name) {
    for (final entry in element.attributes.entries) {
      final key = entry.key;
      final keyName = key is AttributeName ? key.name : key.toString();
      if (keyName == name || keyName == 'xlink:$name') return entry.value;
    }
    return null;
  }

  static String _resolve(String baseFile, String href) => p.posix.normalize(
    p.posix.join(p.posix.dirname(baseFile), Uri.decodeFull(href)),
  );

  /// Package document metadata, manifest and spine.
  EpubInfo readInfo() {
    final cached = _info;
    if (cached != null) return cached;

    final container = _readText('META-INF/container.xml');
    if (container == null) throw const FormatException('Missing container.xml');
    final opfPath = _named(
      _parseXml(container),
      'rootfile',
    ).map((e) => e.attributes['full-path']).nonNulls.firstOrNull;
    final opf = opfPath == null ? null : _readText(opfPath);
    if (opfPath == null || opf == null) {
      throw const FormatException('Missing package document');
    }
    _opfPath = opfPath;

    final doc = _parseXml(opf);
    String? text(String name) => _named(
      doc,
      name,
    ).map((e) => e.text.trim()).where((t) => t.isNotEmpty).firstOrNull;

    final manifest = <String, _ManifestItem>{
      for (final item in _named(doc, 'item'))
        if (item.attributes['id'] case final id?
            when item.attributes['href'] != null)
          id: (
            href: _resolve(opfPath, item.attributes['href']!),
            mediaType: item.attributes['media-type'] ?? '',
            properties: item.attributes['properties'] ?? '',
          ),
    };
    _manifest = manifest;

    final spine = [
      for (final ref in _named(doc, 'itemref'))
        if (manifest[ref.attributes['idref']] case final item?) item.href,
    ];

    String? coverHref = manifest.values
        .where((i) => i.properties.split(' ').contains('cover-image'))
        .map((i) => i.href)
        .firstOrNull;
    if (coverHref == null) {
      final coverId = _named(doc, 'meta')
          .where((m) => m.attributes['name'] == 'cover')
          .map((m) => m.attributes['content'])
          .firstOrNull;
      coverHref = manifest[coverId]?.href;
    }

    return _info = (
      title: text('dc:title'),
      author: text('dc:creator'),
      language: text('dc:language'),
      spine: spine,
      coverHref: coverHref ?? _firstImageOfFirstPage(spine),
    );
  }

  String? _firstImageOfFirstPage(List<String> spine) {
    if (spine.isEmpty) return null;
    final html = _readText(spine.first);
    if (html == null) return null;

    final doc = parse(html);
    for (final element in doc.querySelectorAll('img, image')) {
      final src = _attribute(
        element,
        element.localName == 'img' ? 'src' : 'href',
      );
      if (src != null && !src.startsWith('data:')) {
        return _resolve(spine.first, src);
      }
    }
    return null;
  }

  Uint8List? readCover() {
    final href = readInfo().coverHref;
    return href == null ? null : readEntry(href);
  }

  /// The table of contents, with page numbers being spine indices.
  List<BookChapterModel> readToc() {
    final info = readInfo();
    final manifest = _manifest!;
    final pageOf = {for (final (i, href) in info.spine.indexed) href: i};

    final nav = manifest.values
        .where((i) => i.properties.split(' ').contains('nav'))
        .firstOrNull;
    if (nav != null) {
      final toc = _readNavToc(nav.href, pageOf);
      if (toc.isNotEmpty) return toc;
    }

    final ncxId = _named(
      _parseXml(_readText(_opfPath!)!),
      'spine',
    ).map((e) => e.attributes['toc']).nonNulls.firstOrNull;
    final ncx = manifest[ncxId];
    return ncx == null ? const [] : _readNcxToc(ncx.href, pageOf);
  }

  List<BookChapterModel> _readNavToc(String navPath, Map<String, int> pageOf) {
    final html = _readText(navPath);
    if (html == null) return const [];

    final navElement = parse(html)
        .querySelectorAll('nav')
        .where(
          (n) => (_attribute(n, 'epub:type') ?? n.attributes['type'] ?? '')
              .split(' ')
              .contains('toc'),
        )
        .firstOrNull;
    final list = navElement?.children
        .where((e) => e.localName == 'ol')
        .firstOrNull;
    if (list == null) return const [];

    List<BookChapterModel> walk(Element ol) {
      final result = <BookChapterModel>[];
      for (final li in ol.children.where((e) => e.localName == 'li')) {
        final nested = li.children
            .where((e) => e.localName == 'ol')
            .firstOrNull;
        final children = nested == null ? <BookChapterModel>[] : walk(nested);
        final link = li.children.where((e) => e.localName == 'a').firstOrNull;
        final page = _pageForHref(navPath, link?.attributes['href'], pageOf);
        if (link == null || page == null) {
          result.addAll(children);
        } else {
          result.add(
            BookChapterModel(
              title: link.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
              page: page,
              children: children,
            ),
          );
        }
      }
      return result;
    }

    return walk(list);
  }

  List<BookChapterModel> _readNcxToc(String ncxPath, Map<String, int> pageOf) {
    final xml = _readText(ncxPath);
    if (xml == null) return const [];

    List<BookChapterModel> walk(Iterable<Element> points) {
      final result = <BookChapterModel>[];
      for (final point in points) {
        final children = walk(
          point.children.where((e) => e.localName == 'navpoint'),
        );
        final src = point.children
            .where((e) => e.localName == 'content')
            .map((e) => e.attributes['src'])
            .firstOrNull;
        final page = _pageForHref(ncxPath, src, pageOf);
        final label = _named(point, 'text').firstOrNull;
        if (page == null || label == null) {
          result.addAll(children);
        } else {
          result.add(
            BookChapterModel(
              title: label.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
              page: page,
              children: children,
            ),
          );
        }
      }
      return result;
    }

    final doc = _parseXml(xml);
    final root = _named(doc, 'navmap').firstOrNull;
    if (root == null) return const [];
    return walk(root.children.where((e) => e.localName == 'navpoint'));
  }

  static int? _pageForHref(
    String baseFile,
    String? href,
    Map<String, int> pageOf,
  ) {
    if (href == null) return null;
    final path = href.split('#').first;
    if (path.isEmpty) return null;
    return pageOf[_resolve(baseFile, path)];
  }

  /// Builds the HTML fragment of spine item [index]: its styles followed by
  /// its body, with images inlined and internal links annotated.
  String buildPageHtml(int index) {
    final spine = readInfo().spine;
    final pagePath = spine[index];
    final pageOf = {for (final (i, href) in spine.indexed) href: i};

    final doc = parse(_readText(pagePath) ?? '');
    final head = doc.head;
    final body = doc.body;

    final styles = <Element>[];
    for (final element in head?.children ?? const <Element>[]) {
      String? css;
      if (element.localName == 'style') {
        css = element.text;
      } else if (element.localName == 'link' &&
          (element.attributes['rel'] ?? '')
              .toLowerCase()
              .split(' ')
              .contains('stylesheet') &&
          element.attributes['href'] != null) {
        css = _readText(_resolve(pagePath, element.attributes['href']!));
      }
      if (css == null) continue;
      styles.add(
        Element.tag('style')..text = css.replaceAll(_fontFace, ''),
      );
    }

    final wrapper = Element.tag('div');
    for (final name in ['class', 'style']) {
      final value = body?.attributes[name];
      if (value != null) wrapper.attributes[name] = value;
    }
    for (final node in List.of(body?.nodes ?? const <Node>[])) {
      wrapper.append(node);
    }

    for (final script in wrapper.querySelectorAll('script').toList()) {
      script.remove();
    }

    for (final img in wrapper.querySelectorAll('img').toList()) {
      final src = img.attributes['src'];
      final uri = _entryUri(pagePath, src);
      if (uri != null) img.attributes['src'] = uri;
    }

    for (final image in wrapper.querySelectorAll('svg image').toList()) {
      final uri = _entryUri(pagePath, _attribute(image, 'href'));
      if (uri != null) replaceSvgImage(image, uri);
    }

    for (final link in wrapper.querySelectorAll('a[href]').toList()) {
      final uri = Uri.tryParse(link.attributes['href']!);
      if (uri == null || uri.hasScheme || uri.path.isEmpty) continue;

      final target = pageOf[_resolve(pagePath, uri.path)];
      if (target == null) continue;

      link.attributes[HtmlConstants.kavitaPageAttribute] = '$target';
      if (uri.fragment.isNotEmpty) {
        link.attributes[HtmlConstants.kavitaPartAttribute] = uri.fragment;
        if ((_attribute(link, 'epub:type') ?? '')
            .split(' ')
            .contains('noteref')) {
          link.attributes[HtmlConstants.kavitaNoteRefAttribute] = uri.fragment;
        }
      }
    }

    return [...styles, wrapper].map((e) => e.outerHtml).join();
  }

  /// A `data:` URI for the entry [src] points to, or null if it is not an
  /// entry of the archive.
  String? _entryUri(String pagePath, String? src) {
    if (src == null || src.isEmpty || Uri.tryParse(src)?.hasScheme != false) {
      return null;
    }
    final bytes = readEntry(_resolve(pagePath, src.split('#').first));
    if (bytes == null) return null;

    final mime = switch (p.posix.extension(src).toLowerCase()) {
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.gif' => 'image/gif',
      '.svg' => 'image/svg+xml',
      '.webp' => 'image/webp',
      '.avif' => 'image/avif',
      _ => 'image/png',
    };
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }
}
