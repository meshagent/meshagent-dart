import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:meshagent_dart_arrow/meshagent_dart_arrow.dart';
import 'package:uuid/uuid.dart';

import 'agents_client.dart';
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

enum DatasetStorageFormat { auto, json, arrow, csv, tsv, parquet, excel }

extension DatasetStorageFormatValue on DatasetStorageFormat {
  String get value {
    switch (this) {
      case DatasetStorageFormat.auto:
        return "auto";
      case DatasetStorageFormat.json:
        return "json";
      case DatasetStorageFormat.arrow:
        return "arrow";
      case DatasetStorageFormat.csv:
        return "csv";
      case DatasetStorageFormat.tsv:
        return "tsv";
      case DatasetStorageFormat.parquet:
        return "parquet";
      case DatasetStorageFormat.excel:
        return "excel";
    }
  }
}

enum DatasetImportMode { create, replace, merge }

extension DatasetImportModeValue on DatasetImportMode {
  String get value {
    switch (this) {
      case DatasetImportMode.create:
        return "create";
      case DatasetImportMode.replace:
        return "replace";
      case DatasetImportMode.merge:
        return "merge";
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

sealed class DatasetSqlExecution {
  const DatasetSqlExecution();
}

class DatasetSqlQuery extends DatasetSqlExecution {
  const DatasetSqlQuery({required this.schema, required this.queryId});

  final ArrowSchema schema;
  final String queryId;
}

class DatasetSqlStatement extends DatasetSqlExecution {
  const DatasetSqlStatement({required this.rowsAffected});

  final int rowsAffected;
}

enum DatasetSqlCancelStatus { cancelled, cancelling, notCancellable }

class DatasetSqlCancelResult {
  const DatasetSqlCancelResult({required this.status});

  final DatasetSqlCancelStatus status;
}

typedef DatasetRecord = Map<String, Object?>;
typedef DatasetRows = List<DatasetRecord>;
typedef DatasetRowChunks = Stream<DatasetRows>;
typedef DatasetArrowBatches = Stream<ArrowRecordBatch>;

enum DatasetTableWatchPhase { initial, delta }

class DatasetTableWatchEvent {
  const DatasetTableWatchEvent({
    required this.kind,
    required this.phase,
    this.batch,
    this.changeType,
    this.version,
    this.beginVersion,
    this.endVersion,
    this.transactions,
    this.deletePredicate,
    this.transaction,
  });

  final String kind;
  final DatasetTableWatchPhase phase;
  final ArrowRecordBatch? batch;
  final String? changeType;
  final int? version;
  final int? beginVersion;
  final int? endVersion;
  final List<Map<String, Object?>>? transactions;
  final String? deletePredicate;
  final Map<String, Object?>? transaction;
}

const _arrowIpcStreamMimeType = "application/vnd.apache.arrow.stream";

ArrowTable _tableFromBatches(List<ArrowRecordBatch> batches) {
  return ArrowTable(schema: batches.isEmpty ? const ArrowSchema([]) : batches.first.schema, batches: batches);
}

sealed class DatasetValueEncoder {
  const DatasetValueEncoder();

  Object? encodeDatasetValue();
}

final class DatasetExpression extends DatasetValueEncoder {
  DatasetExpression(String expression) : expression = expression.trim() {
    if (this.expression.isEmpty) {
      throw ArgumentError.value(expression, 'expression', 'dataset expression must not be empty');
    }
  }

  final String expression;

  @override
  Map<String, String> encodeDatasetValue() {
    return {"expression": expression};
  }

  @override
  String toString() => expression;
}

final class DatasetDate extends DatasetValueEncoder {
  DatasetDate(String value) : value = value.trim() {
    final match = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(this.value);
    final parsed = DateTime.tryParse(this.value);
    if (!match || parsed == null || parsed.toUtc().toIso8601String().substring(0, 10) != this.value) {
      throw ArgumentError.value(value, 'value', 'invalid dataset date format');
    }
  }

  final String value;

  @override
  Map<String, String> encodeDatasetValue() {
    return {"date": value};
  }

  @override
  String toString() => value;
}

final class DatasetStruct extends DatasetValueEncoder {
  DatasetStruct(Map<String, Object?> fields) : fields = Map.unmodifiable(fields);

  final Map<String, Object?> fields;

  Map<String, dynamic> toJson() {
    return {for (final entry in fields.entries) entry.key: _encodeRecordValue(entry.value)};
  }

  @override
  Map<String, dynamic> encodeDatasetValue() {
    return {"struct": toJson()};
  }
}

final class DatasetJson extends DatasetValueEncoder {
  DatasetJson(Object? value) : value = _normalizeDatasetJsonValue(value);

  final Object? value;

  Object? toJson() => value;

  @override
  Map<String, dynamic> encodeDatasetValue() {
    return {"json": value};
  }
}

Object? _normalizeDatasetJsonValue(Object? value) {
  if (value == null || value is bool || value is num || value is String) {
    return value;
  }
  if (value is List) {
    return value.map(_normalizeDatasetJsonValue).toList(growable: false);
  }
  if (value is Map) {
    final normalized = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw ArgumentError.value(value, 'value', 'dataset json object keys must be strings');
      }
      normalized[entry.key as String] = _normalizeDatasetJsonValue(entry.value);
    }
    return Map<String, Object?>.unmodifiable(normalized);
  }
  throw ArgumentError.value(value, 'value', 'dataset json values must be valid JSON');
}

List<Map<String, dynamic>>? _metadataEntries(Map<String, dynamic>? metadata) {
  if (metadata == null) {
    return null;
  }
  return metadata.entries
      .map((entry) => {"key": entry.key, "value": entry.value is String ? entry.value : jsonEncode(_encodeRecordValue(entry.value))})
      .toList(growable: false);
}

String _valueJson(Object? value) {
  return jsonEncode(_encodeRecordValue(value));
}

String _bytesToHex(Uint8List bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

String _datasetSqlLiteral(Object? value) {
  if (value is UuidValue) {
    return "X'${_bytesToHex(value.toBytes(validate: true))}'";
  }
  if (value is DatasetDate) {
    return jsonEncode(value.toString());
  }
  if (value is DateTime) {
    final normalized = value.isUtc ? value : value.toUtc();
    return jsonEncode(normalized.toIso8601String().replaceFirst("+00:00", "Z"));
  }
  if (value is DatasetJson) {
    return jsonEncode(jsonEncode(value.toJson()));
  }
  if (value is DatasetStruct) {
    final fields = value.fields.entries.map((entry) => "${jsonEncode(entry.key)}, ${_datasetSqlLiteral(entry.value)}").join(", ");
    return "named_struct($fields)";
  }
  return jsonEncode(_encodeRecordValue(value));
}

Map<String, dynamic> _rowsChunk(DatasetRows rows) {
  return {
    "kind": "rows",
    "rows": rows
        .map(
          (row) => {
            "columns": row.entries.map((entry) => {"name": entry.key, "value": _encodeRecordValue(entry.value)}).toList(growable: false),
          },
        )
        .toList(growable: false),
  };
}

DatasetRows _recordsFromRowsChunk(Map<String, dynamic> json, String operation) {
  if (json["kind"] != "rows") {
    throw RoomServerException("unexpected return type from datasets.$operation call");
  }
  final rows = json["rows"];
  if (rows is! List) {
    throw RoomServerException("unexpected return type from datasets.$operation call");
  }

  return rows
      .map((rawRow) {
        if (rawRow is! Map) {
          throw RoomServerException("unexpected return type from datasets.$operation call");
        }
        final columns = rawRow["columns"];
        if (columns is! List) {
          throw RoomServerException("unexpected return type from datasets.$operation call");
        }
        final decoded = <String, Object?>{};
        for (final rawColumn in columns) {
          if (rawColumn is! Map || rawColumn["name"] is! String) {
            throw RoomServerException("unexpected return type from datasets.$operation call");
          }
          try {
            decoded[rawColumn["name"] as String] = _decodeRecordValue(rawColumn["value"]);
          } catch (_) {
            throw RoomServerException("unexpected return type from datasets.$operation call");
          }
        }
        return decoded;
      })
      .toList(growable: false);
}

List<DatasetRows> _rowChunks(DatasetRows rows, {int rowsPerChunk = 128}) {
  if (rowsPerChunk <= 0) {
    throw RoomServerException("rowsPerChunk must be greater than zero");
  }
  final chunks = <DatasetRows>[];
  for (var index = 0; index < rows.length; index += rowsPerChunk) {
    final end = index + rowsPerChunk > rows.length ? rows.length : index + rowsPerChunk;
    chunks.add(rows.sublist(index, end));
  }
  return chunks;
}

String? _whereClause(Object? where) {
  if (where is Map) {
    final parts = <String>[];
    where.forEach((key, value) {
      parts.add("${key.toString()} = ${_datasetSqlLiteral(value)}");
    });
    return parts.join(" AND ");
  }
  if (where is String) {
    return where;
  }
  return null;
}

class _DatasetWriteInputStream {
  _DatasetWriteInputStream({required this.start, required DatasetRowChunks chunks}) : _source = StreamQueue(chunks);

  final Map<String, dynamic> start;
  final StreamQueue<DatasetRows> _source;
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

class _DatasetReadInputStream {
  _DatasetReadInputStream({required this.start});

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

class _DatasetArrowWriteInputStream {
  _DatasetArrowWriteInputStream({required this.start, required DatasetArrowBatches chunks, this.schema}) : _source = StreamQueue(chunks);

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

class _DatasetArrowReadInputStream {
  _DatasetArrowReadInputStream({required this.start});

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

class DatasetsClient {
  final RoomClient room;

  DatasetsClient({required this.room});

  Future<Content> _invoke(String operation, Map<String, dynamic> input) async {
    final output = await room.invoke(
      toolkit: "dataset",
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
    throw RoomServerException("unexpected return type from datasets.$operation call");
  }

  Future<Content> _invokeContent(String operation, Content input) async {
    final output = await room.invoke(toolkit: "dataset", tool: operation, input: ToolContentInput(input));
    if (output is ToolContentOutput) {
      if (output.content is ErrorContent) {
        final error = output.content as ErrorContent;
        throw RoomServerException(error.text, code: error.code);
      }
      return output.content;
    }
    throw RoomServerException("unexpected return type from datasets.$operation call");
  }

  Future<Stream<Content>> _invokeStream(String operation, Stream<Content> input) async {
    final output = await room.invoke(toolkit: "dataset", tool: operation, input: ToolStreamInput(input));
    if (output is! ToolStreamOutput) {
      throw RoomServerException("unexpected return type from datasets.$operation call");
    }
    return output.stream;
  }

  Future<void> _drainWriteStream(String operation, _DatasetWriteInputStream input) async {
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
          throw RoomServerException("unexpected return type from datasets.$operation call");
        }
        if (chunk is! JsonContent || chunk.json["kind"] != "pull") {
          throw RoomServerException("unexpected return type from datasets.$operation call");
        }
        input.requestNext();
      }
    } finally {
      input.close();
    }
  }

  Future<void> _drainArrowWriteStream(String operation, _DatasetArrowWriteInputStream input) async {
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
          throw RoomServerException("unexpected return type from datasets.$operation call");
        }
        if (chunk is! BinaryContent || chunk.headers["kind"] != "pull") {
          throw RoomServerException("unexpected return type from datasets.$operation call");
        }
        input.requestNext();
      }
    } finally {
      input.close();
    }
  }

  // ignore: unused_element
  DatasetRowChunks _streamRows(String operation, Map<String, dynamic> start) async* {
    final input = _DatasetReadInputStream(start: start);
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
          throw RoomServerException("unexpected return type from datasets.$operation call");
        }
        if (chunk is! JsonContent) {
          throw RoomServerException("unexpected return type from datasets.$operation call");
        }
        yield _recordsFromRowsChunk(chunk.json, operation);
        input.requestNext();
      }
    } finally {
      input.close();
    }
  }

  DatasetArrowBatches _streamArrow(String operation, Map<String, dynamic> start) async* {
    final input = _DatasetArrowReadInputStream(start: start);
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
          throw RoomServerException("unexpected return type from datasets.$operation call");
        }
        if (chunk is! BinaryContent || chunk.headers["kind"] != "data") {
          throw RoomServerException("unexpected return type from datasets.$operation call");
        }
        yield ArrowRecordBatch(chunk.data);
        input.requestNext();
      }
    } finally {
      input.close();
    }
  }

  Stream<DatasetTableWatchEvent> watchTable({
    required String table,
    List<String>? namespace,
    String? branch,
    double pollIntervalSeconds = 0.5,
  }) async* {
    final input = _DatasetArrowReadInputStream(
      start: {"kind": "start", "table": table, "namespace": namespace, "branch": branch, "poll_interval_seconds": pollIntervalSeconds},
    );
    final output = await _invokeStream("watch_table", input.inputStream());
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
          throw RoomServerException("unexpected return type from datasets.watch_table call");
        }
        if (chunk is BinaryContent && chunk.headers["kind"] == "data") {
          final batch = ArrowRecordBatch(chunk.data);
          yield DatasetTableWatchEvent(
            kind: chunk.headers["watch_event"] ?? "data",
            phase: _datasetWatchPhase(chunk.headers["phase"]),
            batch: batch,
            changeType: chunk.headers["change_type"],
            version: _intHeader(chunk.headers["version"]),
            beginVersion: _intHeader(chunk.headers["begin_version"]),
            endVersion: _intHeader(chunk.headers["end_version"]),
            transactions: chunk.headers["watch_event"] == "transactions" ? _transactionsFromWatchBatch(batch) : null,
          );
          input.requestNext();
          continue;
        }
        if (chunk is JsonContent) {
          final json = chunk.json;
          final rawTransactions = json["transactions"];
          final rawTransaction = json["transaction"];
          yield DatasetTableWatchEvent(
            kind: json["kind"]?.toString() ?? "event",
            phase: _datasetWatchPhase(json["phase"]),
            version: _intValue(json["version"]),
            beginVersion: _intValue(json["begin_version"]),
            endVersion: _intValue(json["end_version"]),
            transactions: rawTransactions is List
                ? rawTransactions.whereType<Map>().map((value) => Map<String, Object?>.from(value)).toList(growable: false)
                : null,
            deletePredicate: json["predicate"]?.toString(),
            transaction: rawTransaction is Map ? Map<String, Object?>.from(rawTransaction) : null,
          );
          input.requestNext();
          continue;
        }
        throw RoomServerException("unexpected return type from datasets.watch_table call");
      }
    } finally {
      input.close();
    }
  }

  Future<List<String>> listTables({List<String>? namespace, String? branch}) async {
    final response = await _invoke("list_tables", {"namespace": namespace, "branch": branch});
    if (response is! JsonContent) {
      throw RoomServerException("unexpected return type from datasets.list_tables call");
    }

    final tables = response.json["tables"] as List<dynamic>? ?? [];
    return tables.map((e) => e.toString()).toList(growable: false);
  }

  Future<void> _createTable({
    required String name,
    DatasetRowChunks? data,
    CreateMode mode = CreateMode.create,
    List<String>? namespace,
    String? branch,
    Map<String, dynamic>? metadata,
  }) async {
    final input = _DatasetWriteInputStream(
      start: {
        "kind": "start",
        "name": name,
        "mode": mode.value,
        "namespace": namespace,
        "branch": branch,
        "metadata": _metadataEntries(metadata),
      },
      chunks: data ?? Stream<DatasetRows>.empty(),
    );
    await _drainWriteStream("create_table", input);
  }

  Future<void> createTableWithSchema({
    required String name,
    required ArrowSchema schema,
    CreateMode mode = CreateMode.create,
    List<String>? namespace,
    String? branch,
    Map<String, dynamic>? metadata,
  }) {
    return createTableWithArrowSchema(name: name, schema: schema, mode: mode, namespace: namespace, branch: branch, metadata: metadata);
  }

  Future<void> createTableFromData({
    required String name,
    required DatasetRows data,
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
    required DatasetRowChunks chunks,
    CreateMode mode = CreateMode.create,
    List<String>? namespace,
    String? branch,
    Map<String, dynamic>? metadata,
  }) {
    return _createTable(name: name, data: chunks, mode: mode, namespace: namespace, branch: branch, metadata: metadata);
  }

  Future<void> createTableWithArrowSchema({
    required String name,
    required ArrowSchema schema,
    DatasetArrowBatches? batches,
    CreateMode mode = CreateMode.create,
    List<String>? namespace,
    String? branch,
    Map<String, dynamic>? metadata,
  }) async {
    final input = _DatasetArrowWriteInputStream(
      start: {
        "kind": "start",
        "name": name,
        "mode": mode.value,
        "namespace": namespace,
        "branch": branch,
        "metadata": _metadataEntries(metadata),
      },
      chunks: batches ?? const Stream<ArrowRecordBatch>.empty(),
      schema: schema,
    );
    await _drainArrowWriteStream("create_table", input);
  }

  Future<void> createTableFromArrowBatches({
    required String name,
    required DatasetArrowBatches batches,
    CreateMode mode = CreateMode.create,
    List<String>? namespace,
    String? branch,
    Map<String, dynamic>? metadata,
  }) async {
    final input = _DatasetArrowWriteInputStream(
      start: {
        "kind": "start",
        "name": name,
        "mode": mode.value,
        "namespace": namespace,
        "branch": branch,
        "metadata": _metadataEntries(metadata),
      },
      chunks: batches,
    );
    await _drainArrowWriteStream("create_table", input);
  }

  Future<void> createTableFromArrowTable({
    required String name,
    required ArrowTable table,
    CreateMode mode = CreateMode.create,
    List<String>? namespace,
    String? branch,
    Map<String, dynamic>? metadata,
  }) {
    return createTableWithArrowSchema(
      name: name,
      schema: table.schema,
      batches: Stream.fromIterable(table.batches),
      mode: mode,
      namespace: namespace,
      branch: branch,
      metadata: metadata,
    );
  }

  Future<void> dropTable({required String name, bool ignoreMissing = false, List<String>? namespace, String? branch}) async {
    await _invoke("drop_table", {"name": name, "ignore_missing": ignoreMissing, "namespace": namespace, "branch": branch});
  }

  Future<void> importFromStorage({
    required String table,
    required String path,
    DatasetImportMode mode = DatasetImportMode.create,
    DatasetStorageFormat format = DatasetStorageFormat.auto,
    String? on,
    String? sheet,
    int? batchSize,
    List<String>? namespace,
    String? branch,
  }) async {
    final input = {
      "table": table,
      "path": path,
      "mode": mode.value,
      "format": format.value,
      "on": on,
      "sheet": sheet,
      "namespace": namespace,
      "branch": branch,
    };
    if (batchSize != null) {
      input["batch_size"] = batchSize;
    }
    await _invoke("import_storage", input);
  }

  Future<void> exportToStorage({
    required String table,
    required String path,
    required DatasetStorageFormat format,
    List<String>? namespace,
    String? branch,
    int? version,
  }) async {
    await _invoke("export_storage", {
      "table": table,
      "path": path,
      "format": format.value,
      "namespace": namespace,
      "branch": branch,
      "version": version,
    });
  }

  Future<void> addColumnWithExpression({
    required String table,
    required Map<String, String> newColumns,
    List<String>? namespace,
    String? branch,
  }) async {
    await _invoke("add_columns", {
      "table": table,
      "columns": newColumns.entries.map((entry) => {"name": entry.key, "value_sql": entry.value}).toList(growable: false),
      "namespace": namespace,
      "branch": branch,
    });
  }

  Future<void> addColumnsWithSchema({required String table, required ArrowSchema schema, List<String>? namespace, String? branch}) async {
    final output = await _invokeContent(
      "add_columns",
      BinaryContent(
        data: ArrowIpcSchema.fromSchema(schema).bytes,
        headers: {"table": table, "namespace": namespace, "branch": branch, "content_type": _arrowIpcStreamMimeType},
      ),
    );
    if (output is! EmptyContent) {
      throw RoomServerException("unexpected return type from datasets.add_columns call");
    }
  }

  Future<void> dropColumns({required String table, required List<String> columns, List<String>? namespace, String? branch}) async {
    await _invoke("drop_columns", {"table": table, "columns": columns, "namespace": namespace, "branch": branch});
  }

  Future<void> updateColumnMetadata({
    required String table,
    required String column,
    required Map<String, String> metadata,
    List<String>? namespace,
    String? branch,
  }) async {
    await _invoke("update_column_metadata", {
      "table": table,
      "column": column,
      "metadata": _metadataEntries(metadata),
      "namespace": namespace,
      "branch": branch,
    });
  }

  Future<void> dropIndex({required String table, required String name, List<String>? namespace, String? branch}) async {
    await _invoke("drop_index", {"table": table, "name": name, "namespace": namespace, "branch": branch});
  }

  Future<void> insert({required String table, required ArrowRecordBatch records, List<String>? namespace, String? branch}) async {
    await insertStream(table: table, chunks: Stream.fromIterable([records]), namespace: namespace, branch: branch);
  }

  Future<void> insertTable({required String table, required ArrowTable records, List<String>? namespace, String? branch}) async {
    await insertStream(table: table, chunks: Stream.fromIterable(records.batches), namespace: namespace, branch: branch);
  }

  Future<void> insertStream({required String table, required DatasetArrowBatches chunks, List<String>? namespace, String? branch}) async {
    final input = _DatasetArrowWriteInputStream(
      start: {"kind": "start", "table": table, "namespace": namespace, "branch": branch},
      chunks: chunks,
    );
    await _drainArrowWriteStream("insert", input);
  }

  Future<void> update({
    required String table,
    required String where,
    required DatasetRecord values,
    List<String>? namespace,
    String? branch,
  }) async {
    await _invoke("update", {
      "table": table,
      "where": where,
      "values": values.entries.map((entry) => {"column": entry.key, "value_json": _valueJson(entry.value)}).toList(growable: false),
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
    required ArrowRecordBatch records,
    List<String>? namespace,
    String? branch,
  }) async {
    await mergeStream(table: table, on: on, chunks: Stream.fromIterable([records]), namespace: namespace, branch: branch);
  }

  Future<void> mergeTable({
    required String table,
    required String on,
    required ArrowTable records,
    List<String>? namespace,
    String? branch,
  }) async {
    await mergeStream(table: table, on: on, chunks: Stream.fromIterable(records.batches), namespace: namespace, branch: branch);
  }

  Future<void> mergeStream({
    required String table,
    required String on,
    required DatasetArrowBatches chunks,
    List<String>? namespace,
    String? branch,
  }) async {
    final input = _DatasetArrowWriteInputStream(
      start: {"kind": "start", "table": table, "on": on, "namespace": namespace, "branch": branch},
      chunks: chunks,
    );
    await _drainArrowWriteStream("merge", input);
  }

  Future<List<ArrowRecordBatch>> sql({
    required String query,
    List<TableRef>? tables,
    ArrowTable? params,
    List<String>? namespace,
    String? branch,
  }) async {
    final rows = <ArrowRecordBatch>[];
    await for (final chunk in sqlStream(query: query, tables: tables, params: params, namespace: namespace, branch: branch)) {
      rows.add(chunk);
    }
    return rows;
  }

  Future<ArrowTable> sqlTable({
    required String query,
    List<TableRef>? tables,
    ArrowTable? params,
    List<String>? namespace,
    String? branch,
  }) async {
    return _tableFromBatches(await sql(query: query, tables: tables, params: params, namespace: namespace, branch: branch));
  }

  Future<DatasetSqlQuery> openSqlQuery({
    required String query,
    List<TableRef>? tables,
    ArrowTable? params,
    List<String>? namespace,
    String? branch,
  }) async {
    final response = await _invokeContent(
      "open_sql_query",
      BinaryContent(
        data: params == null ? Uint8List(0) : ArrowIpcStreamWriter.fromTable(params).write(),
        headers: {
          "query": query,
          "tables": (tables ?? const <TableRef>[]).map((table) => table.toJson()).toList(growable: false),
          "namespace": namespace,
          "branch": branch,
        },
      ),
    );
    if (response is! BinaryContent) {
      throw RoomServerException("unexpected return type from datasets.open_sql_query call");
    }
    final queryId = response.headers["query_id"];
    if (queryId is! String || queryId.isEmpty) {
      throw RoomServerException("unexpected return type from datasets.open_sql_query call");
    }
    return DatasetSqlQuery(schema: ArrowIpcSchema(response.data).schema, queryId: queryId);
  }

  Future<DatasetSqlExecution> executeSql({
    required String query,
    List<TableRef>? tables,
    ArrowTable? params,
    List<String>? namespace,
    String? branch,
  }) async {
    final response = await _invokeContent(
      "execute_sql",
      BinaryContent(
        data: params == null ? Uint8List(0) : ArrowIpcStreamWriter.fromTable(params).write(),
        headers: {
          "query": query,
          "tables": (tables ?? const <TableRef>[]).map((table) => table.toJson()).toList(growable: false),
          "namespace": namespace,
          "branch": branch,
        },
      ),
    );
    if (response is BinaryContent) {
      if (response.headers["kind"] != "query") {
        throw RoomServerException("unexpected return type from datasets.execute_sql call");
      }
      final queryId = response.headers["query_id"];
      if (queryId is! String || queryId.isEmpty) {
        throw RoomServerException("unexpected return type from datasets.execute_sql call");
      }
      return DatasetSqlQuery(schema: ArrowIpcSchema(response.data).schema, queryId: queryId);
    }
    if (response is JsonContent) {
      if (response.json["kind"] != "statement") {
        throw RoomServerException("unexpected return type from datasets.execute_sql call");
      }
      final rowsAffected = response.json["rows_affected"];
      if (rowsAffected is! int) {
        throw RoomServerException("unexpected return type from datasets.execute_sql call");
      }
      return DatasetSqlStatement(rowsAffected: rowsAffected);
    }
    throw RoomServerException("unexpected return type from datasets.execute_sql call");
  }

  DatasetArrowBatches sqlStream({
    required String query,
    List<TableRef>? tables,
    ArrowTable? params,
    List<String>? namespace,
    String? branch,
  }) {
    return (() async* {
      final result = await executeSql(query: query, tables: tables, params: params, namespace: namespace, branch: branch);
      if (result is DatasetSqlStatement) {
        throw RoomServerException("SQL statement did not return rows; rows_affected=${result.rowsAffected}");
      }
      final opened = result as DatasetSqlQuery;
      try {
        yield* readSqlQuery(queryId: opened.queryId);
      } finally {
        await closeSqlQuery(queryId: opened.queryId);
      }
    })();
  }

  DatasetArrowBatches readSqlQuery({required String queryId}) {
    return _streamArrow("read_sql_query", {"kind": "start", "query_id": queryId});
  }

  Future<void> closeSqlQuery({required String queryId}) async {
    final response = await _invoke("close_sql_query", {"query_id": queryId});
    if (response is! EmptyContent) {
      throw RoomServerException("unexpected return type from datasets.close_sql_query call");
    }
  }

  Future<DatasetSqlCancelResult> cancelSqlQuery({required String queryId}) async {
    final response = await _invoke("cancel_sql_query", {"query_id": queryId});
    if (response is! JsonContent) {
      throw RoomServerException("unexpected return type from datasets.cancel_sql_query call");
    }
    final status = response.json["status"];
    return DatasetSqlCancelResult(
      status: switch (status) {
        "cancelled" => DatasetSqlCancelStatus.cancelled,
        "cancelling" => DatasetSqlCancelStatus.cancelling,
        "not_cancellable" => DatasetSqlCancelStatus.notCancellable,
        _ => throw RoomServerException("unexpected return type from datasets.cancel_sql_query call"),
      },
    );
  }

  Future<int> executeSqlStatement({
    required String query,
    List<TableRef>? tables,
    ArrowTable? params,
    List<String>? namespace,
    String? branch,
  }) async {
    final response = await _invokeContent(
      "execute_sql_statement",
      BinaryContent(
        data: params == null ? Uint8List(0) : ArrowIpcStreamWriter.fromTable(params).write(),
        headers: {
          "query": query,
          "tables": (tables ?? const <TableRef>[]).map((table) => table.toJson()).toList(growable: false),
          "namespace": namespace,
          "branch": branch,
        },
      ),
    );
    if (response is! JsonContent) {
      throw RoomServerException("unexpected return type from datasets.execute_sql_statement call");
    }
    final rowsAffected = response.json["rows_affected"];
    if (rowsAffected is! int) {
      throw RoomServerException("unexpected return type from datasets.execute_sql_statement call");
    }
    return rowsAffected;
  }

  Future<List<ArrowRecordBatch>> search({
    required String table,
    String? text,
    List<double>? vector,
    Object? where,
    int? offset,
    int? limit,
    List<String>? select,
    List<String>? namespace,
    String? branch,
    int? version,
  }) async {
    final rows = <ArrowRecordBatch>[];
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
      rows.add(chunk);
    }
    return rows;
  }

  Future<ArrowTable> searchTable({
    required String table,
    String? text,
    List<double>? vector,
    Object? where,
    int? offset,
    int? limit,
    List<String>? select,
    List<String>? namespace,
    String? branch,
    int? version,
  }) async {
    return _tableFromBatches(
      await search(
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
      ),
    );
  }

  DatasetArrowBatches searchStream({
    required String table,
    String? text,
    List<double>? vector,
    Object? where,
    int? offset,
    int? limit,
    List<String>? select,
    List<String>? namespace,
    String? branch,
    int? version,
  }) {
    return _streamArrow("search", {
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
    Object? where,
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
      throw RoomServerException("unexpected return type from datasets.count call");
    }
    final count = response.json["count"];
    if (count is! num) {
      throw RoomServerException("unexpected return type from datasets.count call");
    }
    return count.toInt();
  }

  Future<DatasetOptimizeResult> optimize({
    required String table,
    List<String>? namespace,
    String? branch,
    DatasetOptimizeConfig? config,
  }) async {
    final response = await _invoke("optimize", {"table": table, "namespace": namespace, "branch": branch, "config": config?.toJson()});
    if (response is! JsonContent) {
      throw RoomServerException("unexpected return type from datasets.optimize call");
    }
    return DatasetOptimizeResult.fromJson(response.json);
  }

  Future<DatasetTableStats> stats(String table, {List<String>? namespace, String? branch, int? version, int? maxRowsPerGroup}) async {
    final response = await _invoke("stats", {
      "table": table,
      "namespace": namespace,
      "branch": branch,
      "version": version,
      "max_rows_per_group": maxRowsPerGroup,
    });
    if (response is! JsonContent) {
      throw RoomServerException("unexpected return type from datasets.stats call");
    }
    return DatasetTableStats.fromJson(response.json);
  }

  Future<void> restore({required String table, required int version, List<String>? namespace, String? branch}) async {
    await _invoke("restore", {"table": table, "version": version, "namespace": namespace, "branch": branch});
  }

  Future<ArrowSchema> inspect(String table, {List<String>? namespace, String? branch, int? version}) async {
    final response = await _invoke("inspect", {"table": table, "namespace": namespace, "branch": branch, "version": version});
    if (response is! BinaryContent) {
      throw RoomServerException("unexpected return type from datasets.inspect call: ${response.runtimeType}");
    }
    return ArrowIpcSchema(response.data).schema;
  }

  Future<List<TableVersion>> listVersions(String table, {List<String>? namespace, String? branch}) async {
    final response = await _invoke("list_versions", {"table": table, "namespace": namespace, "branch": branch});
    if (response is! JsonContent) {
      throw RoomServerException("unexpected return type from datasets.list_versions call");
    }
    final versions = response.json["versions"];
    if (versions is! List) {
      throw RoomServerException("unexpected return type from datasets.list_versions call");
    }
    return versions
        .map((value) {
          if (value is! Map) {
            throw RoomServerException("unexpected return type from datasets.list_versions call");
          }
          final metadataJson = value["metadata_json"];
          if (metadataJson is! String) {
            throw RoomServerException("unexpected return type from datasets.list_versions call");
          }
          final metadata = jsonDecode(metadataJson);
          if (metadata is! Map) {
            throw RoomServerException("unexpected return type from datasets.list_versions call");
          }
          return TableVersion(
            version: (value["version"] as num).toInt(),
            timestamp: DateTime.parse(value["timestamp"] as String),
            metadata: Map<String, dynamic>.from(metadata),
          );
        })
        .toList(growable: false);
  }

  Future<void> createIndex({required String table, required DatasetIndexConfig config, List<String>? namespace, String? branch}) async {
    await _invoke("create_index", {"table": table, "config": config.toJson(), "namespace": namespace, "branch": branch});
  }

  Future<List<TableIndex>> listIndexes(String table, {List<String>? namespace, String? branch, int? version}) async {
    final response = await _invoke("list_indexes", {"table": table, "namespace": namespace, "branch": branch, "version": version});
    if (response is! JsonContent) {
      throw RoomServerException("unexpected return type from datasets.list_indexes call");
    }
    final indexes = response.json["indexes"];
    if (indexes is! List) {
      throw RoomServerException("unexpected return type from datasets.list_indexes call");
    }
    return indexes.map((value) => TableIndex.fromJson(Map<String, dynamic>.from(value as Map))).toList(growable: false);
  }

  Future<List<TableBranch>> listBranches({List<String>? namespace}) async {
    final response = await _invoke("list_branches", {"namespace": namespace});
    if (response is! JsonContent) {
      throw RoomServerException("unexpected return type from datasets.list_branches call");
    }
    final branches = response.json["branches"];
    if (branches is! List) {
      throw RoomServerException("unexpected return type from datasets.list_branches call");
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
  const TableIndex({
    required this.columns,
    required this.type,
    required this.name,
    this.fields = const [],
    this.typeUrl,
    this.numRowsIndexed,
    this.numSegments,
    this.totalSizeBytes,
    this.details = const {},
    this.statistics = const {},
  });

  final List<String> columns;
  final String name;
  final String type;
  final List<int> fields;
  final String? typeUrl;
  final int? numRowsIndexed;
  final int? numSegments;
  final int? totalSizeBytes;
  final Map<String, dynamic> details;
  final Map<String, dynamic> statistics;

  static TableIndex fromJson(Map<String, dynamic> json) {
    final detailsJson = json["details_json"];
    final statisticsJson = json["statistics_json"];
    return TableIndex(
      columns: [...json["columns"]],
      type: json["type"],
      name: json["name"],
      fields: (json["fields"] as List? ?? const []).map((value) => (value as num).toInt()).toList(growable: false),
      typeUrl: json["type_url"] as String?,
      numRowsIndexed: (json["num_rows_indexed"] as num?)?.toInt(),
      numSegments: (json["num_segments"] as num?)?.toInt(),
      totalSizeBytes: (json["total_size_bytes"] as num?)?.toInt(),
      details: detailsJson is String
          ? Map<String, dynamic>.from(jsonDecode(detailsJson) as Map)
          : Map<String, dynamic>.from(json["details"] as Map? ?? const {}),
      statistics: statisticsJson is String
          ? Map<String, dynamic>.from(jsonDecode(statisticsJson) as Map)
          : Map<String, dynamic>.from(json["statistics"] as Map? ?? const {}),
    );
  }

  Map<String, Object?> toJson() {
    return {
      "name": name,
      "columns": columns,
      "type": type,
      "fields": fields,
      "type_url": typeUrl,
      "num_rows_indexed": numRowsIndexed,
      "num_segments": numSegments,
      "total_size_bytes": totalSizeBytes,
      "details": details,
      "statistics": statistics,
    };
  }
}

class DatasetOptimizeConfig {
  const DatasetOptimizeConfig({
    this.compactFiles = true,
    this.optimizeIndices = true,
    this.cleanupOldVersions = false,
    this.targetRowsPerFragment,
    this.maxRowsPerGroup,
    this.maxBytesPerFile,
    this.materializeDeletions,
    this.materializeDeletionsThreshold,
    this.deferIndexRemap,
    this.numThreads,
    this.batchSize,
    this.compactionMode,
    this.binaryCopyReadBatchBytes,
    this.numIndicesToMerge,
    this.indexNames,
    this.retrain,
    this.olderThanSeconds = 604800,
    this.retainVersions,
    this.deleteUnverified,
    this.errorIfTaggedOldVersions,
    this.deleteRateLimit,
  });

  final bool? compactFiles;
  final bool? optimizeIndices;
  final bool? cleanupOldVersions;
  final int? targetRowsPerFragment;
  final int? maxRowsPerGroup;
  final int? maxBytesPerFile;
  final bool? materializeDeletions;
  final double? materializeDeletionsThreshold;
  final bool? deferIndexRemap;
  final int? numThreads;
  final int? batchSize;
  final String? compactionMode;
  final int? binaryCopyReadBatchBytes;
  final int? numIndicesToMerge;
  final List<String>? indexNames;
  final bool? retrain;
  final double? olderThanSeconds;
  final int? retainVersions;
  final bool? deleteUnverified;
  final bool? errorIfTaggedOldVersions;
  final int? deleteRateLimit;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    void add(String key, Object? value) {
      if (value != null) json[key] = value;
    }

    add("compact_files", compactFiles);
    add("optimize_indices", optimizeIndices);
    add("cleanup_old_versions", cleanupOldVersions);
    add("target_rows_per_fragment", targetRowsPerFragment);
    add("max_rows_per_group", maxRowsPerGroup);
    add("max_bytes_per_file", maxBytesPerFile);
    add("materialize_deletions", materializeDeletions);
    add("materialize_deletions_threshold", materializeDeletionsThreshold);
    add("defer_index_remap", deferIndexRemap);
    add("num_threads", numThreads);
    add("batch_size", batchSize);
    add("compaction_mode", compactionMode);
    add("binary_copy_read_batch_bytes", binaryCopyReadBatchBytes);
    add("num_indices_to_merge", numIndicesToMerge);
    add("index_names", indexNames);
    add("retrain", retrain);
    add("older_than_seconds", olderThanSeconds);
    add("retain_versions", retainVersions);
    add("delete_unverified", deleteUnverified);
    add("error_if_tagged_old_versions", errorIfTaggedOldVersions);
    add("delete_rate_limit", deleteRateLimit);
    return json;
  }
}

class DatasetOptimizeResult {
  const DatasetOptimizeResult({this.compaction, required this.optimizedIndices, this.cleanup});

  final Map<String, dynamic>? compaction;
  final bool optimizedIndices;
  final Map<String, dynamic>? cleanup;

  static DatasetOptimizeResult fromJson(Map<String, dynamic> json) {
    final compactionJson = json["compaction_json"];
    final cleanupJson = json["cleanup_json"];
    return DatasetOptimizeResult(
      compaction: compactionJson is String
          ? Map<String, dynamic>.from(jsonDecode(compactionJson) as Map)
          : json["compaction"] == null
          ? null
          : Map<String, dynamic>.from(json["compaction"] as Map),
      optimizedIndices: json["optimized_indices"] as bool? ?? false,
      cleanup: cleanupJson is String
          ? Map<String, dynamic>.from(jsonDecode(cleanupJson) as Map)
          : json["cleanup"] == null
          ? null
          : Map<String, dynamic>.from(json["cleanup"] as Map),
    );
  }

  Map<String, Object?> toJson() => {"compaction": compaction, "optimized_indices": optimizedIndices, "cleanup": cleanup};
}

class DatasetTableStats {
  const DatasetTableStats({required this.dataset, required this.data});

  final Map<String, dynamic> dataset;
  final Map<String, dynamic> data;

  static DatasetTableStats fromJson(Map<String, dynamic> json) {
    final datasetJson = json["dataset_json"];
    final dataJson = json["data_json"];
    return DatasetTableStats(
      dataset: datasetJson is String
          ? Map<String, dynamic>.from(jsonDecode(datasetJson) as Map)
          : Map<String, dynamic>.from(json["dataset"] as Map),
      data: dataJson is String ? Map<String, dynamic>.from(jsonDecode(dataJson) as Map) : Map<String, dynamic>.from(json["data"] as Map),
    );
  }

  Map<String, Object?> toJson() => {"dataset": dataset, "data": data};
}

class DatasetIndexConfig {
  const DatasetIndexConfig({
    required this.column,
    required this.indexType,
    this.name,
    this.metric,
    this.replace,
    this.numPartitions,
    this.ivfCentroids,
    this.pqCodebook,
    this.numSubVectors,
    this.accelerator,
    this.indexCacheSize,
    this.shufflePartitionBatches,
    this.shufflePartitionConcurrency,
    this.ivfCentroidsFile,
    this.precomputedPartitionDataset,
    this.filterNan,
    this.train,
    this.fragmentIds,
    this.indexUuid,
    this.targetPartitionSize,
    this.skipTranspose,
    this.numBits,
    this.indexFileVersion,
    this.maxLevel,
    this.m,
    this.efConstruction,
    this.withPosition,
    this.memoryLimit,
    this.numWorkers,
    this.skipMerge,
    this.baseTokenizer,
    this.language,
    this.maxTokenLength,
    this.lowerCase,
    this.stem,
    this.removeStopWords,
    this.customStopWords,
    this.asciiFolding,
  });

  final Object column;
  final String indexType;
  final String? name;
  final String? metric;
  final bool? replace;
  final int? numPartitions;
  final List<List<double>>? ivfCentroids;
  final List<List<double>>? pqCodebook;
  final int? numSubVectors;
  final String? accelerator;
  final int? indexCacheSize;
  final int? shufflePartitionBatches;
  final int? shufflePartitionConcurrency;
  final String? ivfCentroidsFile;
  final String? precomputedPartitionDataset;
  final bool? filterNan;
  final bool? train;
  final List<int>? fragmentIds;
  final String? indexUuid;
  final int? targetPartitionSize;
  final bool? skipTranspose;
  final int? numBits;
  final String? indexFileVersion;
  final int? maxLevel;
  final int? m;
  final int? efConstruction;
  final bool? withPosition;
  final int? memoryLimit;
  final int? numWorkers;
  final bool? skipMerge;
  final String? baseTokenizer;
  final String? language;
  final int? maxTokenLength;
  final bool? lowerCase;
  final bool? stem;
  final bool? removeStopWords;
  final List<String>? customStopWords;
  final bool? asciiFolding;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'column': column, 'index_type': indexType};
    void add(String key, Object? value) {
      if (value != null) json[key] = value;
    }

    add('name', name);
    add('metric', metric);
    add('replace', replace);
    add('num_partitions', numPartitions);
    add('ivf_centroids', ivfCentroids);
    add('pq_codebook', pqCodebook);
    add('num_sub_vectors', numSubVectors);
    add('accelerator', accelerator);
    add('index_cache_size', indexCacheSize);
    add('shuffle_partition_batches', shufflePartitionBatches);
    add('shuffle_partition_concurrency', shufflePartitionConcurrency);
    add('ivf_centroids_file', ivfCentroidsFile);
    add('precomputed_partition_dataset', precomputedPartitionDataset);
    add('filter_nan', filterNan);
    add('train', train);
    add('fragment_ids', fragmentIds);
    add('index_uuid', indexUuid);
    add('target_partition_size', targetPartitionSize);
    add('skip_transpose', skipTranspose);
    add('num_bits', numBits);
    add('index_file_version', indexFileVersion);
    add('max_level', maxLevel);
    add('m', m);
    add('ef_construction', efConstruction);
    add('with_position', withPosition);
    add('memory_limit', memoryLimit);
    add('num_workers', numWorkers);
    add('skip_merge', skipMerge);
    add('base_tokenizer', baseTokenizer);
    add('language', language);
    add('max_token_length', maxTokenLength);
    add('lower_case', lowerCase);
    add('stem', stem);
    add('remove_stop_words', removeStopWords);
    add('custom_stop_words', customStopWords);
    add('ascii_folding', asciiFolding);
    return json;
  }
}

