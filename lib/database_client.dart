import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:async/async.dart';

import 'agents_client.dart';
import 'data_types.dart';
import 'room_server_client.dart';

enum CreateMode { create, overwrite, createIfNotExists }

extension CreateModeValue on CreateMode {
  String get value {
    switch (this) {
      case CreateMode.create:
        return "create";
      case CreateMode.overwrite:
        return "overwrite";
      case CreateMode.createIfNotExists:
        return "create_if_not_exists";
    }
  }
}

class TableRef {
  TableRef({required this.name, this.namespace, this.alias, this.branch, this.version});

  final String name;
  final List<String>? namespace;
  final String? alias;
  final String? branch;
  final int? version;

  Map<String, dynamic> toJson() {
    return {"name": name, "namespace": namespace, "alias": alias, "branch": branch, "version": version};
  }
}

class TableBranch {
  const TableBranch({
    required this.name,
    required this.parentBranch,
    required this.parentVersion,
    required this.createdAt,
    required this.manifestSize,
  });

  final String name;
  final String? parentBranch;
  final int? parentVersion;
  final DateTime? createdAt;
  final int? manifestSize;

  static TableBranch fromJson(Map<String, dynamic> json) {
    return TableBranch(
      name: json["name"] as String,
      parentBranch: json["parent_branch"] as String?,
      parentVersion: (json["parent_version"] as num?)?.toInt(),
      createdAt: json["created_at"] == null ? null : DateTime.parse(json["created_at"] as String),
      manifestSize: (json["manifest_size"] as num?)?.toInt(),
    );
  }
}

List<Map<String, dynamic>>? _metadataEntries(Map<String, dynamic>? metadata) {
  if (metadata == null) {
    return null;
  }
  return metadata.entries
      .map((entry) => {"key": entry.key, "value": entry.value is String ? entry.value : jsonEncode(_encodeRecordValue(entry.value))})
      .toList(growable: false);
}

Map<String, dynamic> _toolkitDataTypeJson(DataType dataType) {
  final payload = <String, dynamic>{
    "type": dataType.toJson()["type"],
    "nullable": dataType.nullable,
    "metadata": _metadataEntries(dataType.metadata),
  };

  if (dataType is VectorDataType) {
    payload["size"] = dataType.size;
    payload["element_type"] = _toolkitDataTypeJson(dataType.elementType);
  } else if (dataType is ListDataType) {
    payload["element_type"] = _toolkitDataTypeJson(dataType.elementType);
  } else if (dataType is StructDataType) {
    payload["fields"] = dataType.fields.entries
        .map((entry) => {"name": entry.key, "data_type": _toolkitDataTypeJson(entry.value)})
        .toList(growable: false);
  }

  return payload;
}

Map<String, dynamic> _publicDataTypeJson(dynamic value) {
  if (value is! Map) {
    throw RoomServerException("unexpected return type from database.inspect call");
  }

  final type = value["type"];
  if (type is! String) {
    throw RoomServerException("unexpected return type from database.inspect call");
  }

  final metadata = value["metadata"];
  Map<String, dynamic>? decodedMetadata;
  if (metadata != null) {
    if (metadata is! List) {
      throw RoomServerException("unexpected return type from database.inspect call");
    }
    decodedMetadata = <String, dynamic>{};
    for (final entry in metadata) {
      if (entry is! Map || entry["key"] is! String || entry["value"] is! String) {
        throw RoomServerException("unexpected return type from database.inspect call");
      }
      decodedMetadata[entry["key"] as String] = entry["value"];
    }
  }

  final payload = <String, dynamic>{"type": type, "nullable": value["nullable"], "metadata": decodedMetadata};

  if (type == "vector") {
    payload["size"] = value["size"];
    payload["element_type"] = _publicDataTypeJson(value["element_type"]);
  } else if (type == "list") {
    payload["element_type"] = _publicDataTypeJson(value["element_type"]);
  } else if (type == "struct") {
    final rawFields = value["fields"];
    if (rawFields is! List) {
      throw RoomServerException("unexpected return type from database.inspect call");
    }
    payload["fields"] = {
      for (final rawField in rawFields)
        if (rawField is Map && rawField["name"] is String) rawField["name"] as String: _publicDataTypeJson(rawField["data_type"]),
    };
    if ((payload["fields"] as Map).length != rawFields.length) {
      throw RoomServerException("unexpected return type from database.inspect call");
    }
  }

  return payload;
}

