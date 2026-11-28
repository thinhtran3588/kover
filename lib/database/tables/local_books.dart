import 'package:drift/drift.dart';
import 'package:kover/models/enums/format.dart';
import 'package:kover/models/enums/local_book_source.dart';

class LocalBooks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  TextColumn get author => text().nullable()();
  TextColumn get language => text().nullable()();
  TextColumn get format => textEnum<Format>()();
  TextColumn get source => textEnum<LocalBookSource>()();

  /// Remote file id, e.g. the Google Drive file id.
  TextColumn get remoteId => text().nullable()();

  /// Original file name, used for display and duplicate detection.
  TextColumn get fileName => text()();

  /// Path of the book file, relative to the application support directory.
  TextColumn get filePath => text()();
  IntColumn get fileSize => integer()();
  IntColumn get pages => integer()();
  BlobColumn get cover => blob().nullable()();
  IntColumn get pagesRead => integer().withDefault(const Constant(0))();
  TextColumn get bookScrollId => text().nullable()();
  DateTimeColumn get lastRead => dateTime().nullable()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  DateTimeColumn get created => dateTime().withDefault(currentDateAndTime)();
}