Object? _decodeRecordValue(Object? value) {
  if (value is List) {
    throw RoomServerException("dataset list values must use a {'list': [...]} wrapper");
  }

  if (value is Map<String, dynamic>) {
    if (value.length != 1) {
      throw RoomServerException("dataset object values must use a single-key type wrapper");
    }
    final entry = value.entries.single;
    switch (entry.key) {
      case "binary":
        if (entry.value is! String) {
          throw RoomServerException("dataset binary values must be base64 strings");
        }
        return base64Decode(entry.value as String);
      case "uuid":
        if (entry.value is! String) {
          throw RoomServerException("dataset uuid values must be strings");
        }
        return UuidValue.withValidation(entry.value as String);
      case "expression":
        if (entry.value is! String) {
          throw RoomServerException("dataset expression values must be strings");
        }
        return DatasetExpression(entry.value as String);
      case "date":
        if (entry.value is! String) {
          throw RoomServerException("dataset date values must be strings");
        }
        return DatasetDate(entry.value as String);
      case "timestamp":
        if (entry.value is! String) {
          throw RoomServerException("dataset timestamp values must be strings");
        }
        return DateTime.parse(entry.value as String);
      case "list":
        if (entry.value is! List) {
          throw RoomServerException("dataset list values must be arrays");
        }
        return (entry.value as List).map(_decodeRecordValue).toList(growable: false);
      case "struct":
        if (entry.value is! Map<String, dynamic>) {
          throw RoomServerException("dataset struct values must be objects");
        }
        return DatasetStruct((entry.value as Map<String, dynamic>).map((key, innerValue) => MapEntry(key, _decodeRecordValue(innerValue))));
      case "json":
        return DatasetJson(entry.value);
      default:
        throw RoomServerException("unsupported dataset value wrapper '${entry.key}'");
    }
  }

  return value;
}

