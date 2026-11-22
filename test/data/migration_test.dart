import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/data/database.dart';

import 'generated/schema.dart';

void main() {
  late SchemaVerifier verifier;
  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('fresh v2 database matches the dumped v2 schema', () async {
    final conn = await verifier.startAt(2);
    final db = AppDatabase(conn);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 2);
  });

  test('v1 database migrates to v2 and validates', () async {
    final schema = await verifier.schemaAt(1);
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 2);
  });

  test('v1 -> v2 keeps data and adds TMDB tables with people FTS', () async {
    final schema = await verifier.schemaAt(1);
    final raw = schema.rawDatabase;
    raw.execute("INSERT INTO sources(host) VALUES ('h')");
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    // Opening runs onUpgrade 1 -> 2.
    final names =
        (await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE name LIKE '%tmdb%' OR name LIKE 'title_%' OR name LIKE 'people_fts%'",
                )
                .get())
            .map((r) => r.read<String>('name'))
            .toSet();
    expect(
      names,
      containsAll([
        'tmdb_meta',
        'tmdb_genres',
        'title_genres',
        'tmdb_people',
        'title_cast',
        'people_fts',
        'people_fts_ai',
        'people_fts_ad',
        'people_fts_au',
      ]),
    );
    final src = await db.customSelect('SELECT host FROM sources').get();
    expect(src.single.read<String>('host'), 'h');
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
        'people_fts',
      ]),
    );
    final v = await db.customSelect('PRAGMA user_version').getSingle();
    expect(v.read<int>('user_version'), 2);
  });
}
