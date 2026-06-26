import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:meshagent_dart_arrow/meshagent_dart_arrow.dart';

import 'agents_client.dart';
import 'datasets_client.dart';
import 'room_server_client.dart';

enum SqliteCreateMode { create, overwrite, createIfNotExists }

extension SqliteCreateModeValue on SqliteCreateMode {
  String get value {
    switch (this) {
      case SqliteCreateMode.create:
        return "create";
      case SqliteCreateMode.overwrite:
        return "overwrite";
      case SqliteCreateMode.createIfNotExists:
        return "create_if_not_exists";
    }
  }
}

class SqliteDatabaseDetails {
  const SqliteDatabaseDetails({required this.name, required this.namespace, required this.tables, required this.sizeBytes});

  final String name;
  final List<String>? namespace;
  final int tables;
  final int sizeBytes;

  static SqliteDatabaseDetails fromJson(Map<String, dynamic> json) {
    return SqliteDatabaseDetails(
      name: json["name"] as String,
      namespace: (json["namespace"] as List?)?.map((value) => value.toString()).toList(growable: false),
      tables: (json["tables"] as num).toInt(),
      sizeBytes: (json["size_bytes"] as num?)?.toInt() ?? 0,
    );
  }
}

sealed class SqliteSqlExecution {
  const SqliteSqlExecution();
}

class SqliteSqlQuery extends SqliteSqlExecution {
  const SqliteSqlQuery({required this.schema, required this.queryId});

  final ArrowSchema schema;
  final String queryId;
}

class SqliteSqlStatement extends SqliteSqlExecution {
  const SqliteSqlStatement({required this.rowsAffected});

  final int rowsAffected;
}

enum SqliteSqlCancelStatus { cancelled, cancelling, notCancellable }

class SqliteSqlCancelResult {
  const SqliteSqlCancelResult({required this.status});

  final SqliteSqlCancelStatus status;
}

typedef SqliteArrowBatches = Stream<ArrowRecordBatch>;

const _arrowIpcStreamMimeType = "application/vnd.apache.arrow.stream";

ArrowTable _tableFromBatches(List<ArrowRecordBatch> batches) {
  return ArrowTable(schema: batches.isEmpty ? const ArrowSchema([]) : batches.first.schema, batches: batches);
}

Object? _encodeSqliteValue(Object? value) {
  if (value is DatasetValueEncoder) {
    return value.encodeDatasetValue();
  }
  if (value is Uint8List) {
    return {"binary": base64Encode(value)};
  }
  if (value is DateTime) {
    final normalized = value.isUtc ? value : value.toUtc();
    return {"timestamp": normalized.toIso8601String().replaceFirst("+00:00", "Z")};
  }
  if (value is List) {
    return {"list": value.map(_encodeSqliteValue).toList(growable: false)};
  }
  if (value is Map) {
    throw RoomServerException("sqlite object values must use DatasetStruct or DatasetJson");
  }
  return value;
}

Object? _whereClause(Object? where) {
  if (where is Map) {
    return {for (final entry in where.entries) entry.key.toString(): _encodeSqliteValue(entry.value)};
  }
  if (where is String) {
    return where;
  }
  return null;
}

String _valueJson(Object? value) {
  return jsonEncode(_encodeSqliteValue(value));
}

class _SqliteArrowWriteInputStream {
  _SqliteArrowWriteInputStream({required this.start, required SqliteArrowBatches chunks, this.schema}) : _source = StreamQueue(chunks);

  final Map<String, dynamic> start;
  final ArrowSchema? schema;
  final StreamQueue<ArrowRecordBatch> _source;
  final _pulls = StreamController<void>();
  bool _closed = false;

  Stream<Content> inputStream() async* {
    yield BinaryContent(data: schema == null ? Uint8List(0) : ArrowIpcSchema.fromSchema(schema!).bytes, headers: start);
    await for (final _ in _pulls.stream) {
      if (_closed) {
        return;
      }
      if (!await _source.hasNext) {
        return;
      }
      final nextChunk = await _source.next;
      if (nextChunk.ipcBytes.isEmpty) {
        continue;
      }
      yield BinaryContent(data: nextChunk.ipcBytes, headers: const {"kind": "data", "content_type": _arrowIpcStreamMimeType});
    }
  }

  void requestNext() {
    if (_closed) {
      return;
    }
    _pulls.add(null);
  }

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    unawaited(_pulls.close());
    unawaited(_source.cancel());
  }
}

