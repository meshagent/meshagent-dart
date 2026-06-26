import 'dart:math' as math;

import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

import 'room_server_e2e_helpers.dart';

ArrowSchema _schema(Map<String, ArrowDataType> fields) {
  return ArrowSchema(fields.entries.map((entry) => ArrowField(name: entry.key, type: entry.value)).toList(growable: false));
}

ArrowRecordBatch _batch(ArrowSchema schema, List<Map<String, Object?>> rows) {
  return ArrowRecordBatch.fromColumns(
    schema: schema,
    columns: [
      for (final field in schema.fields) ArrowValueArray(field: field, values: [for (final row in rows) row[field.name]]),
    ],
  );
}

ArrowTable _table(ArrowSchema schema, List<Map<String, Object?>> rows) {
  return ArrowTable(schema: schema, batches: [_batch(schema, rows)]);
}

ArrowTable _tableFromBatches(List<ArrowRecordBatch> batches) {
  return ArrowTable(schema: batches.isEmpty ? const ArrowSchema([]) : batches.first.schema, batches: batches);
}

List<Map<String, Object?>> _rows(ArrowTable table) => table.toRows();

void main() {
  group('sqlite room server integration parity', skip: roomServerE2eSkipReason, () {
    test('sqlite_room_client_round_trip', () async {
      await withTwoRoomServerE2eClients((client, secondClient) async {
        final db = client.sqlite.database('app', namespace: ['team']);
        final secondDb = secondClient.sqlite.database('app', namespace: ['team']);

        await client.sqlite.createDatabase(name: 'app', namespace: ['team']);
        expect(await client.sqlite.listDatabases(namespace: ['team']), ['app']);
        expect(await secondClient.sqlite.listDatabases(namespace: ['team']), ['app']);

        final details = await db.inspectDatabase();
        expect(details.name, 'app');
        expect(details.namespace, ['team']);

        final usersSchema = _schema({
          'id': const ArrowIntType(bitWidth: 64, signed: true),
          'email': const ArrowUtf8Type(),
          'active': const ArrowIntType(bitWidth: 64, signed: true),
        });
        await db.createTableWithSchema(name: 'users', schema: usersSchema);
        expect(await db.listTables(), ['users']);
        expect(await secondDb.listTables(), ['users']);

        expect((await db.inspect('users')).fields.map((field) => field.name), ['id', 'email', 'active']);
        await db.addColumnsWithSchema(table: 'users', schema: _schema({'nickname': const ArrowUtf8Type()}));
        expect((await db.inspect('users')).fields.map((field) => field.name), contains('nickname'));
        await db.dropColumns(table: 'users', columns: ['nickname']);
        expect((await db.inspect('users')).fields.map((field) => field.name), isNot(contains('nickname')));

        await db.insert(
          table: 'users',
          records: _batch(usersSchema, [
            {'id': 1, 'email': 'alice@example.com', 'active': 1},
            {'id': 2, 'email': 'bob@example.com', 'active': 0},
          ]),
        );
        expect(await db.count(table: 'users'), 2);
        expect(_rows(await db.searchTable(table: 'users', where: {'active': 1}, select: ['email'])), [
          {'email': 'alice@example.com'},
        ]);
        expect(_rows(await secondDb.searchTable(table: 'users', where: {'active': 0}, select: ['email'])), [
          {'email': 'bob@example.com'},
        ]);

        expect(_rows(await db.sqlTable(query: 'SELECT id, email FROM users WHERE id = ?', params: [2])), [
          {'id': BigInt.from(2), 'email': 'bob@example.com'},
        ]);

        expect(await db.executeSqlStatement(query: 'UPDATE users SET active = ? WHERE id = ?', params: [1, 2]), 1);
        expect(await db.count(table: 'users', where: {'active': 1}), 2);

        await db.renameTable(name: 'users', newName: 'members');
        expect(await secondDb.listTables(), ['members']);
        await db.renameTable(name: 'members', newName: 'users');

        final searchBatches = await db.searchStream(table: 'users', where: 'active = ?', params: [1], select: ['id']).toList();
        expect(_rows(_tableFromBatches(searchBatches)), [
          {'id': BigInt.one},
          {'id': BigInt.from(2)},
        ]);

        final sqlBatches = await db.sqlStream(query: 'SELECT email FROM users ORDER BY id').toList();
        expect(_rows(_tableFromBatches(sqlBatches)), [
          {'email': 'alice@example.com'},
          {'email': 'bob@example.com'},
        ]);

        final query = await client.sqlite.openSqlQuery(
          database: db.database,
          namespace: db.namespace,
          query: 'SELECT id FROM users ORDER BY id',
        );
        final queryBatches = await client.sqlite.readSqlQuery(queryId: query.queryId).toList();
        expect(_rows(_tableFromBatches(queryBatches)), [
          {'id': BigInt.one},
          {'id': BigInt.from(2)},
        ]);
        await client.sqlite.closeSqlQuery(queryId: query.queryId);
        expect((await client.sqlite.cancelSqlQuery(queryId: query.queryId)).status, SqliteSqlCancelStatus.notCancellable);

        final bulkRows = 512;
        final bulkSchema = _schema({'id': const ArrowIntType(bitWidth: 64, signed: true), 'label': const ArrowUtf8Type()});
        await db.createTableFromArrowTable(
          name: 'bulk_events',
          table: _table(bulkSchema, [
            for (var index = 0; index < bulkRows; index++) {'id': index, 'label': 'event-$index'},
          ]),
        );
        final streamedBulk = await db.searchStream(table: 'bulk_events', select: ['id']).toList();
        expect(streamedBulk.map((batch) => batch.length).fold<int>(0, math.max), greaterThan(0));
        expect(streamedBulk.fold<int>(0, (sum, batch) => sum + batch.length), bulkRows);

        await db.dropTable(name: 'bulk_events');
        await db.dropTable(name: 'users');
        await db.dropDatabase();
        expect(await client.sqlite.listDatabases(namespace: ['team']), isEmpty);
      }, roomNamePrefix: 'dart-sqlite');
    });

    test('sqlite_room_client_isolates_multiple_databases_and_namespaces', () async {
      await withRoomServerE2eClient((client) async {
        final records = [
          (client.sqlite.database('app', namespace: ['team']), 'team-app'),
          (client.sqlite.database('analytics', namespace: ['team']), 'team-analytics'),
          (client.sqlite.database('app', namespace: ['other']), 'other-app'),
        ];
        final schema = _schema({'id': const ArrowIntType(bitWidth: 64, signed: true), 'label': const ArrowUtf8Type()});
        for (final record in records) {
          await record.$1.createDatabase();
          await record.$1.createTableFromArrowTable(
            name: 'events',
            table: _table(schema, [
              {'id': 1, 'label': record.$2},
            ]),
          );
        }

        expect(await client.sqlite.listDatabases(namespace: ['team']), ['analytics', 'app']);
        expect(await client.sqlite.listDatabases(namespace: ['other']), ['app']);

        for (final record in records) {
          expect(_rows(await record.$1.searchTable(table: 'events', select: ['label'])), [
            {'label': record.$2},
          ]);
        }
      }, roomNamePrefix: 'dart-sqlite');
    });
  });
}
