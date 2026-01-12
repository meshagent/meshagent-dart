// database_client.dart
import 'room_server_client.dart';
import 'data_types.dart';

import 'dart:convert';
import 'dart:typed_data';

/// A literal type for controlling table creation mode.
/// In TypeScript: type CreateMode = "create" | "overwrite" | "create_if_not_exists";
/// In Dart, we can use an enum or string constants. Here we'll use an enum.
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

/// A client for interacting with the 'database' extension on the room server.
class DatabaseClient {
  final RoomClient room;

  /// @param room The RoomClient used to send requests.
  DatabaseClient({required this.room});

  /// List all tables in the database.
  /// @returns A future resolving to an array of table names.
  Future<List<String>> listTables({List<String>? namespace}) async {
    final response = (await room.sendRequest("database.list_tables", {"namespace": namespace}) as JsonResponse);

    // Safely extract tables from response JSON
    final tables = response.json["tables"] as List<dynamic>? ?? [];

    return tables.map((e) => e.toString()).toList();
  }

  /// Private helper for creating a table.
  Future<void> _createTable({
    required String name,
    List<Map<String, dynamic>>? data,
    Map<String, DataType>? schema,
    CreateMode mode = CreateMode.create,
    List<String>? namespace,
    Map<String, dynamic>? metadata,
  }) async {
    Map<String, dynamic>? schemaDict;

    if (schema != null) {
      schemaDict = {};
      schema.forEach((key, value) {
        schemaDict![key] = value.toJson();
      });
    }

    final payload = <String, dynamic>{"name": name, "data": data, "schema": schemaDict, "mode": mode.value, "namespace": namespace};

    await room.sendRequest("database.create_table", payload);
  }

  /// Create a new table with a specific schema.
  Future<void> createTableWithSchema({
    required String name,
    required Map<String, DataType> schema,
    CreateMode mode = CreateMode.create,
    List<String>? namespace,
    Map<String, dynamic>? metadata,
  }) {
    return _createTable(name: name, schema: schema, mode: mode, namespace: namespace, metadata: metadata);
  }

  /// Create a table from initial data, optionally specifying a mode.
  Future<void> createTableFromData({
    required String name,
    required List<Map<String, dynamic>> data,
    CreateMode mode = CreateMode.create,
    List<String>? namespace,
    Map<String, dynamic>? metadata,
  }) {
    return _createTable(name: name, data: data, mode: mode, namespace: namespace, metadata: metadata);
  }

  /// Drop (delete) a table by name.
  Future<void> dropTable({required String name, bool ignoreMissing = false, List<String>? namespace}) async {
    await room.sendRequest("database.drop_table", {"name": name, "ignoreMissing": ignoreMissing, "namespace": namespace});
  }

  /// Add new columns to an existing table.
  Future<void> addColumnWithExpression({required String table, required Map<String, String> newColumns, List<String>? namespace}) async {
    await room.sendRequest("database.add_columns", {"table": table, "new_columns": newColumns, "namespace": namespace});
  }

  /// Add new columns to an existing table.
  Future<void> addColumnsOfType({required String table, required Map<String, DataType> newColumns, List<String>? namespace}) async {
    await room.sendRequest("database.add_columns", {
      "table": table,
      "new_columns": {for (final entry in newColumns.entries) entry.key: entry.value.toJson()},
      "namespace": namespace,
    });
  }

  /// Drop columns from an existing table.
  Future<void> dropColumns({required String table, required List<String> columns, List<String>? namespace}) async {
    await room.sendRequest("database.drop_columns", {"table": table, "columns": columns, "namespace": namespace});
  }

  /// Drop columns from an existing table.
  Future<void> dropIndex({required String table, required String name, List<String>? namespace}) async {
    await room.sendRequest("database.drop_index", {"table": table, "name": name, "namespace": namespace});
  }

