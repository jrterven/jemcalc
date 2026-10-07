import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class NotebookStore {
  Database? _db;
  Future<Database> get db async => _db ??= await openDatabase(
    p.join(await getDatabasesPath(), 'jem_calc.db'),
    version: 1,
    onCreate: (db, _) async {
      await db.execute(
        'CREATE TABLE entries (id INTEGER PRIMARY KEY AUTOINCREMENT, payload TEXT NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE preferences (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
    },
  );
  Future<Map<String, dynamic>> preferences() async {
    final rows = await (await db).query('preferences');
    return {
      for (final row in rows)
        row['key'] as String: jsonDecode(row['value'] as String),
    };
  }

  Future<void> set(String key, dynamic value) async => (await db).insert(
    'preferences',
    {'key': key, 'value': jsonEncode(value)},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
  Future<List<Map<String, dynamic>>> history() async =>
      (await (await db).query('entries', orderBy: 'id DESC', limit: 200))
          .map(
            (r) => {
              ...jsonDecode(r['payload'] as String) as Map<String, dynamic>,
              'id': r['id'],
            },
          )
          .toList();
  Future<void> add(Map<String, dynamic> entry) async {
    final d = await db;
    await d.insert('entries', {'payload': jsonEncode(entry)});
    await d.execute(
      'DELETE FROM entries WHERE id NOT IN (SELECT id FROM entries ORDER BY id DESC LIMIT 200)',
    );
  }

  Future<void> clear() async => (await db).delete('entries');
}
