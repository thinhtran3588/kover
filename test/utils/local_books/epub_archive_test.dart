import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart';
import 'package:kover/utils/local_books/epub_archive.dart';
import 'package:path/path.dart' as p;

// A 1x1 transparent PNG.
const _png = [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
];

const _container = '''
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''';

const _opf = '''
<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Test Book</dc:title>
    <dc:creator>Jane Doe</dc:creator>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="ch1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/>
    <item id="css" href="style.css" media-type="text/css"/>
    <item id="img" href="images/pic.png" media-type="image/png" properties="cover-image"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>''';

const _nav = '''
<?xml version="1.0"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
  <body>
    <nav epub:type="toc">
      <ol>
        <li><a href="text/ch1.xhtml">One</a></li>
        <li><a href="text/ch2.xhtml">Two</a>
          <ol><li><a href="text/ch2.xhtml#sec">Two B</a></li></ol>
        </li>
        <li><a href="text/missing.xhtml">Missing</a></li>
      </ol>
    </nav>
  </body>
</html>''';

const _ch1 = '''
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
  <head>
    <link rel="stylesheet" href="../style.css"/>
    <script>alert(1)</script>
  </head>
  <body class="main">
    <p>Hello <a href="ch2.xhtml#sec">next</a> <a href="#local">local</a>
      <a href="https://example.com">web</a></p>
    <img src="../images/pic.png"/>
    <script>alert(2)</script>
  </body>
</html>''';

const _ch2 = '''
<html xmlns="http://www.w3.org/1999/xhtml">
  <body><p id="sec">Second</p></body>
</html>''';

const _css = '''
@font-face { font-family: X; src: url(x.ttf); }
p { color: red; }''';

void main() {
  late Directory tempDir;
  late String epubPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('epub_archive_test');
    final archive = Archive()
      ..add(ArchiveFile.string('META-INF/container.xml', _container))
      ..add(ArchiveFile.string('OEBPS/content.opf', _opf))
      ..add(ArchiveFile.string('OEBPS/nav.xhtml', _nav))
      ..add(ArchiveFile.string('OEBPS/text/ch1.xhtml', _ch1))
      ..add(ArchiveFile.string('OEBPS/text/ch2.xhtml', _ch2))
      ..add(ArchiveFile.string('OEBPS/style.css', _css))
      ..add(ArchiveFile.bytes('OEBPS/images/pic.png', _png));
    epubPath = p.join(tempDir.path, 'book.epub');
    File(epubPath).writeAsBytesSync(ZipEncoder().encodeBytes(archive));
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  group('EpubArchive', () {
    test('reads metadata, spine and cover', () {
      final archive = EpubArchive.open(epubPath);
      addTearDown(archive.close);

      final info = archive.readInfo();

      expect(info.title, 'Test Book');
      expect(info.author, 'Jane Doe');
      expect(info.language, 'en');
      expect(info.spine, ['OEBPS/text/ch1.xhtml', 'OEBPS/text/ch2.xhtml']);
      expect(archive.readCover(), _png);
    });

    test('reads the table of contents, dropping unmapped entries', () {
      final archive = EpubArchive.open(epubPath);
      addTearDown(archive.close);

      final toc = archive.readToc();

      expect(toc.map((c) => (c.title, c.page)), [('One', 0), ('Two', 1)]);
      expect(toc[1].children.single.title, 'Two B');
      expect(toc[1].children.single.page, 1);
    });

    test('builds a page in the shape of the Kavita server', () {
      final archive = EpubArchive.open(epubPath);
      addTearDown(archive.close);

      final html = archive.buildPageHtml(0);
      final fragment = parseFragment(html);

      final style = fragment.querySelector('style')!;
      expect(style.text, contains('color: red'));
      expect(style.text, isNot(contains('@font-face')));
      expect(
        fragment.querySelector('img')!.attributes['src'],
        startsWith('data:image/png;base64,'),
      );
      final link = fragment.querySelector('a[kavita-page="1"]')!;
      expect(link.attributes['kavita-part'], 'sec');
      expect(
        fragment.querySelector('a[href="#local"]')!.attributes,
        isNot(contains('kavita-page')),
      );
      expect(
        fragment.querySelector('a[href="https://example.com"]')!.attributes,
        isNot(contains('kavita-page')),
      );
      expect(fragment.querySelector('script'), isNull);
      expect(fragment.querySelector('div.main p'), isNotNull);
    });
  });
}
