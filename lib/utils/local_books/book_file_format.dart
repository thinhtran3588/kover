import 'package:kover/models/enums/format.dart';
import 'package:path/path.dart' as p;

const supportedExtensions = ['epub', 'pdf', 'cbz', 'zip'];

/// The [Format] of the book file called [name], or null if it is not supported.
Format? formatForFileName(String name) {
  return switch (p.extension(name).toLowerCase()) {
    '.epub' => .epub,
    '.pdf' => .pdf,
    '.cbz' || '.zip' => .archive,
    _ => null,
  };
}
