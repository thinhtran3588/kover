import 'package:drift/drift.dart';
import 'package:kover/database/app_database.dart';
import 'package:kover/database/app_database.steps.dart';

Future<void> migrateFrom16To17(
  AppDatabase db,
  Migrator m,
  Schema17 schema,
) async {
  await m.addColumn(schema.localBooks, schema.localBooks.isFavorite);
}