List<Map<String, dynamic>> _schemaEntries(Map<String, DataType>? schema) {
  if (schema == null) {
    return <Map<String, dynamic>>[];
  }
  return schema.entries.map((entry) => {"name": entry.key, "data_type": _toolkitDataTypeJson(entry.value)}).toList(growable: false);
}

String _valueJson(dynamic value) {
  return jsonEncode(_encodeRecordValue(value));
}

Map<String, dynamic> _streamEncodeValue(dynamic value) {
  if (value == null) {
    return {"type": "null"};
  }
  if (value is bool) {
    return {"type": "bool", "value": value};
  }
  if (value is int) {
    return {"type": "int", "value": value};
  }
  if (value is double) {
    return {"type": "float", "value": value};
  }
  if (value is num) {
    return {"type": "float", "value": value.toDouble()};
  }
  if (value is String) {
    return {"type": "text", "value": value};
  }
  if (value is Uint8List) {
    return {"type": "binary", "data": base64Encode(value)};
  }
  if (value is DateTime) {
    final normalized = value.isUtc ? value : value.toUtc();
    return {"type": "timestamp", "value": normalized.toIso8601String().replaceFirst("+00:00", "Z")};
  }
  if (value is List) {
    return {"type": "list", "items": value.map((item) => _streamEncodeValue(item)).toList(growable: false)};
  }
  if (value is Map) {
    return {
      "type": "struct",
      "fields": value.entries
          .map((entry) => {"name": entry.key.toString(), "value": _streamEncodeValue(entry.value)})
          .toList(growable: false),
    };
  }
  throw RoomServerException("database stream does not support value type ${value.runtimeType}");
}

dynamic _streamDecodeValue(dynamic value, String operation) {
  if (value is! Map) {
    throw RoomServerException("unexpected return type from database.$operation call");
  }
  final type = value["type"];
  if (type is! String) {
    throw RoomServerException("unexpected return type from database.$operation call");
  }
  switch (type) {
    case "null":
      return null;
    case "bool":
      final decoded = value["value"];
      if (decoded is! bool) {
        throw RoomServerException("unexpected return type from database.$operation call");
      }
      return decoded;
    case "int":
      final decoded = value["value"];
      if (decoded is! num) {
        throw RoomServerException("unexpected return type from database.$operation call");
      }
      return decoded.toInt();
    case "float":
      final decoded = value["value"];
      if (decoded is! num) {
        throw RoomServerException("unexpected return type from database.$operation call");
      }
      return decoded.toDouble();
    case "text":
    case "date":
    case "timestamp":
      final decoded = value["value"];
      if (decoded is! String) {
        throw RoomServerException("unexpected return type from database.$operation call");
      }
      return decoded;
    case "binary":
      final data = value["data"];
      if (data is! String) {
        throw RoomServerException("unexpected return type from database.$operation call");
      }
      return base64Decode(data);
    case "list":
      final items = value["items"];
      if (items is! List) {
        throw RoomServerException("unexpected return type from database.$operation call");
      }
      return items.map((item) => _streamDecodeValue(item, operation)).toList(growable: false);
    case "struct":
      final fields = value["fields"];
      if (fields is! List) {
        throw RoomServerException("unexpected return type from database.$operation call");
      }
      return {
        for (final field in fields)
          if (field is Map && field["name"] is String) field["name"] as String: _streamDecodeValue(field["value"], operation),
      };
  }
  throw RoomServerException("unexpected return type from database.$operation call");
}

Map<String, dynamic> _rowsChunk(List<Map<String, dynamic>> rows) {
  return {
    "kind": "rows",
    "rows": rows
        .map(
          (row) => {
            "columns": row.entries.map((entry) => {"name": entry.key, "value": _streamEncodeValue(entry.value)}).toList(growable: false),
          },
        )
        .toList(growable: false),
  };
}

