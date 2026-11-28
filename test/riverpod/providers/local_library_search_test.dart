import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/models/enums/local_book_source.dart';
import 'package:kover/models/local_book_model.dart';
import 'package:kover/riverpod/providers/local_library.dart';
import 'package:kover/riverpod/repository/local_library_repository.dart';

class _FakeRepository implements LocalLibraryRepository {
  final List<LocalBookModel> books;

  _FakeRepository(this.books);

  @override
  Stream<List<LocalBookModel>> watchBooks({
    LocalBookSource? source,
    bool favoritesOnly = false,
  }) => Stream.value(books);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

LocalBookModel _book(
  int id,
  String title, {
  String? author,
  LocalBookSource source = LocalBookSource.device,
}) {
  return LocalBookModel(
    id: id,
    title: title,
    author: author,
    language: null,
    format: .epub,
    source: source,
    remoteId: null,
    fileName: '$title.epub',
    filePath: 'local_books/$title.epub',
    fileSize: 1,
    pages: 10,
    pagesRead: 0,
    bookScrollId: null,
    lastRead: null,
    created: DateTime(2026),
  );
}

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        localLibraryRepositoryProvider.overrideWithValue(
          _FakeRepository([
            _book(1, 'Dune', author: 'Frank Herbert'),
            _book(2, 'Bàn Long', source: LocalBookSource.googleDrive),
            _book(3, 'Emma', author: 'Jane Austen'),
            _book(
              4,
              'Truyện BÀN tay',
              author: 'Nguyễn',
              source: LocalBookSource.googleDrive,
            ),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<Map<LocalBookSource, List<int>>> search(String query) async {
    final provider = searchLocalBooksProvider(query);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    final result = await container.read(provider.future);
    return {
      for (final entry in result.entries)
        entry.key: entry.value.map((book) => book.id).toList(),
    };
  }

  test('matches the title case-insensitively', () async {
    expect(await search('dUNE'), {
      LocalBookSource.device: [1],
    });
  });

  test('matches the author', () async {
    expect(await search('austen'), {
      LocalBookSource.device: [3],
    });
  });

  test('matches Vietnamese text regardless of case', () async {
    expect(await search('bàn'), {
      LocalBookSource.googleDrive: [2, 4],
    });
    expect(await search('NGUYỄN'), {
      LocalBookSource.googleDrive: [4],
    });
  });

  test('splits the matches by source', () async {
    expect(await search('n'), {
      LocalBookSource.device: [1, 3],
      LocalBookSource.googleDrive: [2, 4],
    });
  });

  test('returns nothing when no book matches', () async {
    expect(await search('zzz'), isEmpty);
  });
}
