import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:kover/models/enums/format.dart';
import 'package:kover/utils/local_books/book_file_format.dart';

part 'drive_item_model.freezed.dart';

/// A folder or a supported book file in Google Drive.
@freezed
sealed class DriveItemModel with _$DriveItemModel {
  const DriveItemModel._();

  const factory DriveItemModel({
    required String id,
    required String name,
    required bool isFolder,
    int? size,
    DateTime? modifiedTime,
  }) = _DriveItemModel;

  Format? get format => isFolder ? null : formatForFileName(name);
}