DatasetRows decodeRecords(DatasetRows records) {
  for (final record in records) {
    for (final key in record.keys.toList()) {
      record[key] = _decodeRecordValue(record[key]);
    }
  }
  return records;
}

DatasetTableWatchPhase _datasetWatchPhase(Object? value) {
  return value?.toString() == "delta" ? DatasetTableWatchPhase.delta : DatasetTableWatchPhase.initial;
}

List<Map<String, Object?>> _transactionsFromWatchBatch(ArrowRecordBatch batch) {
  final transactions = <Map<String, Object?>>[];
  for (final row in batch.toRows()) {
    final transactionJson = row["transaction_json"];
    if (transactionJson is String && transactionJson.isNotEmpty) {
      final decoded = jsonDecode(transactionJson);
      if (decoded is Map) {
        transactions.add(Map<String, Object?>.from(decoded));
        continue;
      }
    }
    transactions.add(Map<String, Object?>.from(row));
  }
  return transactions;
}

int? _intHeader(Object? value) {
  if (value == null) {
    return null;
  }
  return int.tryParse(value.toString());
}

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value == null) {
    return null;
  }
  return int.tryParse(value.toString());
}

Object? _encodeRecordValue(Object? value) {
  if (value is DatasetValueEncoder) {
    return value.encodeDatasetValue();
  }
  if (value is UuidValue) {
    return {"uuid": value.toFormattedString(validate: true)};
  }
  if (value is Uint8List) {
    return {"binary": base64Encode(value)};
  }
  if (value is DateTime) {
    final normalized = value.isUtc ? value : value.toUtc();
    return {"timestamp": normalized.toIso8601String().replaceFirst("+00:00", "Z")};
  }
  if (value is List) {
    return {"list": value.map(_encodeRecordValue).toList(growable: false)};
  }
  if (value is Map<String, dynamic>) {
    throw RoomServerException("dataset object values must use DatasetStruct or DatasetJson");
  }
  return value;
}

DatasetRows encodeRecords(DatasetRows records) {
  return records.map((record) => record.map((key, value) => MapEntry(key, _encodeRecordValue(value)))).toList(growable: false);
}