class _SqliteArrowReadInputStream {
  _SqliteArrowReadInputStream({required this.start});

  final Map<String, dynamic> start;
  final _pulls = StreamController<void>();
  bool _closed = false;

  Stream<Content> inputStream() async* {
    yield BinaryContent(data: Uint8List(0), headers: start);
    await for (final _ in _pulls.stream) {
      if (_closed) {
        return;
      }
      yield BinaryContent(data: Uint8List(0), headers: const {"kind": "pull"});
    }
  }

  void requestNext() {
    if (_closed) {
      return;
    }
    _pulls.add(null);
  }

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    unawaited(_pulls.close());
  }
}

class SqliteDatabaseClient {
  SqliteDatabaseClient({required this.client, required this.database, this.namespace});

  final SqliteClient client;
  final String database;
  final List<String>? namespace;

  Future<void> createDatabase({SqliteCreateMode mode = SqliteCreateMode.create}) {
    return client.createDatabase(name: database, namespace: namespace, mode: mode);
  }

  Future<void> dropDatabase({bool ignoreMissing = false}) {
    return client.dropDatabase(name: database, namespace: namespace, ignoreMissing: ignoreMissing);
  }

  Future<SqliteDatabaseDetails> inspectDatabase() {
    return client.inspectDatabase(name: database, namespace: namespace);
  }

  Future<List<String>> listTables() => client.listTables(database: database, namespace: namespace);

  Future<void> createTableWithSchema({
    required String name,
    required ArrowSchema schema,
    SqliteArrowBatches? batches,
    SqliteCreateMode mode = SqliteCreateMode.create,
  }) {
    return client.createTableWithSchema(database: database, name: name, schema: schema, batches: batches, mode: mode, namespace: namespace);
  }

  Future<void> createTableFromArrowTable({
    required String name,
    required ArrowTable table,
    SqliteCreateMode mode = SqliteCreateMode.create,
  }) {
    return client.createTableFromArrowTable(database: database, name: name, table: table, mode: mode, namespace: namespace);
  }

  Future<void> createTableFromArrowBatches({
    required String name,
    required SqliteArrowBatches batches,
    SqliteCreateMode mode = SqliteCreateMode.create,
  }) {
    return client.createTableFromArrowBatches(database: database, name: name, batches: batches, mode: mode, namespace: namespace);
  }

  Future<void> dropTable({required String name, bool ignoreMissing = false}) {
    return client.dropTable(database: database, name: name, ignoreMissing: ignoreMissing, namespace: namespace);
  }

  Future<void> renameTable({required String name, required String newName}) {
    return client.renameTable(database: database, name: name, newName: newName, namespace: namespace);
  }

  Future<ArrowSchema> inspect(String table) => client.inspect(database: database, table: table, namespace: namespace);

  Future<void> addColumnsWithSchema({required String table, required ArrowSchema schema}) {
    return client.addColumnsWithSchema(database: database, table: table, schema: schema, namespace: namespace);
  }

  Future<void> dropColumns({required String table, required List<String> columns}) {
    return client.dropColumns(database: database, table: table, columns: columns, namespace: namespace);
  }

  Future<void> insert({required String table, required ArrowRecordBatch records}) {
    return client.insert(database: database, table: table, records: records, namespace: namespace);
  }

  Future<void> insertTable({required String table, required ArrowTable records}) {
    return client.insertTable(database: database, table: table, records: records, namespace: namespace);
  }

  Future<void> insertStream({required String table, required SqliteArrowBatches chunks}) {
    return client.insertStream(database: database, table: table, chunks: chunks, namespace: namespace);
  }

  Future<int> update({required String table, required String where, required DatasetRecord values, Object? params}) {
    return client.update(database: database, table: table, where: where, values: values, params: params, namespace: namespace);
  }

  Future<int> delete({required String table, required String where, Object? params}) {
    return client.delete(database: database, table: table, where: where, params: params, namespace: namespace);
  }

  Future<List<ArrowRecordBatch>> search({
    required String table,
    Object? where,
    Object? params,
    int? offset,
    int? limit,
    List<String>? select,
  }) {
    return client.search(
      database: database,
      table: table,
      where: where,
      params: params,
      offset: offset,
      limit: limit,
      select: select,
      namespace: namespace,
    );
  }

  Future<ArrowTable> searchTable({required String table, Object? where, Object? params, int? offset, int? limit, List<String>? select}) {
    return client.searchTable(
      database: database,
      table: table,
      where: where,
      params: params,
      offset: offset,
      limit: limit,
      select: select,
      namespace: namespace,
    );
  }

