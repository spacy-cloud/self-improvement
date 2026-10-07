import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:self_improvement/core/database/app_database.dart';

/// Directory of the schema 1 fixtures. They were made with the unchanged code
/// of v0.1.0 before the schema 2 change, see
/// `test/fixtures/v1/generate_v1_fixtures.dart.txt`.
const String v1FixtureDirectory = 'test/fixtures/v1';

/// The SQL text dump of the schema 1 database: ten days of synthetic data in
/// all 19 tables, `PRAGMA user_version = 1`.
final String v1DatabaseScript = File('$v1FixtureDirectory/v1-database.sql')
    .readAsStringSync();

/// An in-memory SQLite database that holds the schema 1 fixture (and nothing
/// else). [extraSql] runs after it.
QueryExecutor v1FixtureExecutor({String? extraSql}) => NativeDatabase.memory(
  setup: (raw) {
    raw.execute(v1DatabaseScript);
    if (extraSql != null) {
      raw.execute(extraSql);
    }
  },
);

/// The schema 1 fixture as a file at [path]: created once by an instance that
/// does not upgrade, so the file stays a schema 1 database until the real app
/// code opens it.
Future<void> writeV1DatabaseFile(String path) async {
  final database = V1FixtureDatabase(
    NativeDatabase(
      File(path),
      setup: (raw) {
        final version = raw.select('PRAGMA user_version').first.columnAt(0);
        if (version == 0) {
          raw.execute(v1DatabaseScript);
        }
      },
    ),
  );
  await database.customSelect('SELECT 1').get();
  await database.close();
}

/// [AppDatabase] on a schema 1 file that is NOT upgraded: Drift sees version 1
/// and runs no migration, so a single migration step can be tried on it and
/// the old content compared with the new one. Never used outside tests.
class V1FixtureDatabase extends AppDatabase {
  V1FixtureDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

/// The columns of every table as they are in [database] right now, keyed by
/// table name (without `sqlite_*`), in table order.
Future<Map<String, List<String>>> columnsOfAllTables(
  AppDatabase database,
) async {
  final tables = await database
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )
      .map((row) => row.read<String>('name'))
      .get();
  final result = <String, List<String>>{};
  for (final table in tables) {
    final columns = await database
        .customSelect(
          'SELECT name FROM pragma_table_info(?1)',
          variables: [Variable<String>(table)],
        )
        .map((row) => row.read<String>('name'))
        .get();
    result[table] = columns;
  }
  return result;
}

/// Every row of every table in [columns] over exactly the listed columns,
/// ordered by rowid, each row as JSON text. Comparing two such snapshots
/// proves that no value of these columns changed.
Future<Map<String, List<String>>> rowsOfAllTables(
  AppDatabase database,
  Map<String, List<String>> columns,
) async {
  final result = <String, List<String>>{};
  for (final entry in columns.entries) {
    final list = entry.value.map((c) => '"$c"').join(', ');
    final rows = await database
        .customSelect('SELECT $list FROM "${entry.key}" ORDER BY rowid')
        .get();
    result[entry.key] = [
      for (final row in rows) jsonEncode(row.data.values.toList()),
    ];
  }
  return result;
}

/// Number of rows per table.
Future<Map<String, int>> rowCounts(AppDatabase database) async {
  final tables = await columnsOfAllTables(database);
  final result = <String, int>{};
  for (final table in tables.keys) {
    final row = await database
        .customSelect('SELECT COUNT(*) AS n FROM "$table"')
        .getSingle();
    result[table] = row.read<int>('n');
  }
  return result;
}

/// The structure of the database as text: one line per table and index
/// (`type name (table): normalized SQL`). Two databases with the same
/// structure have the same lines; the white space and the quotes of the
/// stored `CREATE` statements are normalized.
Future<List<String>> schemaLines(AppDatabase database) async {
  final rows = await database
      .customSelect(
        'SELECT type, name, tbl_name, sql FROM sqlite_master '
        "WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' "
        'ORDER BY type, name',
      )
      .get();
  return [
    for (final row in rows)
      '${row.read<String>('type')} ${row.read<String>('name')} '
          '(${row.read<String>('tbl_name')}): '
          '${_normalizeSql(row.read<String>('sql'))}',
  ];
}

String _normalizeSql(String sql) =>
    sql.replaceAll('"', '').replaceAll(RegExp(r'\s+'), ' ').trim();

/// `PRAGMA user_version`.
Future<int> userVersion(AppDatabase database) async =>
    (await database.customSelect('PRAGMA user_version').getSingle()).read<int>(
      'user_version',
    );

/// The result of `PRAGMA integrity_check` (the single word `ok` when sound).
Future<List<String>> integrityCheck(AppDatabase database) async => database
    .customSelect('PRAGMA integrity_check')
    .map((row) => row.read<String>('integrity_check'))
    .get();

/// The rows of `PRAGMA foreign_key_check`: empty when no foreign key is
/// violated.
Future<List<String>> foreignKeyViolations(AppDatabase database) async =>
    database
        .customSelect('PRAGMA foreign_key_check')
        .map((row) => jsonEncode(row.data))
        .get();
