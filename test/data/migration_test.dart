import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/data/database.dart';

import 'generated/schema.dart';

void main() {
  late SchemaVerifier verifier;
  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('fresh v1 database matches the dumped v1 schema', () async {
    final conn = await verifier.startAt(1);
    final db = AppDatabase(conn);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 1);
  });

  test('onCreate builds FTS table and sync triggers', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE name LIKE '%fts%'")
        .get();
    final names = rows.map((r) => r.read<String>('name')).toSet();
    expect(
      names,
      containsAll([
        'titles_fts',
        'titles_fts_ai',
        'titles_fts_ad',
        'titles_fts_au',
        'categories_fts_au',
      ]),
    );
    final v = await db.customSelect('PRAGMA user_version').getSingle();
    expect(v.read<int>('user_version'), 1);
  });

  // When schemaVersion becomes 2: dump schema, regenerate helpers, and add
  //   final schema = await verifier.schemaAt(1); ... migrateAndValidate(db, 2)
}