  SqliteArrowBatches searchStream({required String table, Object? where, Object? params, int? offset, int? limit, List<String>? select}) {
    return client.searchStream(
      database: database,
      table: table,
      where: where,
      params: params,
      offset: offset,
      limit: limit,
      select: select,
      namespace: namespace,
    );
  }

  Future<int> count({required String table, Object? where, Object? params}) {
    return client.count(database: database, table: table, where: where, params: params, namespace: namespace);
  }

  Future<List<ArrowRecordBatch>> sql({required String query, Object? params}) {
    return client.sql(database: database, query: query, params: params, namespace: namespace);
  }

  Future<ArrowTable> sqlTable({required String query, Object? params}) {
    return client.sqlTable(database: database, query: query, params: params, namespace: namespace);
  }

  SqliteArrowBatches sqlStream({required String query, Object? params}) {
    return client.sqlStream(database: database, query: query, params: params, namespace: namespace);
  }

  Future<SqliteSqlExecution> executeSql({required String query, Object? params}) {
    return client.executeSql(database: database, query: query, params: params, namespace: namespace);
  }

  Future<int> executeSqlStatement({required String query, Object? params}) {
    return client.executeSqlStatement(database: database, query: query, params: params, namespace: namespace);
  }
}

class SqliteClient {
  SqliteClient({required this.room});

  final RoomClient room;

  RoomServerException _unexpectedResponseError(String operation) {
    return RoomServerException("unexpected return type from sqlite.$operation call");
  }

  SqliteDatabaseClient database(String name, {List<String>? namespace}) {
    return SqliteDatabaseClient(client: this, database: name, namespace: namespace);
  }

  Future<Content> _invoke(String operation, Map<String, dynamic> input) async {
    final output = await room.invoke(
      toolkit: "sqlite",
      tool: operation,
      input: ToolContentInput(JsonContent(json: input)),
    );
    if (output is ToolContentOutput) {
      if (output.content is ErrorContent) {
        final error = output.content as ErrorContent;
        throw RoomServerException(error.text, code: error.code);
      }
      return output.content;
    }
    throw _unexpectedResponseError(operation);
  }

  Future<Content> _invokeContent(String operation, Content input) async {
    final output = await room.invoke(toolkit: "sqlite", tool: operation, input: ToolContentInput(input));
    if (output is ToolContentOutput) {
      if (output.content is ErrorContent) {
        final error = output.content as ErrorContent;
        throw RoomServerException(error.text, code: error.code);
      }
      return output.content;
    }
    throw _unexpectedResponseError(operation);
  }

  Future<ToolStreamOutput> _invokeStream(String operation, Stream<Content> input) async {
    final output = await room.invoke(toolkit: "sqlite", tool: operation, input: ToolStreamInput(input));
    if (output is! ToolStreamOutput) {
      throw _unexpectedResponseError(operation);
    }
    return output;
  }

  Future<void> _drainArrowWriteStream(String operation, _SqliteArrowWriteInputStream input) async {
    final output = await _invokeStream(operation, input.inputStream());
    try {
      await for (final chunk in output.stream) {
        if (chunk is ErrorContent) {
          throw RoomServerException(chunk.text, code: chunk.code);
        }
        if (chunk is ControlContent) {
          if (chunk.method == "close") {
            return;
          }
          throw _unexpectedResponseError(operation);
        }
        if (chunk is! BinaryContent || chunk.headers["kind"] != "pull") {
          throw _unexpectedResponseError(operation);
        }
        input.requestNext();
      }
    } finally {
      input.close();
      await output.inputClosed;
    }
  }

  SqliteArrowBatches _streamArrow(String operation, Map<String, dynamic> start) async* {
    final input = _SqliteArrowReadInputStream(start: start);
    final output = await _invokeStream(operation, input.inputStream());
    input.requestNext();
    try {
      await for (final chunk in output.stream) {
        if (chunk is ErrorContent) {
          throw RoomServerException(chunk.text, code: chunk.code);
        }
        if (chunk is ControlContent) {
          if (chunk.method == "close") {
            return;
          }
          throw _unexpectedResponseError(operation);
        }
        if (chunk is! BinaryContent || chunk.headers["kind"] != "data") {
          throw _unexpectedResponseError(operation);
        }
        yield ArrowRecordBatch(chunk.data);
        input.requestNext();
      }
    } finally {
      input.close();
      await output.inputClosed;
    }
  }