List<Map<String, dynamic>> _recordsFromRowsChunk(Map<String, dynamic> json, String operation) {
  if (json["kind"] != "rows") {
    throw RoomServerException("unexpected return type from database.$operation call");
  }
  final rows = json["rows"];
  if (rows is! List) {
    throw RoomServerException("unexpected return type from database.$operation call");
  }

  return rows
      .map((rawRow) {
        if (rawRow is! Map) {
          throw RoomServerException("unexpected return type from database.$operation call");
        }
        final columns = rawRow["columns"];
        if (columns is! List) {
          throw RoomServerException("unexpected return type from database.$operation call");
        }
        return {
          for (final rawColumn in columns)
            if (rawColumn is Map && rawColumn["name"] is String)
              rawColumn["name"] as String: _streamDecodeValue(rawColumn["value"], operation),
        };
      })
      .toList(growable: false);
}

List<List<Map<String, dynamic>>> _rowChunks(List<Map<String, dynamic>> rows, {int rowsPerChunk = 128}) {
  if (rowsPerChunk <= 0) {
    throw RoomServerException("rowsPerChunk must be greater than zero");
  }
  final chunks = <List<Map<String, dynamic>>>[];
  for (var index = 0; index < rows.length; index += rowsPerChunk) {
    final end = index + rowsPerChunk > rows.length ? rows.length : index + rowsPerChunk;
    chunks.add(rows.sublist(index, end));
  }
  return chunks;
}

String? _whereClause(dynamic where) {
  if (where is Map) {
    final parts = <String>[];
    where.forEach((key, value) {
      parts.add("${key.toString()} = ${jsonEncode(_encodeRecordValue(value))}");
    });
    return parts.join(" AND ");
  }
  if (where is String) {
    return where;
  }
  return null;
}

class _DatabaseWriteInputStream {
  _DatabaseWriteInputStream({required this.start, required Stream<List<Map<String, dynamic>>> chunks}) : _source = StreamQueue(chunks);

  final Map<String, dynamic> start;
  final StreamQueue<List<Map<String, dynamic>>> _source;
  final _pulls = StreamController<void>();
  bool _closed = false;

