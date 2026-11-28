import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:kover/sync/google_drive_operations.dart';

drive.File _file(String name, {String? mime, String? size}) =>
    drive.File(id: 'id-$name', name: name, mimeType: mime, size: size);

void main() {
  group('queries', () {
    test('escapes backslashes and quotes', () {
      expect(GoogleDriveOperations.escape("O'Reilly"), r"O\'Reilly");
      expect(GoogleDriveOperations.escape(r'a\b'), r'a\\b');
    });

    test('folder query restricts to the parent and supported types', () {
      final q = GoogleDriveOperations.folderQuery('abc');
      expect(q, startsWith("'abc' in parents and trashed = false"));
      expect(q, contains("mimeType = 'application/epub+zip'"));
      expect(q, contains("name contains '.cbz'"));
    });

    test('search query escapes the text', () {
      expect(
        GoogleDriveOperations.searchQuery("O'Reilly"),
        startsWith(r"name contains 'O\'Reilly' and trashed = false"),
      );
    });

    test('shared query', () {
      expect(
        GoogleDriveOperations.sharedQuery(),
        startsWith('sharedWithMe = true and trashed = false'),
      );
    });
  });

  test('filterItems keeps folders and supported books only', () {
    final items = GoogleDriveOperations.filterItems([
      _file('Comics', mime: 'application/vnd.google-apps.folder'),
      _file('book.epub', size: '2048'),
      _file('scan.PDF'),
      _file('issue.cbz'),
      _file('notes.txt'),
      _file('photo.jpg'),
      drive.File(name: 'no id.epub'),
    ]);

    expect(items.map((i) => i.name), [
      'Comics',
      'book.epub',
      'scan.PDF',
      'issue.cbz',
    ]);
    expect(items.first.isFolder, isTrue);
    expect(items[1].size, 2048);
  });
}