  Future<List<String>> listDatabases({List<String>? namespace}) async {
    final response = await _invoke("list_databases", {"namespace": namespace});
    if (response is! JsonContent) {
      throw _unexpectedResponseError("list_databases");
    }
    final databases = response.json["databases"] as List<dynamic>? ?? [];
    return databases.map((value) => value.toString()).toList(growable: false);
  }

  Future<void> createDatabase({required String name, List<String>? namespace, SqliteCreateMode mode = SqliteCreateMode.create}) async {
    final response = await _invoke("create_database", {"name": name, "namespace": namespace, "mode": mode.value});
    if (response is! EmptyContent) {
      throw _unexpectedResponseError("create_database");
    }
  }

  Future<void> dropDatabase({required String name, List<String>? namespace, bool ignoreMissing = false}) async {
    final response = await _invoke("drop_database", {"name": name, "namespace": namespace, "ignore_missing": ignoreMissing});
    if (response is! EmptyContent) {
      throw _unexpectedResponseError("drop_database");
    }
  }

  Future<SqliteDatabaseDetails> inspectDatabase({required String name, List<String>? namespace}) async {
    final response = await _invoke("inspect_database", {"name": name, "namespace": namespace});
    if (response is! JsonContent) {
      throw _unexpectedResponseError("inspect_database");
    }
    return SqliteDatabaseDetails.fromJson(response.json);
  }

  Future<List<String>> listTables({required String database, List<String>? namespace}) async {
    final response = await _invoke("list_tables", {"database": database, "namespace": namespace});
    if (response is! JsonContent) {
      throw _unexpectedResponseError("list_tables");
    }
    final tables = response.json["tables"] as List<dynamic>? ?? [];
    return tables.map((value) => value.toString()).toList(growable: false);
  }

  Future<void> createTableWithSchema({
    required String database,
    required String name,
    required ArrowSchema schema,
    SqliteArrowBatches? batches,
    SqliteCreateMode mode = SqliteCreateMode.create,
    List<String>? namespace,
  }) async {
    final input = _SqliteArrowWriteInputStream(
      start: {"kind": "start", "database": database, "name": name, "mode": mode.value, "namespace": namespace},
      chunks: batches ?? const Stream<ArrowRecordBatch>.empty(),
      schema: schema,
    );
    await _drainArrowWriteStream("create_table", input);
  }

  Future<void> createTableFromArrowBatches({
    required String database,
    required String name,
    required SqliteArrowBatches batches,
    SqliteCreateMode mode = SqliteCreateMode.create,
    List<String>? namespace,
  }) async {
    final input = _SqliteArrowWriteInputStream(
      start: {"kind": "start", "database": database, "name": name, "mode": mode.value, "namespace": namespace},
      chunks: batches,
    );
    await _drainArrowWriteStream("create_table", input);
  }

  Future<void> createTableFromArrowTable({
    required String database,
    required String name,
    required ArrowTable table,
    SqliteCreateMode mode = SqliteCreateMode.create,
    List<String>? namespace,
  }) {
    return createTableWithSchema(
      database: database,
      name: name,
      schema: table.schema,
      batches: Stream.fromIterable(table.batches),
      mode: mode,
      namespace: namespace,
    );
  }

  Future<void> dropTable({required String database, required String name, bool ignoreMissing = false, List<String>? namespace}) async {
    final response = await _invoke("drop_table", {
      "database": database,
      "name": name,
      "ignore_missing": ignoreMissing,
      "namespace": namespace,
    });
    if (response is! EmptyContent) {
      throw _unexpectedResponseError("drop_table");
    }
  }

  Future<void> renameTable({required String database, required String name, required String newName, List<String>? namespace}) async {
    final response = await _invoke("rename_table", {"database": database, "name": name, "new_name": newName, "namespace": namespace});
    if (response is! EmptyContent) {
      throw _unexpectedResponseError("rename_table");
    }
  }

  Future<ArrowSchema> inspect({required String database, required String table, List<String>? namespace}) async {
    final response = await _invoke("inspect", {"database": database, "table": table, "namespace": namespace});
    if (response is! BinaryContent) {
      throw _unexpectedResponseError("inspect");
    }
    return ArrowIpcSchema(response.data).schema;
  }