  /// Insert new records into a table.
  Future<void> insert({required String table, required List<Map<String, dynamic>> records, List<String>? namespace}) async {
    await room.sendRequest("database.insert", {"table": table, "records": encodeRecords(records), "namespace": namespace});
  }

  /// Update existing records in a table.
  Future<void> update({
    required String table,
    required String where,
    Map<String, dynamic>? values,
    Map<String, String>? valuesSql,
    List<String>? namespace,
  }) async {
    final payload = <String, dynamic>{"table": table, "where": where, "values": values, "valuesSql": valuesSql, "namespace": namespace};
    await room.sendRequest("database.update", payload);
  }

  /// Delete records from a table.
  Future<void> delete({required String table, required String where, List<String>? namespace}) async {
    await room.sendRequest("database.delete", {"table": table, "where": where, "namespace": namespace});
  }

  /// Merge (upsert) records into a table.
  Future<void> merge({
    required String table,
    required String on,
    required List<Map<String, dynamic>> records,
    List<String>? namespace,
  }) async {
    await room.sendRequest("database.merge", {"table": table, "on": on, "records": records, "namespace": namespace});
  }

  /// Search for records in a table.
  Future<List<Map<String, dynamic>>> search({
    required String table,
    String? text,
    List<double>? vector,
    dynamic where, // String or Map<String, dynamic>
    int? offset,
    int? limit,
    List<String>? select,
    List<String>? namespace,
  }) async {
    // If 'where' is a Map, convert it to an AND-joined string.
    String? whereClause;
    if (where is Map<String, dynamic>) {
      final parts = <String>[];
      where.forEach((key, value) {
        parts.add("$key = ${_escapeValue(value)}");
      });
      whereClause = parts.join(" AND ");
    } else if (where is String) {
      whereClause = where;
    }

    final payload = <String, dynamic>{"table": table, "where": whereClause, "text": text};

    if (offset != null) {
      payload["offset"] = offset;
    }
    if (limit != null) {
      payload["limit"] = limit;
    }
    if (select != null) {
      payload["select"] = select;
    }
    if (vector != null) {
      payload["vector"] = vector;
    }

    payload["namespace"] = namespace;

    final response = (await room.sendRequest("database.search", payload) as JsonResponse);

    // If your sendRequest returns a structure like { "json": { "results": [...] } }
    // Then parse it accordingly:
    final results = decodeRecords((response.json["results"] as List).cast<Map<String, dynamic>>());
    return results.toList();
  }

  /// Count records in a table.
  Future<int> count({
    required String table,
    String? text,
    List<double>? vector,
    dynamic where, // String or Map<String, dynamic>
    List<String>? namespace,
  }) async {
    // If 'where' is a Map, convert it to an AND-joined string.
    String? whereClause;
    if (where is Map<String, dynamic>) {
      final parts = <String>[];
      where.forEach((key, value) {
        parts.add("$key = ${_escapeValue(value)}");
      });
      whereClause = parts.join(" AND ");
    } else if (where is String) {
      whereClause = where;
    }

    final payload = <String, dynamic>{"table": table, "where": whereClause, "text": text};

    if (vector != null) {
      payload["vector"] = vector;
    }

    payload["namespace"] = namespace;

    final response = (await room.sendRequest("database.count", payload) as JsonResponse);

    // If your sendRequest returns a structure like { "json": { "results": [...] } }
    // Then parse it accordingly:
    return (response.json["count"] as num).toInt();
  }

  /// A helper to safely convert values to SQL strings (very naive).
  /// You might replace this with parameterized queries in real code.
  String _escapeValue(dynamic value) {
    // For simplicity, just JSON-encode. In real usage, sanitize properly.
    return "'${value.toString().replaceAll("'", "''")}'";
  }

  /// Optimize (compact/prune) a table.
  Future<void> optimize({required String table, List<String>? namespace}) async {
    await room.sendRequest("database.optimize", {"table": table, "namespace": namespace});
  }

