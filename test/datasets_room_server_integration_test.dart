import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

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

Future<List<Map<String, Object?>>> _searchRows(
  RoomClient client, {
  required String table,
  Object? where,
  List<String>? namespace,
  String? branch,
  int? version,
}) async {
  final result = await client.datasets.searchTable(table: table, where: where, namespace: namespace, branch: branch, version: version);
  return result.toRows();
}

List<int> _ids(List<Map<String, Object?>> rows) {
  return rows.map((row) => (row['id'] as BigInt).toInt()).toList()..sort();
}

void main() {
  group('datasets room server integration parity', skip: roomServerE2eSkipReason, () {
    test('list_tables_empty', () async {
      await withTwoRoomServerE2eClients((client1, _) async {
        expect(await client1.datasets.listTables(), isEmpty);
      }, roomNamePrefix: 'dart-datasets');
    });

    test('create_table_with_schema', () async {
      await withTwoRoomServerE2eClients((client1, _) async {
        await client1.datasets.createTableWithSchema(
          name: 'test_table_schema',
          schema: _schema({'id': const ArrowIntType(bitWidth: 64, signed: true)}),
        );
        expect(await client1.datasets.listTables(), contains('test_table_schema'));
      }, roomNamePrefix: 'dart-datasets');
    });

    test('create_table_with_schema_namespace', () async {
      await withTwoRoomServerE2eClients((client1, _) async {
        final schema = _schema({'id': const ArrowIntType(bitWidth: 64, signed: true)});
        await client1.datasets.createTableWithSchema(name: 'test_namespaced_table', namespace: ['team'], schema: schema);
        expect(await client1.datasets.listTables(namespace: ['team']), contains('test_namespaced_table'));
        await client1.datasets.insert(
          table: 'test_namespaced_table',
          namespace: ['team'],
          records: _batch(schema, [
            {'id': 1},
          ]),
        );
        final inspected = await client1.datasets.inspect('test_namespaced_table', namespace: ['team']);
        final rows = await _searchRows(client1, table: 'test_namespaced_table', namespace: ['team']);
        expect(inspected.fields.single.name, 'id');
        expect(rows, [
          {'id': BigInt.one},
        ]);
      }, roomNamePrefix: 'dart-datasets');
    });

    test('create_table_with_schema_namespace_create_if_not_exists_is_idempotent', () async {
      await withTwoRoomServerE2eClients((client1, client2) async {
        final schema = _schema({'id': const ArrowIntType(bitWidth: 64, signed: true)});
        const namespace = ['agents', 'assistant', 'threads'];
        await client1.datasets.createTableWithSchema(
          name: 'idempotent',
          namespace: namespace,
          schema: schema,
          mode: CreateMode.createIfNotExists,
        );
        await client2.datasets.createTableWithSchema(
          name: 'idempotent',
          namespace: namespace,
          schema: schema,
          mode: CreateMode.createIfNotExists,
        );
        await client1.datasets.insert(
          table: 'idempotent',
          namespace: namespace,
          records: _batch(schema, [
            {'id': 1},
          ]),
        );
        expect(await _searchRows(client1, table: 'idempotent', namespace: namespace), [
          {'id': BigInt.one},
        ]);
      }, roomNamePrefix: 'dart-datasets');
    });

    test('create_table_with_schema_namespace_create_if_not_exists_concurrent', () async {
      await withTwoRoomServerE2eClients((client1, client2) async {
        final schema = _schema({'id': const ArrowIntType(bitWidth: 64, signed: true)});
        const namespace = ['agents', 'assistant', 'threads'];
        await Future.wait([
          client1.datasets.createTableWithSchema(
            name: 'concurrent',
            namespace: namespace,
            schema: schema,
            mode: CreateMode.createIfNotExists,
          ),
          client2.datasets.createTableWithSchema(
            name: 'concurrent',
            namespace: namespace,
            schema: schema,
            mode: CreateMode.createIfNotExists,
          ),
        ]);
        await client1.datasets.insert(
          table: 'concurrent',
          namespace: namespace,
          records: _batch(schema, [
            {'id': 1},
          ]),
        );
        expect(await _searchRows(client1, table: 'concurrent', namespace: namespace), [
          {'id': BigInt.one},
        ]);
      }, roomNamePrefix: 'dart-datasets');
    });

    test('create_table_with_empty_name_fails', () async {
      await withTwoRoomServerE2eClients((client1, _) async {
        expect(
          () =>
              client1.datasets.createTableWithSchema(name: '   ', schema: _schema({'id': const ArrowIntType(bitWidth: 64, signed: true)})),
          throwsA(isA<ArgumentError>()),
        );
      }, roomNamePrefix: 'dart-datasets');
    });

    test('create_table_from_binary_data and binary schema', () async {
      await withTwoRoomServerE2eClients((client1, _) async {
        await client1.datasets.createTableFromData(
          name: 'binary_from_data',
          data: [
            {'data': Uint8List.fromList('hello world'.codeUnits)},
          ],
        );
        final schema = _schema({'data': const ArrowBinaryType()});
        await client1.datasets.createTableWithSchema(name: 'binary_schema', schema: schema);
        await client1.datasets.insert(
          table: 'binary_schema',
          records: _batch(schema, [
            {'data': Uint8List.fromList('hello world'.codeUnits)},
          ]),
        );
        final rows = await _searchRows(client1, table: 'binary_schema');
        expect(String.fromCharCodes(rows.single['data'] as Uint8List), 'hello world');
      }, roomNamePrefix: 'dart-datasets');
    });

    test('create_table_with_uuid_data_schema', () async {
      await withTwoRoomServerE2eClients((client1, _) async {
        final id = UuidValue.withValidation('123e4567-e89b-12d3-a456-426614174000');
        final schema = parseArrowSchema('id uuid');
        await client1.datasets.createTableWithSchema(name: 'uuid_table', schema: schema);
        await client1.datasets.insert(
          table: 'uuid_table',
          records: _batch(schema, [
            {'id': id.toBytes(validate: true)},
          ]),
        );
        final rows = await _searchRows(client1, table: 'uuid_table', where: {'id': id});
        expect(rows, hasLength(1));
      }, roomNamePrefix: 'dart-datasets');
    });

    test('insert_and_merge_reject_expression_values_for_arrow_writes', () async {
      await withTwoRoomServerE2eClients((client1, _) async {
        final schema = parseArrowSchema('key utf8, id uuid');
        await client1.datasets.createTableWithSchema(name: 'expr_table', schema: schema);
        expect(
          () => _batch(schema, [
            {'key': 'alpha', 'id': DatasetExpression('uuid()')},
          ]).ipcBytes,
          throwsA(anything),
        );
        expect(
          () => _batch(schema, [
            {'key': 'alpha', 'id': DatasetExpression('uuid()')},
          ]).ipcBytes,
          throwsA(anything),
        );
      }, roomNamePrefix: 'dart-datasets');
    });

    test('create_table_with_list_struct_schema', () async {
      await withTwoRoomServerE2eClients((client1, _) async {
        final schema = ArrowSchema([
          const ArrowField(name: 'id', type: ArrowIntType(bitWidth: 64, signed: true)),
          ArrowField(
            name: 'annotations',
            type: ArrowListType(
              ArrowField(
                name: 'item',
                type: ArrowStructType([
                  const ArrowField(name: 'key', type: ArrowUtf8Type(), nullable: false),
                  const ArrowField(name: 'value', type: ArrowUtf8Type()),
                ]),
              ),
            ),
          ),
        ]);
        await client1.datasets.createTableWithSchema(name: 'list_struct_table', schema: schema);
        await client1.datasets.insert(
          table: 'list_struct_table',
          records: _batch(schema, [
            {
              'id': 1,
              'annotations': [
                {'key': 'source', 'value': 'image_generation'},
                {'key': 'model', 'value': 'test'},
              ],
            },
          ]),
        );
        final rows = await _searchRows(client1, table: 'list_struct_table', where: {'id': 1});
        expect(rows.single['annotations'], [
          {'key': 'source', 'value': 'image_generation'},
          {'key': 'model', 'value': 'test'},
        ]);
      }, roomNamePrefix: 'dart-datasets');
    });

    test('create_table_with_json_schema', () async {
      await withTwoRoomServerE2eClients((client1, _) async {
        final schema = ArrowSchema([
          const ArrowField(name: 'id', type: ArrowIntType(bitWidth: 64, signed: true)),
          const ArrowField(name: 'payload', type: ArrowUtf8Type(), metadata: {arrowExtensionNameMetadataKey: arrowJsonExtensionName}),
        ]);
        final payload = {
          'kind': 'demo',
          'count': 3,
          'tags': ['x', 'y'],
        };
        await client1.datasets.createTableWithSchema(name: 'json_table', schema: schema);
        await client1.datasets.insert(
          table: 'json_table',
          records: _batch(schema, [
            {'id': 1, 'payload': jsonEncode(payload)},
          ]),
        );
        final rows = await _searchRows(client1, table: 'json_table', where: {'id': 1});
        expect(rows, hasLength(1));
      }, roomNamePrefix: 'dart-datasets');
    });

    test('drop_table and rename_table', () async {
      await withTwoRoomServerE2eClients((client1, client2) async {
        final schema = _schema({'id': const ArrowIntType(bitWidth: 64, signed: true), 'label': const ArrowUtf8Type()});
        await client1.datasets.createTableWithSchema(name: 'drop_me', schema: schema);
        expect(await client1.datasets.listTables(), contains('drop_me'));
        await client1.datasets.dropTable(name: 'drop_me');
        expect(await client1.datasets.listTables(), isNot(contains('drop_me')));

        await client1.datasets.createTableWithSchema(name: 'rename_old', schema: schema);
        await client1.datasets.insert(
          table: 'rename_old',
          records: _batch(schema, [
            {'id': 1, 'label': 'alpha'},
          ]),
        );
        await client1.datasets.renameTable(name: 'rename_old', newName: 'rename_new');
        expect(await client2.datasets.listTables(), contains('rename_new'));
        expect(await _searchRows(client2, table: 'rename_new'), [
          {'id': BigInt.one, 'label': 'alpha'},
        ]);
      }, roomNamePrefix: 'dart-datasets');
    });

    test('insert_search_update_delete_merge', () async {
      await withTwoRoomServerE2eClients((client1, _) async {
        final schema = _schema({'id': const ArrowIntType(bitWidth: 64, signed: true), 'name': const ArrowUtf8Type()});
        await client1.datasets.createTableWithSchema(name: 'crud_table', schema: schema);
        await client1.datasets.insert(
          table: 'crud_table',
          records: _batch(schema, [
            {'id': 2, 'name': 'Bob'},
          ]),
        );
        expect(await _searchRows(client1, table: 'crud_table', where: {'id': 2}), [
          {'id': BigInt.from(2), 'name': 'Bob'},
        ]);
        await client1.datasets.update(table: 'crud_table', where: 'id = 2', values: {'name': 'Robert'});
        expect(await _searchRows(client1, table: 'crud_table', where: {'id': 2}), [
          {'id': BigInt.from(2), 'name': 'Robert'},
        ]);
        await client1.datasets.merge(
          table: 'crud_table',
          on: 'id',
          records: _batch(schema, [
            {'id': 2, 'name': 'Caroline'},
          ]),
        );
        expect(await _searchRows(client1, table: 'crud_table', where: {'id': 2}), [
          {'id': BigInt.from(2), 'name': 'Caroline'},
        ]);
        await client1.datasets.delete(table: 'crud_table', where: 'id = 2');
        expect(await _searchRows(client1, table: 'crud_table', where: {'id': 2}), isEmpty);
      }, roomNamePrefix: 'dart-datasets');
    });

    test('update_supports_function_expression_values', () async {
      await withTwoRoomServerE2eClients((client1, _) async {
        final schema = parseArrowSchema('key int64, id int64');
        await client1.datasets.createTableWithSchema(name: 'uuid_function_update_table', schema: schema);
        await client1.datasets.insert(
          table: 'uuid_function_update_table',
          records: _batch(schema, [
            {'key': 1, 'id': 1},
          ]),
        );
        await client1.datasets.update(table: 'uuid_function_update_table', where: 'key = 1', values: {'id': DatasetExpression('key + 41')});
        final rows = await _searchRows(client1, table: 'uuid_function_update_table', where: {'key': 1});
        expect(rows, [
          {'key': BigInt.one, 'id': BigInt.from(42)},
        ]);
      }, roomNamePrefix: 'dart-datasets');
    });

    test('sql_query', () async {
      await withTwoRoomServerE2eClients((client1, _) async {
        final users = _schema({'id': const ArrowIntType(bitWidth: 64, signed: true), 'name': const ArrowUtf8Type()});
        final orders = _schema({
          'id': const ArrowIntType(bitWidth: 64, signed: true),
          'user_id': const ArrowIntType(bitWidth: 64, signed: true),
          'amount': const ArrowIntType(bitWidth: 64, signed: true),
        });
        await client1.datasets.createTableWithSchema(name: 'users', schema: users);
        await client1.datasets.createTableWithSchema(name: 'orders', schema: orders);
        await client1.datasets.insert(
          table: 'users',
          records: _batch(users, [
            {'id': 1, 'name': 'Alice'},
            {'id': 2, 'name': 'Bob'},
          ]),
        );
        await client1.datasets.insert(
          table: 'orders',
          records: _batch(orders, [
            {'id': 10, 'user_id': 1, 'amount': 50},
            {'id': 11, 'user_id': 2, 'amount': 75},
            {'id': 12, 'user_id': 2, 'amount': 120},
          ]),
        );
        final table = await client1.datasets.sqlTable(
          query: 'SELECT u.name AS user_name, o.amount AS order_amount FROM users u JOIN orders o ON u.id = o.user_id WHERE o.amount > 60',
        );
        expect(table.toRows().map((row) => '${row['user_name']}:${row['order_amount']}').toSet(), {'Bob:75', 'Bob:120'});
      }, roomNamePrefix: 'dart-datasets');
    });

    test('optimize_create_indexes_add_drop_columns', () async {
      await withTwoRoomServerE2eClients((client1, _) async {
        final schema = ArrowSchema([
          const ArrowField(name: 'id', type: ArrowIntType(bitWidth: 64, signed: true)),
          const ArrowField(name: 'name', type: ArrowUtf8Type()),
          const ArrowField(
            name: 'embedding',
            type: ArrowFixedSizeListType(
              valueField: ArrowField(name: 'item', type: ArrowFloatingPointType(ArrowFloatingPointPrecision.doublePrecision)),
              listSize: 8,
            ),
          ),
        ]);
        await client1.datasets.createTableWithSchema(name: 'index_table', schema: schema);
        await client1.datasets.insert(
          table: 'index_table',
          records: _batch(schema, [
            for (var i = 0; i < 256; i++)
              {
                'id': i,
                'name': 'test',
                'embedding': [for (var j = 0; j < 8; j++) math.Random(i + j).nextDouble()],
              },
          ]),
        );
        await client1.datasets.createIndex(
          table: 'index_table',
          config: const DatasetIndexConfig(column: 'id', indexType: 'BTREE'),
        );
        await client1.datasets.createIndex(
          table: 'index_table',
          config: const DatasetIndexConfig(column: 'embedding', indexType: 'IVF_PQ', numPartitions: 16, numSubVectors: 2),
        );
        await client1.datasets.createIndex(
          table: 'index_table',
          config: const DatasetIndexConfig(column: 'name', indexType: 'INVERTED'),
        );
        expect(await client1.datasets.listIndexes('index_table'), isNotEmpty);
        await client1.datasets.optimize(table: 'index_table');
        await client1.datasets.addColumnWithExpression(table: 'index_table', newColumns: {'email': "'hello'"});
        await client1.datasets.dropColumns(table: 'index_table', columns: ['email']);
        final rows = await _searchRows(client1, table: 'index_table', where: {'id': 1});
        expect(rows.single.containsKey('email'), isFalse);
      }, roomNamePrefix: 'dart-datasets');
    });

    test('add_drop_columns_of_type', () async {
      await withTwoRoomServerE2eClients((client1, _) async {
        await client1.datasets.createTableFromData(
          name: 'typed_columns',
          data: [
            {'id': 1, 'name': 'Dave'},
          ],
        );
        await client1.datasets.addColumnsWithSchema(table: 'typed_columns', schema: _schema({'email': const ArrowUtf8Type()}));
        await client1.datasets.dropColumns(table: 'typed_columns', columns: ['email']);
        final rows = await _searchRows(client1, table: 'typed_columns', where: {'id': 1});
        expect(rows.single.containsKey('email'), isFalse);
      }, roomNamePrefix: 'dart-datasets');
    });

    test('insert_date_and_datetime', () async {
      await withTwoRoomServerE2eClients((client1, _) async {
        final dateSchema = _schema({
          'id': const ArrowIntType(bitWidth: 64, signed: true),
          'date': const ArrowDateType(ArrowDateUnit.millisecond),
        });
        await client1.datasets.createTableWithSchema(name: 'date_table', schema: dateSchema);
        await client1.datasets.insert(
          table: 'date_table',
          records: _batch(dateSchema, [
            {'id': 1, 'date': DateTime.parse('2025-01-01T00:00:00Z')},
          ]),
        );
        expect(await _searchRows(client1, table: 'date_table', where: "date=DATE '2025-01-01'"), isNotEmpty);

        final tsSchema = _schema({
          'id': const ArrowIntType(bitWidth: 64, signed: true),
          'date': const ArrowTimestampType(unit: ArrowTimeUnit.microsecond, timezone: 'UTC'),
        });
        await client1.datasets.createTableWithSchema(name: 'timestamp_table', schema: tsSchema);
        await client1.datasets.insert(
          table: 'timestamp_table',
          records: _batch(tsSchema, [
            {'id': 1, 'date': DateTime.parse('2025-05-21T18:32:56Z')},
          ]),
        );
        expect(await _searchRows(client1, table: 'timestamp_table', where: {'id': 1}), isNotEmpty);
      }, roomNamePrefix: 'dart-datasets');
    });

    test('restore_versions_and_branches', () async {
      await withTwoRoomServerE2eClients((client1, client2) async {
        final schema = _schema({'id': const ArrowIntType(bitWidth: 64, signed: true), 'name': const ArrowUtf8Type()});
        await client1.datasets.createTableWithSchema(name: 'restore_table', schema: schema);
        await client1.datasets.insert(
          table: 'restore_table',
          records: _batch(schema, [
            {'id': 1, 'name': 'first'},
          ]),
        );
        final restoreVersion = (await client1.datasets.listVersions('restore_table')).map((version) => version.version).reduce(math.max);
        await client1.datasets.insert(
          table: 'restore_table',
          records: _batch(schema, [
            {'id': 2, 'name': 'second'},
          ]),
        );
        expect(_ids(await _searchRows(client1, table: 'restore_table')), [1, 2]);
        expect(_ids(await _searchRows(client1, table: 'restore_table', version: restoreVersion)), [1]);
        await client1.datasets.restore(table: 'restore_table', version: restoreVersion);
        await client2.datasets.insert(
          table: 'restore_table',
          records: _batch(schema, [
            {'id': 3, 'name': 'after_restore'},
          ]),
        );
        expect(_ids(await _searchRows(client1, table: 'restore_table')), [1, 3]);

        await client1.datasets.createBranch(branch: 'exp');
        await client1.datasets.insert(
          table: 'restore_table',
          records: _batch(schema, [
            {'id': 4, 'name': 'main-only'},
          ]),
        );
        expect(_ids(await _searchRows(client1, table: 'restore_table', branch: 'exp')), [1, 3]);
        await client1.datasets.insert(
          table: 'restore_table',
          branch: 'exp',
          records: _batch(schema, [
            {'id': 5, 'name': 'exp-only'},
          ]),
        );
        expect(_ids(await _searchRows(client1, table: 'restore_table')), [1, 3, 4]);
        expect(_ids(await _searchRows(client1, table: 'restore_table', branch: 'exp')), [1, 3, 5]);

        await client1.datasets.createBranch(branch: 'branch_catalog');
        await client1.datasets.createTableWithSchema(
          name: 'branch_only',
          schema: _schema({'id': const ArrowIntType(bitWidth: 64, signed: true)}),
          branch: 'branch_catalog',
        );
        expect(await client1.datasets.listTables(), isNot(contains('branch_only')));
        expect(await client1.datasets.listTables(branch: 'branch_catalog'), contains('branch_only'));
        expect(await _searchRows(client1, table: 'branch_only', branch: 'branch_catalog'), isEmpty);
      }, roomNamePrefix: 'dart-datasets');
    });
  });
}