  Future<void> addColumnsWithSchema({
    required String database,
    required String table,
    required ArrowSchema schema,
    List<String>? namespace,
  }) async {
    final response = await _invokeContent(
      "add_columns",
      BinaryContent(
        data: ArrowIpcSchema.fromSchema(schema).bytes,
        headers: {"database": database, "table": table, "namespace": namespace, "content_type": _arrowIpcStreamMimeType},
      ),
    );
    if (response is! EmptyContent) {
      throw _unexpectedResponseError("add_columns");
    }
  }

  Future<void> dropColumns({
    required String database,
    required String table,
    required List<String> columns,
    List<String>? namespace,
  }) async {
    final response = await _invoke("drop_columns", {"database": database, "table": table, "columns": columns, "namespace": namespace});
    if (response is! EmptyContent) {
      throw _unexpectedResponseError("drop_columns");
    }
  }

  Future<void> insert({required String database, required String table, required ArrowRecordBatch records, List<String>? namespace}) {
    return insertStream(database: database, table: table, chunks: Stream.fromIterable([records]), namespace: namespace);
  }

  Future<void> insertTable({required String database, required String table, required ArrowTable records, List<String>? namespace}) {
    return insertStream(database: database, table: table, chunks: Stream.fromIterable(records.batches), namespace: namespace);
  }

  Future<void> insertStream({
    required String database,
    required String table,
    required SqliteArrowBatches chunks,
    List<String>? namespace,
  }) async {
    final input = _SqliteArrowWriteInputStream(
      start: {"kind": "start", "database": database, "table": table, "namespace": namespace},
      chunks: chunks,
    );
    await _drainArrowWriteStream("insert", input);
  }

  Future<int> update({
    required String database,
    required String table,
    required String where,
    required DatasetRecord values,
    Object? params,
    List<String>? namespace,
  }) async {
    final response = await _invoke("update", {
      "database": database,
      "table": table,
      "where": where,
      "values": values.entries.map((entry) => {"column": entry.key, "value_json": _valueJson(entry.value)}).toList(growable: false),
      "params": params,
      "namespace": namespace,
    });
    if (response is! JsonContent || response.json["rows_affected"] is! num) {
      throw _unexpectedResponseError("update");
    }
    return (response.json["rows_affected"] as num).toInt();
  }

  Future<int> delete({
    required String database,
    required String table,
    required String where,
    Object? params,
    List<String>? namespace,
  }) async {
    final response = await _invoke("delete", {
      "database": database,
      "table": table,
      "where": where,
      "params": params,
      "namespace": namespace,
    });
    if (response is! JsonContent || response.json["rows_affected"] is! num) {
      throw _unexpectedResponseError("delete");
    }
    return (response.json["rows_affected"] as num).toInt();
  }

  Future<List<ArrowRecordBatch>> search({
    required String database,
    required String table,
    Object? where,
    Object? params,
    int? offset,
    int? limit,
    List<String>? select,
    List<String>? namespace,
  }) async {
    final rows = <ArrowRecordBatch>[];
    await for (final chunk in searchStream(
      database: database,
      table: table,
      where: where,
      params: params,
      offset: offset,
      limit: limit,
      select: select,
      namespace: namespace,
    )) {
      rows.add(chunk);
    }
    return rows;
  }

  Future<ArrowTable> searchTable({
    required String database,
    required String table,
    Object? where,
    Object? params,
    int? offset,
    int? limit,
    List<String>? select,
    List<String>? namespace,
  }) async {
    return _tableFromBatches(
      await search(
        database: database,
        table: table,
        where: where,
        params: params,
        offset: offset,
        limit: limit,
        select: select,
        namespace: namespace,
      ),
    );
  }

  SqliteArrowBatches searchStream({
    required String database,
    required String table,
    Object? where,
    Object? params,
    int? offset,
    int? limit,
    List<String>? select,
    List<String>? namespace,
  }) {
    return _streamArrow("search", {
      "kind": "start",
      "database": database,
      "table": table,
      "where": _whereClause(where),
      "params": params,
      "offset": offset,
      "limit": limit,
      "select": select,
      "namespace": namespace,
    });
  }

  Future<int> count({required String database, required String table, Object? where, Object? params, List<String>? namespace}) async {
    final response = await _invoke("count", {
      "database": database,
      "table": table,
      "where": _whereClause(where),
      "params": params,
      "namespace": namespace,
    });
    if (response is! JsonContent || response.json["count"] is! num) {
      throw _unexpectedResponseError("count");
    }
    return (response.json["count"] as num).toInt();
  }