  Stream<Content> inputStream() async* {
    yield JsonContent(json: start);
    await for (final _ in _pulls.stream) {
      if (_closed) {
        return;
      }
      if (!await _source.hasNext) {
        return;
      }
      final nextChunk = await _source.next;
      if (nextChunk.isEmpty) {
        continue;
      }
      yield JsonContent(json: _rowsChunk(nextChunk));
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

class _DatabaseReadInputStream {
  _DatabaseReadInputStream({required this.start});

  final Map<String, dynamic> start;
  final _pulls = StreamController<void>();
  bool _closed = false;

  Stream<Content> inputStream() async* {
    yield JsonContent(json: start);
    await for (final _ in _pulls.stream) {
      if (_closed) {
        return;
      }
      yield JsonContent(json: const {"kind": "pull"});
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

class DatabaseClient {
  final RoomClient room;

  DatabaseClient({required this.room});

  Future<Content> _invoke(String operation, Map<String, dynamic> input) async {
    final output = await room.invoke(
      toolkit: "database",
      tool: operation,
      input: ToolContentInput(JsonContent(json: input)),
    );
    if (output is ToolContentOutput) {
      return output.content;
    }
    throw RoomServerException("unexpected return type from database.$operation call");
  }

  Future<Stream<Content>> _invokeStream(String operation, Stream<Content> input) async {
    final output = await room.invoke(toolkit: "database", tool: operation, input: ToolStreamInput(input));
    if (output is! ToolStreamOutput) {
      throw RoomServerException("unexpected return type from database.$operation call");
    }
    return output.stream;
  }

  Future<void> _drainWriteStream(String operation, _DatabaseWriteInputStream input) async {
    final output = await _invokeStream(operation, input.inputStream());
    try {
      await for (final chunk in output) {
        if (chunk is ErrorContent) {
          throw RoomServerException(chunk.text, code: chunk.code);
        }
        if (chunk is ControlContent) {
          if (chunk.method == "close") {
            return;
          }
          throw RoomServerException("unexpected return type from database.$operation call");
        }
        if (chunk is! JsonContent || chunk.json["kind"] != "pull") {
          throw RoomServerException("unexpected return type from database.$operation call");
        }
        input.requestNext();
      }
    } finally {
      input.close();
    }
  }

  Stream<List<Map<String, dynamic>>> _streamRows(String operation, Map<String, dynamic> start) async* {
    final input = _DatabaseReadInputStream(start: start);
    final output = await _invokeStream(operation, input.inputStream());
    input.requestNext();
    try {
      await for (final chunk in output) {
        if (chunk is ErrorContent) {
          throw RoomServerException(chunk.text, code: chunk.code);
        }
        if (chunk is ControlContent) {
          if (chunk.method == "close") {
            return;
          }
          throw RoomServerException("unexpected return type from database.$operation call");
        }
        if (chunk is! JsonContent) {
          throw RoomServerException("unexpected return type from database.$operation call");
        }
        yield _recordsFromRowsChunk(chunk.json, operation);
        input.requestNext();
      }
    } finally {
      input.close();
    }
  }

  Future<List<String>> listTables({List<String>? namespace, String? branch}) async {
    final response = await _invoke("list_tables", {"namespace": namespace, "branch": branch});
    if (response is! JsonContent) {
      throw RoomServerException("unexpected return type from database.list_tables call");
    }

    final tables = response.json["tables"] as List<dynamic>? ?? [];
    return tables.map((e) => e.toString()).toList(growable: false);
  }

  Future<void> _createTable({
    required String name,
    Stream<List<Map<String, dynamic>>>? data,
    Map<String, DataType>? schema,
    CreateMode mode = CreateMode.create,
    List<String>? namespace,
    String? branch,
    Map<String, dynamic>? metadata,
  }) async {
    final input = _DatabaseWriteInputStream(
      start: {
        "kind": "start",
        "name": name,
        "fields": schema == null ? null : _schemaEntries(schema),
        "mode": mode.value,
        "namespace": namespace,
        "branch": branch,
        "metadata": _metadataEntries(metadata),
      },
      chunks: data ?? Stream<List<Map<String, dynamic>>>.empty(),
    );
    await _drainWriteStream("create_table", input);
  }

  Future<void> createTableWithSchema({
    required String name,
    required Map<String, DataType> schema,
    CreateMode mode = CreateMode.create,
    List<String>? namespace,
    String? branch,
    Map<String, dynamic>? metadata,
  }) {
    return _createTable(name: name, schema: schema, mode: mode, namespace: namespace, branch: branch, metadata: metadata);
  }

  Future<void> createTableFromData({
    required String name,
    required List<Map<String, dynamic>> data,
    CreateMode mode = CreateMode.create,
    List<String>? namespace,
    String? branch,
    Map<String, dynamic>? metadata,
  }) {
    return _createTable(
      name: name,
      data: Stream.fromIterable(_rowChunks(data)),
      mode: mode,
      namespace: namespace,
      branch: branch,
      metadata: metadata,
    );
  }

  Future<void> createTableFromDataStream({
    required String name,
    required Stream<List<Map<String, dynamic>>> chunks,
    Map<String, DataType>? schema,
    CreateMode mode = CreateMode.create,
    List<String>? namespace,
    String? branch,
    Map<String, dynamic>? metadata,
  }) {
    return _createTable(name: name, data: chunks, schema: schema, mode: mode, namespace: namespace, branch: branch, metadata: metadata);
  }

  Future<void> dropTable({required String name, bool ignoreMissing = false, List<String>? namespace, String? branch}) async {
    await _invoke("drop_table", {"name": name, "ignore_missing": ignoreMissing, "namespace": namespace, "branch": branch});
  }

  Future<void> addColumnWithExpression({
    required String table,
    required Map<String, String> newColumns,
    List<String>? namespace,
    String? branch,
  }) async {
    await _invoke("add_columns", {
      "table": table,
      "columns": newColumns.entries
          .map((entry) => {"name": entry.key, "value_sql": entry.value, "data_type": null})
          .toList(growable: false),
      "namespace": namespace,
      "branch": branch,
    });
  }

  Future<void> addColumnsOfType({
    required String table,
    required Map<String, DataType> newColumns,
    List<String>? namespace,
    String? branch,
  }) async {
    await _invoke("add_columns", {
      "table": table,
      "columns": newColumns.entries
          .map((entry) => {"name": entry.key, "value_sql": null, "data_type": _toolkitDataTypeJson(entry.value)})
          .toList(growable: false),
      "namespace": namespace,
      "branch": branch,
    });
  }

  Future<void> dropColumns({required String table, required List<String> columns, List<String>? namespace, String? branch}) async {
    await _invoke("drop_columns", {"table": table, "columns": columns, "namespace": namespace, "branch": branch});
  }

  Future<void> dropIndex({required String table, required String name, List<String>? namespace, String? branch}) async {
    await _invoke("drop_index", {"table": table, "name": name, "namespace": namespace, "branch": branch});
  }

  Future<void> insert({required String table, required List<Map<String, dynamic>> records, List<String>? namespace, String? branch}) async {
    await insertStream(table: table, chunks: Stream.fromIterable(_rowChunks(records)), namespace: namespace, branch: branch);
  }

  Future<void> insertStream({
    required String table,
    required Stream<List<Map<String, dynamic>>> chunks,
    List<String>? namespace,
    String? branch,
  }) async {
    final input = _DatabaseWriteInputStream(
      start: {"kind": "start", "table": table, "namespace": namespace, "branch": branch},
      chunks: chunks,
    );
    await _drainWriteStream("insert", input);
  }

  Future<void> update({
    required String table,
    required String where,
    Map<String, dynamic>? values,
    Map<String, String>? valuesSql,
    List<String>? namespace,
    String? branch,
  }) async {
    await _invoke("update", {
      "table": table,
      "where": where,
      "values": values?.entries.map((entry) => {"column": entry.key, "value_json": _valueJson(entry.value)}).toList(growable: false),
      "values_sql": valuesSql?.entries.map((entry) => {"column": entry.key, "expression": entry.value}).toList(growable: false),
      "namespace": namespace,
      "branch": branch,
    });
  }

  Future<void> delete({required String table, required String where, List<String>? namespace, String? branch}) async {
    await _invoke("delete", {"table": table, "where": where, "namespace": namespace, "branch": branch});
  }

  Future<void> merge({
    required String table,
    required String on,
    required List<Map<String, dynamic>> records,
    List<String>? namespace,
    String? branch,
  }) async {
    await mergeStream(table: table, on: on, chunks: Stream.fromIterable(_rowChunks(records)), namespace: namespace, branch: branch);
  }

  Future<void> mergeStream({
    required String table,
    required String on,
    required Stream<List<Map<String, dynamic>>> chunks,
    List<String>? namespace,
    String? branch,
  }) async {
    final input = _DatabaseWriteInputStream(
      start: {"kind": "start", "table": table, "on": on, "namespace": namespace, "branch": branch},
      chunks: chunks,
    );
    await _drainWriteStream("merge", input);
  }

  Future<List<Map<String, dynamic>>> sql({required String query, required List<TableRef> tables, Map<String, dynamic>? params}) async {
    final rows = <Map<String, dynamic>>[];
    await for (final chunk in sqlStream(query: query, tables: tables, params: params)) {
      rows.addAll(chunk);
    }
    return rows;
  }

  Stream<List<Map<String, dynamic>>> sqlStream({required String query, required List<TableRef> tables, Map<String, dynamic>? params}) {
    return _streamRows("sql", {
      "kind": "start",
      "query": query,
      "tables": tables.map((table) => table.toJson()).toList(growable: false),
      "params_json": params == null ? null : jsonEncode(_encodeRecordValue(params)),
    });
  }

  Future<List<Map<String, dynamic>>> search({
    required String table,
    String? text,
    List<double>? vector,
    dynamic where,
    int? offset,
    int? limit,
    List<String>? select,
    List<String>? namespace,
    String? branch,
    int? version,
  }) async {
    final rows = <Map<String, dynamic>>[];
    await for (final chunk in searchStream(
      table: table,
      text: text,
      vector: vector,
      where: where,
      offset: offset,
      limit: limit,
      select: select,
      namespace: namespace,
      branch: branch,
      version: version,
    )) {
      rows.addAll(chunk);
    }
    return rows;
  }

  Stream<List<Map<String, dynamic>>> searchStream({
    required String table,
    String? text,
    List<double>? vector,
    dynamic where,
    int? offset,
    int? limit,
    List<String>? select,
    List<String>? namespace,
    String? branch,
    int? version,
  }) {
    return _streamRows("search", {
      "kind": "start",
      "table": table,
      "text": text,
      "vector": vector,
      "text_columns": null,
      "where": _whereClause(where),
      "offset": offset,
      "limit": limit,
      "select": select,
      "namespace": namespace,
      "branch": branch,
      "version": version,
    });
  }

  Future<int> count({
    required String table,
    String? text,
    List<double>? vector,
    dynamic where,
    List<String>? namespace,
    String? branch,
    int? version,
  }) async {
    final response = await _invoke("count", {
      "table": table,
      "text": text,
      "vector": vector,
      "text_columns": null,
      "where": _whereClause(where),
      "namespace": namespace,
      "branch": branch,
      "version": version,
    });
    if (response is! JsonContent) {
      throw RoomServerException("unexpected return type from database.count call");
    }
    final count = response.json["count"];
    if (count is! num) {
      throw RoomServerException("unexpected return type from database.count call");
    }
    return count.toInt();
  }

  Future<void> optimize({required String table, List<String>? namespace, String? branch}) async {
    await _invoke("optimize", {"table": table, "namespace": namespace, "branch": branch});
  }

  Future<void> restore({required String table, required int version, List<String>? namespace, String? branch}) async {
    await _invoke("restore", {"table": table, "version": version, "namespace": namespace, "branch": branch});
  }

  Future<Map<String, DataType>> inspect(String table, {List<String>? namespace, String? branch, int? version}) async {
    final response = await _invoke("inspect", {"table": table, "namespace": namespace, "branch": branch, "version": version});
    if (response is! JsonContent) {
      throw RoomServerException("unexpected return type from database.inspect call");
    }
    final fields = response.json["fields"];
    if (fields is! List) {
      throw RoomServerException("unexpected return type from database.inspect call");
    }
    return {
      for (final rawField in fields)
        if (rawField is Map && rawField["name"] is String)
          rawField["name"] as String: DataType.fromJson(_publicDataTypeJson(rawField["data_type"])),
    };
  }

  Future<List<TableVersion>> listVersions(String table, {List<String>? namespace, String? branch}) async {
    final response = await _invoke("list_versions", {"table": table, "namespace": namespace, "branch": branch});
    if (response is! JsonContent) {
      throw RoomServerException("unexpected return type from database.list_versions call");
    }
    final versions = response.json["versions"];
    if (versions is! List) {
      throw RoomServerException("unexpected return type from database.list_versions call");
    }
    return versions
        .map((value) {
          if (value is! Map) {
            throw RoomServerException("unexpected return type from database.list_versions call");
          }
          final metadataJson = value["metadata_json"];
          if (metadataJson is! String) {
            throw RoomServerException("unexpected return type from database.list_versions call");
          }
          final metadata = jsonDecode(metadataJson);
          if (metadata is! Map) {
            throw RoomServerException("unexpected return type from database.list_versions call");
          }
          return TableVersion(
            version: (value["version"] as num).toInt(),
            timestamp: DateTime.parse(value["timestamp"] as String),
            metadata: Map<String, dynamic>.from(metadata),
          );
        })
        .toList(growable: false);
  }

  Future<void> createVectorIndex({
    required String table,
    required String column,
    List<String>? namespace,
    String? branch,
    bool replace = false,
  }) async {
    await _invoke("create_vector_index", {"table": table, "column": column, "namespace": namespace, "branch": branch, "replace": replace});
  }

  Future<void> createScalarIndex({
    required String table,
    required String column,
    List<String>? namespace,
    String? branch,
    bool replace = false,
  }) async {
    await _invoke("create_scalar_index", {"table": table, "column": column, "namespace": namespace, "branch": branch, "replace": replace});
  }

  Future<void> createFullTextSearchIndex({
    required String table,
    required String column,
    List<String>? namespace,
    String? branch,
    bool replace = false,
  }) async {
    await _invoke("create_full_text_search_index", {
      "table": table,
      "column": column,
      "namespace": namespace,
      "branch": branch,
      "replace": replace,
    });
  }

  Future<List<TableIndex>> listIndexes(String table, {List<String>? namespace, String? branch, int? version}) async {
    final response = await _invoke("list_indexes", {"table": table, "namespace": namespace, "branch": branch, "version": version});
    if (response is! JsonContent) {
      throw RoomServerException("unexpected return type from database.list_indexes call");
    }
    final indexes = response.json["indexes"];
    if (indexes is! List) {
      throw RoomServerException("unexpected return type from database.list_indexes call");
    }
    return indexes.map((value) => TableIndex.fromJson(Map<String, dynamic>.from(value as Map))).toList(growable: false);
  }

  Future<List<TableBranch>> listBranches({List<String>? namespace}) async {
    final response = await _invoke("list_branches", {"namespace": namespace});
    if (response is! JsonContent) {
      throw RoomServerException("unexpected return type from database.list_branches call");
    }
    final branches = response.json["branches"];
    if (branches is! List) {
      throw RoomServerException("unexpected return type from database.list_branches call");
    }
    return branches.map((value) => TableBranch.fromJson(Map<String, dynamic>.from(value as Map))).toList(growable: false);
  }

  Future<void> createBranch({required String branch, String? fromBranch, List<String>? namespace}) async {
    await _invoke("create_branch", {"branch": branch, "from_branch": fromBranch, "namespace": namespace});
  }

  Future<void> deleteBranch({required String branch, List<String>? namespace}) async {
    await _invoke("delete_branch", {"branch": branch, "namespace": namespace});
  }
}

class TableVersion {
  const TableVersion({required this.version, required this.timestamp, required this.metadata});

  final int version;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;
}

class TableIndex {
  const TableIndex({required this.columns, required this.type, required this.name});

  final List<String> columns;
  final String name;
  final String type;

  static TableIndex fromJson(Map<String, dynamic> json) {
    return TableIndex(columns: [...json["columns"]], type: json["type"], name: json["name"]);
  }
}

dynamic _decodeRecordValue(dynamic value) {
  if (value is List) {
    return value.map(_decodeRecordValue).toList(growable: false);
  }

  if (value is Map<String, dynamic>) {
    final encoding = value["encoding"];
    if (encoding == "base64" && value.length == 2 && value["data"] is String) {
      return base64Decode(value["data"] as String);
    }
    return value.map((key, innerValue) => MapEntry(key, _decodeRecordValue(innerValue)));
  }

  return value;
}

List<Map<String, dynamic>> decodeRecords(List<Map<String, dynamic>> records) {
  for (final record in records) {
    for (final key in record.keys.toList()) {
      record[key] = _decodeRecordValue(record[key]);
    }
  }
  return records;
}

dynamic _encodeRecordValue(dynamic value) {
  if (value is Uint8List) {
    return {"encoding": "base64", "data": base64Encode(value)};
  }
  if (value is DateTime) {
    final normalized = value.isUtc ? value : value.toUtc();
    return normalized.toIso8601String().replaceFirst("+00:00", "Z");
  }
  if (value is List) {
    return value.map(_encodeRecordValue).toList(growable: false);
  }
  if (value is Map<String, dynamic>) {
    return value.map((key, innerValue) => MapEntry(key, _encodeRecordValue(innerValue)));
  }
  return value;
}

List<Map<String, dynamic>> encodeRecords(List<Map<String, dynamic>> records) {
  return records.map((record) => record.map((key, value) => MapEntry(key, _encodeRecordValue(value)))).toList(growable: false);
}