  /// Restore a previous version of a table
  Future<void> restore({required String table, required int version, List<String>? namespace}) async {
    await room.sendRequest("database.restore", {"table": table, "version": version, "namespace": namespace});
  }

  /// Restore a previous version of a table
  Future<Map<String, DataType>> inspect(String table, {List<String>? namespace}) async {
    final json = (await room.sendRequest("database.inspect", {"table": table, "namespace": namespace}) as JsonResponse);
    final schema = json.json["schema"] as Map;
    return {for (final k in schema.keys) k: DataType.fromJson(schema[k])};
  }

  /// Checkout a version of a table (will put the table in a read only mode)
  Future<void> checkout({required String table, required int version, List<String>? namespace}) async {
    await room.sendRequest("database.checkout", {"table": table, "version": version, "namespace": namespace});
  }

  /// List versions of a table
  Future<List<TableVersion>> listVersions(String table, {List<String>? namespace}) async {
    final versions =
        (await room.sendRequest("database.list_versions", {"table": table, "namespace": namespace}) as JsonResponse).json["versions"]
            as List;
    return versions.map((v) => TableVersion(version: (v["version"] as num).toInt(), timestamp: DateTime.parse(v["timestamp"]))).toList();
  }

  /// Create a vector index on a given column.
  Future<void> createVectorIndex({required String table, required String column, List<String>? namespace, bool replace = false}) async {
    await room.sendRequest("database.create_vector_index", {"table": table, "column": column, "namespace": namespace, "replace": replace});
  }

  /// Create a scalar index on a given column.
  Future<void> createScalarIndex({required String table, required String column, List<String>? namespace, bool replace = false}) async {
    await room.sendRequest("database.create_scalar_index", {"table": table, "column": column, "namespace": namespace, "replace": replace});
  }

  /// Create a full-text search index on a given text column.
  Future<void> createFullTextSearchIndex({
    required String table,
    required String column,
    List<String>? namespace,
    bool replace = false,
  }) async {
    await room.sendRequest("database.create_full_text_search_index", {
      "table": table,
      "column": column,
      "namespace": namespace,
      "replace": replace,
    });
  }

  /// List all indexes on a table.
  Future<List<TableIndex>> listIndexes(String table, {List<String>? namespace}) async {
    final response = await room.sendRequest("database.list_indexes", {"table": table, "namespace": namespace}) as JsonResponse;
    final indexes = response.json["indexes"] as List;

    return [...indexes.map((m) => TableIndex.fromJson(m))];
  }
}

class TableVersion {
  const TableVersion({required this.version, required this.timestamp});

  final int version;
  final DateTime timestamp;
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

/// Decodes any base64-encoded fields in the list of record maps.
/// If a value is a map with {"encoding": "base64", "data": ...},
/// it will be replaced with a `Uint8List` containing the decoded bytes.
List<Map<String, dynamic>> decodeRecords(List<Map<String, dynamic>> records) {
  for (final r in records) {
    for (final k in r.keys.toList()) {
      final v = r[k];
      if (v is Map<String, dynamic>) {
        final encoding = v["encoding"];
        if (encoding == "base64") {
          final data = v["data"] as String;
          r[k] = base64Decode(data);
        } else {
          throw ArgumentError("Invalid encoding type $encoding");
        }
      }
    }
  }
  return records;
}

/// Encodes any `Uint8List` (or raw bytes) in the record maps
/// into a {"encoding": "base64", "data": "..."} wrapper.
List<Map<String, dynamic>> encodeRecords(List<Map<String, dynamic>> records) {
  final transformedRecords = <Map<String, dynamic>>[];

  for (final r in records) {
    final c = <String, dynamic>{};
    for (final k in r.keys) {
      final v = r[k];
      if (v is Uint8List) {
        c[k] = {"encoding": "base64", "data": base64Encode(v)};
      } else {
        c[k] = v;
      }
    }
    transformedRecords.add(c);
  }

  return transformedRecords;
}