  Future<List<ArrowRecordBatch>> sql({required String database, required String query, Object? params, List<String>? namespace}) async {
    final rows = <ArrowRecordBatch>[];
    await for (final chunk in sqlStream(database: database, query: query, params: params, namespace: namespace)) {
      rows.add(chunk);
    }
    return rows;
  }

  Future<ArrowTable> sqlTable({required String database, required String query, Object? params, List<String>? namespace}) async {
    return _tableFromBatches(await sql(database: database, query: query, params: params, namespace: namespace));
  }

  Future<SqliteSqlQuery> openSqlQuery({required String database, required String query, Object? params, List<String>? namespace}) async {
    final response = await _invokeContent(
      "open_sql_query",
      BinaryContent(data: Uint8List(0), headers: {"database": database, "query": query, "params": params, "namespace": namespace}),
    );
    if (response is! BinaryContent) {
      throw _unexpectedResponseError("open_sql_query");
    }
    final queryId = response.headers["query_id"];
    if (queryId is! String || queryId.isEmpty) {
      throw _unexpectedResponseError("open_sql_query");
    }
    return SqliteSqlQuery(schema: ArrowIpcSchema(response.data).schema, queryId: queryId);
  }

  Future<SqliteSqlExecution> executeSql({required String database, required String query, Object? params, List<String>? namespace}) async {
    final response = await _invokeContent(
      "execute_sql",
      BinaryContent(data: Uint8List(0), headers: {"database": database, "query": query, "params": params, "namespace": namespace}),
    );
    if (response is BinaryContent) {
      if (response.headers["kind"] != "query") {
        throw _unexpectedResponseError("execute_sql");
      }
      final queryId = response.headers["query_id"];
      if (queryId is! String || queryId.isEmpty) {
        throw _unexpectedResponseError("execute_sql");
      }
      return SqliteSqlQuery(schema: ArrowIpcSchema(response.data).schema, queryId: queryId);
    }
    if (response is JsonContent) {
      if (response.json["kind"] != "statement" || response.json["rows_affected"] is! num) {
        throw _unexpectedResponseError("execute_sql");
      }
      return SqliteSqlStatement(rowsAffected: (response.json["rows_affected"] as num).toInt());
    }
    throw _unexpectedResponseError("execute_sql");
  }

  SqliteArrowBatches sqlStream({required String database, required String query, Object? params, List<String>? namespace}) {
    return (() async* {
      final result = await executeSql(database: database, query: query, params: params, namespace: namespace);
      if (result is SqliteSqlStatement) {
        throw RoomServerException("SQL statement did not return rows; rows_affected=${result.rowsAffected}");
      }
      final opened = result as SqliteSqlQuery;
      try {
        yield* readSqlQuery(queryId: opened.queryId);
      } finally {
        await closeSqlQuery(queryId: opened.queryId);
      }
    })();
  }

  SqliteArrowBatches readSqlQuery({required String queryId}) {
    return _streamArrow("read_sql_query", {"kind": "start", "query_id": queryId});
  }

  Future<void> closeSqlQuery({required String queryId}) async {
    final response = await _invoke("close_sql_query", {"query_id": queryId});
    if (response is! EmptyContent) {
      throw _unexpectedResponseError("close_sql_query");
    }
  }

  Future<SqliteSqlCancelResult> cancelSqlQuery({required String queryId}) async {
    final response = await _invoke("cancel_sql_query", {"query_id": queryId});
    if (response is! JsonContent) {
      throw _unexpectedResponseError("cancel_sql_query");
    }
    final status = response.json["status"];
    return SqliteSqlCancelResult(
      status: switch (status) {
        "cancelled" => SqliteSqlCancelStatus.cancelled,
        "cancelling" => SqliteSqlCancelStatus.cancelling,
        "not_cancellable" => SqliteSqlCancelStatus.notCancellable,
        _ => throw _unexpectedResponseError("cancel_sql_query"),
      },
    );
  }

  Future<int> executeSqlStatement({required String database, required String query, Object? params, List<String>? namespace}) async {
    final response = await _invokeContent(
      "execute_sql_statement",
      BinaryContent(data: Uint8List(0), headers: {"database": database, "query": query, "params": params, "namespace": namespace}),
    );
    if (response is! JsonContent || response.json["rows_affected"] is! num) {
      throw _unexpectedResponseError("execute_sql_statement");
    }
    return (response.json["rows_affected"] as num).toInt();
  }
}
