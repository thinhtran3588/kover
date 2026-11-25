import 'package:kover/models/book_chapter_model.dart';
import 'package:kover/models/image_model.dart';
import 'package:kover/models/page_content.dart';
import 'package:kover/models/pdf_model.dart';
import 'package:kover/riverpod/providers/local_library.dart';
import 'package:kover/riverpod/repository/book_repository.dart';
import 'package:kover/utils/extensions/int.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'book.g.dart';

@riverpod
Stream<List<BookChapterModel>> bookChapters(
  Ref ref, {
  required int chapterId,
}) {
  if (chapterId.isLocalBook) {
    return Stream.fromFuture(
      ref.watch(localTocProvider(chapterId.localBookId).future),
    );
  }

  final repo = ref.watch(bookRepositoryProvider);
  return repo.watchBookChapters(chapterId).distinct();
}

@riverpod
Future<PageContent> epubPage(
  Ref ref, {
  required int chapterId,
  required int page,
}) async {
  if (chapterId.isLocalBook) {
    return ref.watch(
      localEpubPageProvider(id: chapterId.localBookId, page: page).future,
    );
  }

  final repo = ref.watch(bookRepositoryProvider);
  final content = await repo.getEpubPage(chapterId: chapterId, page: page);

  return content.copyWith(
    root: content.root,
  );
}

@riverpod
Future<ImageModel> imagePage(
  Ref ref, {
  required int chapterId,
  required int page,
}) async {
  if (chapterId.isLocalBook) {
    return ref.watch(
      localImagePageProvider(id: chapterId.localBookId, page: page).future,
    );
  }

  final repo = ref.watch(bookRepositoryProvider);
  return repo.getImagePage(chapterId: chapterId, page: page);
}

@riverpod
Future<PdfModel> pdf(Ref ref, {required int chapterId}) async {
  if (chapterId.isLocalBook) {
    return ref.watch(localPdfProvider(chapterId.localBookId).future);
  }

  final repo = ref.watch(bookRepositoryProvider);
  return repo.getPdf(chapterId: chapterId);
}
