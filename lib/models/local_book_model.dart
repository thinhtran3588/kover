import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:kover/database/app_database.dart';
import 'package:kover/models/chapter_model.dart';
import 'package:kover/models/enums/age_rating.dart';
import 'package:kover/models/enums/format.dart';
import 'package:kover/models/enums/local_book_source.dart';
import 'package:kover/models/enums/publication_status.dart';
import 'package:kover/models/progress_model.dart';
import 'package:kover/models/series_model.dart';

part 'local_book_model.freezed.dart';

@freezed
sealed class LocalBookModel with _$LocalBookModel {
  const LocalBookModel._();

  const factory LocalBookModel({
    required int id,
    required String title,
    required String? author,
    required String? language,
    required Format format,
    required LocalBookSource source,
    required String? remoteId,
    required String fileName,
    required String filePath,
    required int fileSize,
    required int pages,
    required int pagesRead,
    required String? bookScrollId,
    required DateTime? lastRead,
    required DateTime created,
  }) = _LocalBookModel;

  factory LocalBookModel.fromDatabaseModel(LocalBook row) {
    return LocalBookModel(
      id: row.id,
      title: row.title,
      author: row.author,
      language: row.language,
      format: row.format,
      source: row.source,
      remoteId: row.remoteId,
      fileName: row.fileName,
      filePath: row.filePath,
      fileSize: row.fileSize,
      pages: row.pages,
      pagesRead: row.pagesRead,
      bookScrollId: row.bookScrollId,
      lastRead: row.lastRead,
      created: row.created,
    );
  }

  double get progress =>
      pages == 0 ? 0 : (pagesRead / pages).clamp(0, 1).toDouble();

  /// The id the reader uses for both the series and the chapter of this book.
  int get readerId => -id;

  List<PersonModel> get _writers =>
      author == null ? const [] : [PersonModel(id: 0, name: author!)];

  SeriesModel toSeriesModel() {
    return SeriesModel(
      id: readerId,
      libraryId: -1,
      name: title,
      format: format,
      pages: pages,
      avgHoursToRead: 0,
      wordCount: null,
      primaryColor: null,
      secondaryColor: null,
      lastSynced: null,
    );
  }

  ChapterModel toChapterModel() {
    return ChapterModel(
      id: readerId,
      seriesId: readerId,
      volumeId: readerId,
      title: title,
      pages: pages,
      format: format,
      writers: _writers,
    );
  }

  ProgressModel? toProgressModel() {
    if (pagesRead == 0 && bookScrollId == null) return null;

    return ProgressModel(
      volumeId: readerId,
      chapterId: readerId,
      pageNum: pagesRead,
      seriesId: readerId,
      libraryId: -1,
      bookScrollId: bookScrollId,
      lastModified: lastRead,
    );
  }

  SeriesMetadataModel toSeriesMetadata() {
    return SeriesMetadataModel(
      seriesId: readerId,
      totalChapters: 1,
      releaseYear: null,
      summary: null,
      ageRating: AgeRating.unknown,
      language: language,
      publicationStatus: PublicationStatus.unknown,
      writers: _writers,
      coverArtists: const [],
      publishers: const [],
      characters: const [],
      pencillers: const [],
      inkers: const [],
      imprints: const [],
      colorists: const [],
      letterers: const [],
      editors: const [],
      translators: const [],
      teams: const [],
      locations: const [],
      genres: const [],
      tags: const [],
    );
  }
}
