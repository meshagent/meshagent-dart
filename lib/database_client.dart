// database_client.dart
import 'room_server_client.dart';
import 'data_types.dart';

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
  Future<List<String>> listTables() async {
    final response = (await room.sendRequest("database.list_tables", {}) as JsonResponse);

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
  }) async {
    Map<String, dynamic>? schemaDict;

    if (schema != null) {
      schemaDict = {};
      schema.forEach((key, value) {
        schemaDict![key] = value.toJson();
      });
    }

    final payload = <String, dynamic>{"name": name, "data": data, "schema": schemaDict, "mode": mode.value};

    await room.sendRequest("database.create_table", payload);
  }

  /// Create a new table with a specific schema.
  Future<void> createTableWithSchema({required String name, required Map<String, DataType> schema, CreateMode mode = CreateMode.create}) {
    return _createTable(name: name, schema: schema, mode: mode);
  }

  /// Create a table from initial data, optionally specifying a mode.
  Future<void> createTableFromData({required String name, required List<Map<String, dynamic>> data, CreateMode mode = CreateMode.create}) {
    return _createTable(name: name, data: data, mode: mode);
  }

  /// Drop (delete) a table by name.
  Future<void> dropTable({required String name, bool ignoreMissing = false}) async {
    await room.sendRequest("database.drop_table", {"name": name, "ignoreMissing": ignoreMissing});
  }

  /// Add new columns to an existing table.
  Future<void> addColumns({required String table, required Map<String, String> newColumns}) async {
    await room.sendRequest("database.add_columns", {"table": table, "new_columns": newColumns});
  }

  /// Drop columns from an existing table.
  Future<void> dropColumns({required String table, required List<String> columns}) async {
    await room.sendRequest("database.drop_columns", {"table": table, "columns": columns});
  }

  /// Insert new records into a table.
  Future<void> insert({required String table, required List<Map<String, dynamic>> records}) async {
    await room.sendRequest("database.insert", {"table": table, "records": records});
  }

  /// Update existing records in a table.
  Future<void> update({required String table, required String where, Map<String, dynamic>? values, Map<String, String>? valuesSql}) async {
    final payload = <String, dynamic>{"table": table, "where": where, "values": values, "valuesSql": valuesSql};
    await room.sendRequest("database.update", payload);
  }

  /// Delete records from a table.
  Future<void> delete({required String table, required String where}) async {
    await room.sendRequest("database.delete", {"table": table, "where": where});
  }

  /// Merge (upsert) records into a table.
  Future<void> merge({required String table, required String on, required List<Map<String, dynamic>> records}) async {
    await room.sendRequest("database.merge", {"table": table, "on": on, "records": records});
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

    final response = (await room.sendRequest("database.search", payload) as JsonResponse);

    // If your sendRequest returns a structure like { "json": { "results": [...] } }
    // Then parse it accordingly:
    final results = response.json["results"];

    if (results is List) {
      return results.map((e) => e as Map<String, dynamic>).toList();
    }

    return [];
  }

  /// A helper to safely convert values to SQL strings (very naive).
  /// You might replace this with parameterized queries in real code.
  String _escapeValue(dynamic value) {
    // For simplicity, just JSON-encode. In real usage, sanitize properly.
    return "'${value.toString().replaceAll("'", "''")}'";
  }

  /// Optimize (compact/prune) a table.
  Future<void> optimize({required String table}) async {
    await room.sendRequest("database.optimize", {"table": table});
  }

  /// Restore a previous version of a table
  Future<void> restore({required String table, required int version}) async {
    await room.sendRequest("database.restore", {"table": table, "version": version});
  }

  /// Checkout a version of a table (will put the table in a read only mode)
  Future<void> checkout({required String table, required int version}) async {
    await room.sendRequest("database.checkout", {"table": table, "version": version});
  }

  /// List versions of a table
  Future<List<TableVersion>> listVersions(String table) async {
    final versions = (await room.sendRequest("database.list_versions", {"table": table}) as JsonResponse).json["versions"] as List;
    return versions.map((v) => TableVersion(version: (v["version"] as num).toInt(), timestamp: DateTime.parse(v["timestamp"]))).toList();
  }

  /// Create a vector index on a given column.
  Future<void> createVectorIndex({required String table, required String column}) async {
    await room.sendRequest("database.create_vector_index", {"table": table, "column": column});
  }

  /// Create a scalar index on a given column.
  Future<void> createScalarIndex({required String table, required String column}) async {
    await room.sendRequest("database.create_scalar_index", {"table": table, "column": column});
  }

  /// Create a full-text search index on a given text column.
  Future<void> createFullTextSearchIndex({required String table, required String column}) async {
    await room.sendRequest("database.create_full_text_search_index", {"table": table, "column": column});
  }

  /// List all indexes on a table.
  Future<Map<String, dynamic>> listIndexes({required String table}) async {
    final response = await room.sendRequest("database.list_indexes", {"table": table}) as Map<String, dynamic>?;
    final json = response?["json"] as Map<String, dynamic>?;

    return json ?? {};
  }
}

class TableVersion {
  TableVersion({required this.version, required this.timestamp});

  final int version;
  final DateTime timestamp;
}
