import 'package:sembast_web/sembast_web.dart';

/// IndexedDB keeps the same history/preferences contract as native SQLite.
class NotebookStore {
  Future<Database>? _database;
  Future<Database> get db =>
      _database ??= databaseFactoryWeb.openDatabase('jem_calc');
  final _preferences = StoreRef<String, Object?>('preferences');
  final _entries = intMapStoreFactory.store('entries');

  Future<Map<String, dynamic>> preferences() async => {
    for (final record in await _preferences.find(await db))
      record.key: record.value,
  };

  Future<void> set(String key, dynamic value) async {
    await _preferences.record(key).put(await db, value as Object?);
  }

  Future<List<Map<String, dynamic>>> history() async =>
      (await _entries.find(
            await db,
            finder: Finder(
              sortOrders: [SortOrder(Field.key, false)],
              limit: 200,
            ),
          ))
          .map((record) => <String, dynamic>{...record.value, 'id': record.key})
          .toList();

  Future<void> add(Map<String, dynamic> entry) async {
    await (await db).transaction((transaction) async {
      await _entries.add(transaction, entry);
      final old = await _entries.find(
        transaction,
        finder: Finder(sortOrders: [SortOrder(Field.key, false)], offset: 200),
      );
      await _entries
          .records(old.map((record) => record.key))
          .delete(transaction);
    });
  }

  Future<void> clear() async => _entries.delete(await db);
}
