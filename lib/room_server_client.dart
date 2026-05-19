import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:logging/logging.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent/queues_client.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:meshagent/yaml/yaml.dart';

import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import 'runtime.dart';
import 'src/websocket_connect_status_stub.dart' if (dart.library.io) 'src/websocket_connect_status_io.dart' as websocket_connect_status;

final Logger _roomClientLogger = Logger('room_server_client');

class RoomServerException implements Exception {
  RoomServerException(this.message, {this.statusCode, this.code, this.retryable = false});

  final String message;
  final int? statusCode;
  final int? code;
  final bool retryable;

  @override
  String toString() {
    return message;
  }
}

String _websocketConnectFailureMessage(int statusCode) {
  final statusText = switch (statusCode) {
    403 => 'Forbidden',
    404 => 'Not Found',
    408 => 'Request Timeout',
    429 => 'Too Many Requests',
    502 => 'Bad Gateway',
    503 => 'Service Unavailable',
    504 => 'Gateway Timeout',
    _ => null,
  };
  if (statusText == null) {
    return 'websocket connect failed with status $statusCode';
  }
  return 'websocket connect failed with status $statusCode: $statusText';
}

bool _isRetryableConnectStatusCode(int statusCode) {
  return statusCode == 408 || statusCode == 429 || statusCode >= 500;
}

RoomServerException _wrapRoomConnectionError(Object? error) {
  if (error is RoomServerException) {
    return error;
  }
  final connectStatusCode = websocket_connect_status.websocketConnectStatusCode(error);
  if (connectStatusCode != null) {
    return RoomServerException(
      _websocketConnectFailureMessage(connectStatusCode),
      statusCode: connectStatusCode,
      retryable: _isRetryableConnectStatusCode(connectStatusCode),
    );
  }
  if (error is ProtocolCloseException) {
    final reason = error.reason;
    return RoomServerException(
      reason == null || reason.isEmpty ? 'room connection closed with status ${error.closeCode}' : reason,
      statusCode: error.closeCode,
      retryable: error.closeCode == 1013,
    );
  }
  return RoomServerException("room connection error: $error");
}

String? _nonRetryableConnectFailureReason(Object error) {
  if (error is RoomServerException && (error.statusCode == 403 || error.statusCode == 404)) {
    final normalizedMessage = error.message.trim();
    if (normalizedMessage.isNotEmpty) {
      return normalizedMessage;
    }
    return _websocketConnectFailureMessage(error.statusCode!);
  }
  return null;
}

bool _isRetryableStartupClose({required ProtocolCloseKind kind, required String? reason}) {
  if (kind == ProtocolCloseKind.error || kind == ProtocolCloseKind.server) {
    return true;
  }
  return (reason ?? '').toLowerCase().contains('1013');
}

RoomServerException _roomClosedBeforeReadyError(Protocol protocol) {
  final channel = protocol.channel;
  if (channel is WebSocketProtocolChannel) {
    final closeCode = channel.webSocket?.closeCode;
    if (closeCode != null && closeCode != ws_status.normalClosure) {
      final closeReason = channel.webSocket?.closeReason;
      return RoomServerException(
        closeReason == null || closeReason.isEmpty ? 'room connection closed with status $closeCode' : closeReason,
        statusCode: closeCode,
        retryable: closeCode == 1013,
      );
    }
  }

  return RoomServerException("room connection closed before request completed", retryable: true);
}

abstract class Participant extends ChangeEmitter {
  Participant({required this.client, required this.id});

  final RoomClient client;
  String id;
  final Map<String, dynamic> _attributes = {};

  final List<String> _connections = [];

  Iterable<String> get connections {
    return _connections;
  }

  dynamic getAttribute(String name) {
    return _attributes[name];
  }

  bool _hasSameAttributes(Map<String, dynamic> attributes) {
    if (_attributes.length != attributes.length) {
      return false;
    }

    for (final entry in attributes.entries) {
      if (!_attributes.containsKey(entry.key) || _attributes[entry.key] != entry.value) {
        return false;
      }
    }

    return true;
  }

  void _applyAttributes(Map<String, dynamic> attributes) {
    var changed = false;
    for (final entry in attributes.entries) {
      if (!_attributes.containsKey(entry.key) || _attributes[entry.key] != entry.value) {
        _attributes[entry.key] = entry.value;
        changed = true;
      }
    }

    if (changed) {
      notifyListeners();
    }
  }

  void _replaceIdentity({required String participantId, required Map<String, dynamic> attributes}) {
    final identityChanged = id != participantId;
    final attributesChanged = !_hasSameAttributes(attributes);
    if (!identityChanged && !attributesChanged) {
      return;
    }

    id = participantId;
    _attributes
      ..clear()
      ..addAll(attributes);
    notifyListeners();
  }
}

class RemoteParticipant extends Participant {
  RemoteParticipant({required super.client, required super.id, required this.role, this.online});

  final String role;
  bool? online;

  void _setOnline(bool online) {
    if (this.online == online) {
      return;
    }
    this.online = online;
    notifyListeners();
  }
}

class LocalParticipant extends Participant {
  LocalParticipant({required super.client, required super.id});

  void setAttribute(String name, dynamic value) {
    _applyAttributes({name: value});
    client._sendLocalAttributesNowait({name: value});
  }
}

Uint8List splitMessagePayload(Uint8List packet) {
  final data = packet.buffer.asByteData();
  final headerSize = data.getUint32(4).toInt() + (data.getUint32(0).toInt() << 32);
  final payload = Uint8List.sublistView(data, 8 + headerSize, packet.length);
  return payload;
}

String splitMessageHeader(Uint8List packet) {
  final data = packet.buffer.asByteData();
  final headerSize = data.getUint32(4).toInt() + (data.getUint32(0).toInt() << 32);

  final subList = Uint8List.sublistView(data, 8, 8 + headerSize);
  return utf8.decode(subList);
}

class Message {
  Message(this.header, this.payload);

  Map<String, dynamic> header;
  Uint8List payload;
}

Message unpackMessage(Uint8List message) {
  return Message(jsonDecode(splitMessageHeader(message)), splitMessagePayload(message));
}

Uint8List packMessage(Map<String, dynamic> header, [Uint8List? data]) {
  final jsonMessage = utf8.encode(jsonEncode(header));

  final size = jsonMessage.length;

  final packet = BytesBuilder();
  packet.add(
    Uint8List(8)
      ..buffer.asByteData().setUint32(0, size >> 32, Endian.big)
      ..buffer.asByteData().setUint32(4, size & 0xffffffff, Endian.big),
  );
  packet.add(jsonMessage);
  if (data != null) {
    packet.add(data);
  }
  return packet.toBytes();
}

class _PendingRequest {
  _PendingRequest();

  final _completer = Completer<Content>();

  Future<Content> get fut {
    return _completer.future;
  }
}

abstract class Requirement {
  Requirement({required this.name, this.callable = true});

  final bool callable;
  final String name;

  Map<String, dynamic> toJson();

  static Requirement fromJson(Map<String, dynamic> json) {
    if (json["toolkit"] != null) {
      return RequiredToolkit.fromJson(json);
    } else if (json["table"] != null) {
      return RequiredTable.fromJson(json);
    } else if (json["schema"] != null) {
      return RequiredSchema.fromJson(json);
    }
    throw Exception("Unexpected requirement");
  }
}

class RequiredSchema extends Requirement {
  RequiredSchema({required super.name});

  @override
  Map<String, dynamic> toJson() {
    return {"schema": name};
  }

  static RequiredSchema fromJson(Map<String, dynamic> json) {
    return RequiredSchema(name: "schema");
  }
}

class RequiredTable extends Requirement {
  RequiredTable({
    required super.name,
    required this.schema,
    this.namespace,
    this.scalarIndexes,
    this.fullTextSearchIndexes,
    this.vectorIndexes,
  });

  /// Arrow table schema.
  final ArrowSchema schema;

  /// Optional namespace path
  final List<String>? namespace;

  final List<String>? scalarIndexes;
  final List<String>? fullTextSearchIndexes;
  final List<String>? vectorIndexes;

  @override
  Map<String, dynamic> toJson() {
    return {
      'table': name,
      'schema': base64Encode(ArrowIpcSchema.fromSchema(schema).bytes),
      'namespace': namespace,
      'scalar_indexes': scalarIndexes,
      'full_text_search_indexes': fullTextSearchIndexes,
      'vector_indexes': vectorIndexes,
    };
  }

  static RequiredTable fromJson(Map<String, dynamic> json) {
    final rawSchema = json['schema'];
    if (rawSchema is! String) {
      throw RoomServerException("required table schema must be a base64 Arrow IPC schema");
    }

    return RequiredTable(
      name: json['table'] as String,
      schema: ArrowIpcSchema(Uint8List.fromList(base64Decode(rawSchema))).schema,
      namespace: (json['namespace'] as List?)?.cast<String>(),
      scalarIndexes: (json['scalar_indexes'] as List?)?.cast<String>(),
      fullTextSearchIndexes: (json['full_text_search_indexes'] as List?)?.cast<String>(),
      vectorIndexes: (json['vector_indexes'] as List?)?.cast<String>(),
    );
  }
}

class RequiredToolkit extends Requirement {
  // Required toolkits, set tools to null to require all the tools in the toolkit
  RequiredToolkit({required super.name, this.tools, this.participantName});

  final List<String>? tools;
  final String? participantName;

  @override
  Map<String, dynamic> toJson() {
    return {"toolkit": name, "tools": tools, "participant_name": participantName};
  }

  static RequiredToolkit fromJson(Map<String, dynamic> from) {
    return RequiredToolkit(
      name: from["toolkit"],
      tools: (from["tools"] as List?)?.whereType<String>().toList(),
      participantName: from["participant_name"],
    );
  }
}

abstract class RoomEvent {
  RoomEvent();

  String get name;
  String get description;
}

class RoomStatusEvent extends RoomEvent {
  RoomStatusEvent({required this.status, required this.message});

  @override
  String get name {
    return status;
  }

  @override
  String get description {
    return message;
  }

  final String message;
  final String status;

  static RoomStatusEvent fromJson(Map<String, dynamic> json) {
    return RoomStatusEvent(status: json["status"], message: json["message"]);
  }
}

class RoomMessage {
  RoomMessage({required this.fromParticipantId, required this.type, required this.message, this.local = false, this.attachment});

  final bool local;
  final String fromParticipantId;
  final String type;
  final Map<String, dynamic> message;
  final Uint8List? attachment;
}

class _QueuedRoomMessage extends RoomMessage {
  _QueuedRoomMessage({
    required super.fromParticipantId,
    required super.type,
    required super.message,
    super.attachment,
    required this.to,
    required this.dropIfOffline,
  }) : completer = dropIfOffline ? null : Completer<void>();

  final Participant? to;
  final bool dropIfOffline;
  final Completer<void>? completer;
}

class RoomMessageEvent extends RoomEvent {
  RoomMessageEvent({required this.message});

  final RoomMessage message;

  @override
  String get name {
    return message.type;
  }

  @override
  String get description {
    return "a message was received ${jsonEncode(message.message)}";
  }
}

class FileDeletedEvent extends RoomEvent {
  FileDeletedEvent({required this.path, required this.participantId});

  final String path;
  final String participantId;

  @override
  String get name => "file deleted";

  @override
  String get description => "a file was deleted at the path $path";
}

class FileUpdatedEvent extends RoomEvent {
  FileUpdatedEvent({required this.path, required this.participantId});

  final String path;
  final String participantId;

  @override
  String get name => "file updated";

  @override
  String get description => "a file was updated at the path $path";
}

class FileMovedEvent extends RoomEvent {
  FileMovedEvent({required this.sourcePath, required this.destinationPath, required this.participantId});

  final String sourcePath;
  final String destinationPath;
  final String participantId;

  @override
  String get name => "file moved";

  @override
  String get description => "a file was moved from $sourcePath to $destinationPath";
}

class RoomLogEvent extends RoomEvent {
  RoomLogEvent({required this.type, required this.data});

  final String type;
  final Map<String, dynamic> data;

  @override
  String get name => type;

  @override
  String get description => jsonEncode(data);

  static RoomLogEvent fromJson(Map<String, dynamic> json) {
    final type = json["type"];
    final data = json["data"];
    return RoomLogEvent(type: type, data: data);
  }
}

class _RefCount<T> {
  _RefCount(this.ref);

  T ref;
  int count = 1;
}

class _RoomClientTerminalState {
  const _RoomClientTerminalState({required this.requestMessage, required this.toolCallMessage, required this.messageSendMessage});

  final String requestMessage;
  final String toolCallMessage;
  final String messageSendMessage;

  RoomServerException requestError() {
    return RoomServerException(requestMessage);
  }

  RoomServerException toolCallError() {
    return RoomServerException(toolCallMessage);
  }

  RoomServerException messageSendError() {
    return RoomServerException(messageSendMessage);
  }
}

class _ProtocolStartupFailure implements Exception {
  _ProtocolStartupFailure({required this.kind, required this.reason});

  final ProtocolCloseKind kind;
  final String? reason;

  @override
  String toString() {
    return reason ?? kind.name;
  }
}

typedef _ProtocolConnectAttempt = Future<void> Function({required Protocol protocol, required Duration? remaining});

class _ProtocolRetryResult {
  const _ProtocolRetryResult({required this.connected, this.closeKind, this.closeReason});

  final bool connected;
  final ProtocolCloseKind? closeKind;
  final String? closeReason;
}

class RoomProtocolProxy {
  RoomProtocolProxy({required RoomClient room}) : _room = room;

  final RoomClient _room;
  final Map<String, ProtocolMessageHandler> _handlers = <String, ProtocolMessageHandler>{};

  void _bind(Protocol protocol) {
    for (final entry in _handlers.entries) {
      if (identical(protocol.getHandler(entry.key), entry.value)) {
        continue;
      }
      protocol.addHandler(entry.key, entry.value);
    }
  }

  void _unbind(Protocol protocol) {
    for (final entry in _handlers.entries) {
      final current = protocol.getHandler(entry.key);
      if (identical(current, entry.value)) {
        protocol.removeHandler(entry.key, current!);
      }
    }
  }

  void addHandler(String type, ProtocolMessageHandler handler) {
    if (_handlers.containsKey(type)) {
      throw StateError('already registered handler for $type');
    }
    _handlers[type] = handler;
    _bind(_room._protocolInstance);
  }

  void removeHandler(String type, ProtocolMessageHandler handler) {
    final registeredHandler = _handlers[type];
    if (!identical(registeredHandler, handler)) {
      throw StateError('handler mismatch for $type');
    }
    _handlers.remove(type);
    final current = _room._protocolInstance.getHandler(type);
    if (identical(current, registeredHandler)) {
      _room._protocolInstance.removeHandler(type, current!);
    }
  }

  ProtocolMessageHandler? getHandler(String type) {
    return _handlers[type];
  }

  Future<void> send(String type, Uint8List data, {int? id}) async {
    if (_room._entered && !_room.isConnected && !_room._allowDisconnectedRequests) {
      throw _room._disconnectedError(baseMessage: 'room connection is disconnected');
    }
    await _room._protocolInstance.send(type, data, id: id);
  }

  int sendNowait(String type, Uint8List data, {int? id}) {
    if (_room._entered && !_room.isConnected && !_room._allowDisconnectedRequests) {
      throw _room._disconnectedError(baseMessage: 'room connection is disconnected');
    }
    return _room._protocolInstance.sendNowait(type, data, id: id);
  }

  int getNextMessageId() {
    if (_room._entered && !_room.isConnected && !_room._allowDisconnectedRequests) {
      throw _room._disconnectedError(baseMessage: 'room connection is disconnected');
    }
    return _room._protocolInstance.getNextMessageId();
  }

  Future<Object?> get done {
    return _room.waitForClose().then<Object?>((_) => null);
  }

  Future<void> waitForClose() {
    return _room.waitForClose();
  }

  ProtocolCloseKind? get closeKind {
    return _room.closeKind;
  }

  String? get closeReason {
    return _room.closeReason;
  }

  bool get isOpen {
    return _room._protocolInstance.isOpen;
  }

  bool get isClosed {
    return _room.isClosed;
  }

  String? get token {
    return _room._protocolInstance.token;
  }

  Uri? get url {
    return _room._protocolInstance.url;
  }
}

class RoomClient extends ChangeEmitter {
  RoomClient({
    required ProtocolFactory protocolFactory,
    Duration? reconnectTimeout,
    Duration reconnectRetryBaseDelay = const Duration(milliseconds: 500),
    Duration reconnectRetryMaxDelay = const Duration(seconds: 30),
    OAuthTokenRequestHandler? oauthTokenRequestHandler,
    SecretRequestHandler? secretRequestHandler,
  }) : _protocolFactory = protocolFactory,
       _reconnectTimeout = reconnectTimeout,
       _reconnectRetryBaseDelay = reconnectRetryBaseDelay,
       _reconnectRetryMaxDelay = reconnectRetryMaxDelay {
    if (reconnectTimeout != null && reconnectTimeout.isNegative) {
      throw ArgumentError.value(reconnectTimeout, 'reconnectTimeout', 'must be null or non-negative');
    }
    if (reconnectRetryBaseDelay <= Duration.zero) {
      throw ArgumentError.value(reconnectRetryBaseDelay, 'reconnectRetryBaseDelay', 'must be positive');
    }
    if (reconnectRetryMaxDelay <= Duration.zero) {
      throw ArgumentError.value(reconnectRetryMaxDelay, 'reconnectRetryMaxDelay', 'must be positive');
    }
    _protocolInstance = _protocolFactory();
    unawaited(_ready.future.catchError((Object _) {}));
    protocol = RoomProtocolProxy(room: this);
    protocol.addHandler('__response__', _handleResponse);
    protocol.addHandler('connected', _handleParticipant);
    protocol.addHandler('room_ready', _handleRoomReady);
    protocol.addHandler('room.status', _handleRoomStatus);
    protocol.addHandler('room.tool_call_response_chunk', _handleToolCallResponseChunk);
    sync = SyncClient(room: this);
    storage = StorageClient(room: this);
    developer = DeveloperClient(room: this);
    messaging = MessagingClient(room: this);
    agents = AgentsClient(room: this);
    queues = QueuesClient(room: this);
    datasets = DatasetsClient(room: this);
    memory = MemoryClient(room: this);
    containers = ContainersClient(room: this);
    services = ServicesClient(room: this);
    secrets = SecretsClient(room: this, oauthTokenRequestHandler: oauthTokenRequestHandler, secretRequestHandler: secretRequestHandler);
  }

  final ProtocolFactory _protocolFactory;
  final Duration? _reconnectTimeout;
  final Duration _reconnectRetryBaseDelay;
  final Duration _reconnectRetryMaxDelay;
  late Protocol _protocolInstance;
  late final RoomProtocolProxy protocol;
  late final QueuesClient queues;
  late final SyncClient sync;
  late final StorageClient storage;
  late final DeveloperClient developer;
  late final MessagingClient messaging;
  late final AgentsClient agents;
  late final DatasetsClient datasets;
  late final MemoryClient memory;
  late final ContainersClient containers;
  late final ServicesClient services;
  late final SecretsClient secrets;

  final _ready = Completer<void>();
  final _roomClosed = Completer<void>();
  Completer<void> _connectionReady = Completer<void>();
  Completer<void> _localParticipantReady = Completer<void>();

  Future<void> get ready {
    return _ready.future;
  }

  final _pendingRequests = <int, _PendingRequest>{};
  final _ignoredResponseLabels = <int, String>{};
  final _toolCallStreams = <String, StreamController<Content>>{};
  final _pendingInvokeResponses = <String, Completer<Content>>{};
  final _uuid = const Uuid();
  final _eventsController = StreamController<RoomEvent>.broadcast();

  Future<void>? _lifecycleTask;
  _RoomClientTerminalState? _terminalState;
  bool _entered = false;
  bool _closing = false;
  bool _connected = false;
  bool _allowDisconnectedRequests = false;
  bool _terminalCallbacksInvoked = false;
  ProtocolCloseKind? _closeKind;
  String? _closeReason;
  void Function()? _doneHandler;
  void Function(Object? error)? _errorHandler;

  ParticipantToken? get participantToken {
    final token = _protocolInstance.token;
    if (token == null || token.isEmpty) {
      return null;
    }

    try {
      return ParticipantToken.fromJwt(token, verify: false);
    } catch (_) {
      return null;
    }
  }

  ApiScope? get apiGrant {
    return participantToken?.getApiGrant();
  }

  bool get isConnected {
    return _connected;
  }

  bool get isClosed {
    return _closing || _terminalState != null || _roomClosed.isCompleted;
  }

  ProtocolCloseKind? get closeKind {
    return _closeKind ?? _protocolInstance.closeKind;
  }

  String? get closeReason {
    return _closeReason ?? _normalizeCloseReason(_protocolInstance.closeReason);
  }

  Future<void> waitForClose() async {
    if (_lifecycleTask == null) {
      await _protocolInstance.waitForClose();
      return;
    }
    await _roomClosed.future;
  }

  Future<void> waitUntilConnected() async {
    while (!_connected) {
      _raiseIfTerminal();
      if (_roomClosed.isCompleted) {
        _raiseIfTerminal();
        throw _disconnectedError(baseMessage: 'room connection closed before reconnect completed');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> _waitUntilConnectedForMessages() async {
    while (!_connected) {
      _raiseIfTerminalForMessages();
      if (_roomClosed.isCompleted) {
        _raiseIfTerminalForMessages();
        throw _messageDisconnectedError(baseMessage: 'room connection closed before message send completed');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  void _markConnected() {
    _connected = true;
    _closeKind = null;
    _closeReason = null;
  }

  void _markDisconnected({required String? reason, required ProtocolCloseKind? kind}) {
    _connected = false;
    _closeKind = kind;
    _closeReason = _normalizeCloseReason(reason);
    _ignoredResponseLabels.clear();
  }

  void _failPendingRequests(RoomServerException error) {
    if (_pendingRequests.isEmpty) {
      return;
    }

    final pending = Map<int, _PendingRequest>.from(_pendingRequests);
    _pendingRequests.clear();
    for (final request in pending.values) {
      if (!request._completer.isCompleted) {
        request._completer.completeError(error);
      }
    }
  }

  Future<void> _failPendingWork({required _RoomClientTerminalState state}) async {
    _failPendingRequests(state.requestError());
    await _failToolCallStreams(error: state.toolCallError());
  }

  Future<void> _openProtocol({required bool initial}) async {
    final protocol = _protocolInstance;
    _connectionReady = Completer<void>();
    _localParticipantReady = Completer<void>();
    protocol.start(
      onDone: () {
        final error = _roomClosedBeforeReadyError(protocol);
        if (!_connectionReady.isCompleted) {
          _connectionReady.completeError(error);
        }
        if (!_localParticipantReady.isCompleted) {
          _localParticipantReady.completeError(error);
        }
        if (!initial && !_ready.isCompleted) {
          _ready.completeError(error);
        }
      },
      onError: (Object? error) {
        final wrapped = _wrapRoomConnectionError(error);
        if (!_connectionReady.isCompleted) {
          _connectionReady.completeError(wrapped);
        }
        if (!_localParticipantReady.isCompleted) {
          _localParticipantReady.completeError(wrapped);
        }
        if (!initial && !_ready.isCompleted) {
          _ready.completeError(wrapped);
        }
      },
    );
    try {
      await Future.wait<void>([_connectionReady.future, _localParticipantReady.future]);
    } catch (error) {
      final kind = protocol.closeKind ?? ProtocolCloseKind.error;
      if (!initial && kind != ProtocolCloseKind.error) {
        throw _ProtocolStartupFailure(kind: kind, reason: protocol.closeReason);
      }
      rethrow;
    }
  }

  Future<void> start({void Function()? onDone, void Function(Object? error)? onError}) async {
    if (_entered) {
      throw RoomServerException('room client already started');
    }
    _doneHandler = onDone;
    _errorHandler = onError;
    try {
      try {
        await _openProtocol(initial: true);
      } on _ProtocolStartupFailure catch (error) {
        if (!_isRetryableStartupClose(kind: error.kind, reason: error.reason) || _reconnectTimeout == Duration.zero) {
          _setStartupTerminalState(closeKind: error.kind, closeReason: error.reason, protocol: _protocolInstance);
          throw _startupException(closeKind: error.kind, closeReason: error.reason, protocol: _protocolInstance);
        }

        await _closeProtocol(_protocolInstance);
        final retryResult = await _retryProtocolConnection(
          disconnectReason: error.reason,
          protocolFactoryFailureLogMessage: 'unable to create replacement room protocol during initial startup',
          attemptFailureLogMessage: 'room startup attempt failed',
          attempt: _attemptInitialProtocolStartup,
        );
        if (!retryResult.connected) {
          _finalizeInitialStartupRetryFailure(retryResult: retryResult);
        }
      } catch (error, stackTrace) {
        final nonRetryableCloseReason = _nonRetryableConnectFailureReason(error);
        if (nonRetryableCloseReason != null) {
          _finalizeInitialStartupRetryFailure(
            retryResult: _ProtocolRetryResult(connected: false, closeKind: ProtocolCloseKind.error, closeReason: nonRetryableCloseReason),
          );
        }

        final closeKind = _protocolInstance.closeKind;
        if (closeKind != null && !_isRetryableStartupClose(kind: closeKind, reason: _protocolInstance.closeReason)) {
          _setStartupTerminalState(closeKind: closeKind, closeReason: _protocolInstance.closeReason, protocol: _protocolInstance);
          throw _startupException(closeKind: closeKind, closeReason: _protocolInstance.closeReason, protocol: _protocolInstance);
        }

        final closeReason = _connectionFailureReason(error);
        if (_reconnectTimeout == Duration.zero) {
          _setStartupTerminalState(closeKind: ProtocolCloseKind.error, closeReason: closeReason, protocol: _protocolInstance);
          throw _startupException(closeKind: ProtocolCloseKind.error, closeReason: closeReason, protocol: _protocolInstance);
        }

        _roomClientLogger.log(Level.FINE, 'room startup attempt failed', error, stackTrace);
        await _closeProtocol(_protocolInstance);
        final retryResult = await _retryProtocolConnection(
          disconnectReason: closeReason,
          protocolFactoryFailureLogMessage: 'unable to create replacement room protocol during initial startup',
          attemptFailureLogMessage: 'room startup attempt failed',
          attempt: _attemptInitialProtocolStartup,
        );
        if (!retryResult.connected) {
          _finalizeInitialStartupRetryFailure(retryResult: retryResult);
        }
      }
      sync.start();
      messaging.start();
      _entered = true;
      _markConnected();
      messaging._onRoomReconnect();
      _lifecycleTask = _connectionLifecycle();
    } catch (error) {
      sync.dispose();
      unawaited(messaging.stop());
      _protocolInstance.dispose();
      rethrow;
    }

    await ready;
  }

  void _invokeTerminalCallbacks({required bool useErrorCallback, Object? error}) {
    if (_terminalCallbacksInvoked) {
      return;
    }
    _terminalCallbacksInvoked = true;
    if (useErrorCallback) {
      _errorHandler?.call(error);
      return;
    }
    _doneHandler?.call();
  }

  Future<void> _completeReconnect() async {
    await _openProtocol(initial: false);
    _allowDisconnectedRequests = true;
    try {
      _resendLocalAttributesNowait();
      await sync._onRoomReconnect();
      messaging._onRoomReconnect();
      _markConnected();
    } finally {
      _allowDisconnectedRequests = false;
    }
  }

  void _replaceProtocol(Protocol nextProtocol) {
    final currentProtocol = _protocolInstance;
    protocol._unbind(currentProtocol);
    _protocolInstance = nextProtocol;
    protocol._bind(nextProtocol);
  }

  Duration? _remainingReconnectTimeout(DateTime? deadline) {
    if (deadline == null) {
      return null;
    }
    final remaining = deadline.difference(DateTime.now());
    if (remaining.isNegative) {
      return Duration.zero;
    }
    return remaining;
  }

  Duration _reconnectRetryDelay({required int retryCount}) {
    var delay = _reconnectRetryBaseDelay;
    for (var i = 0; i < retryCount; i++) {
      if (delay >= _reconnectRetryMaxDelay) {
        return _reconnectRetryMaxDelay;
      }
      delay *= 2;
    }
    return delay > _reconnectRetryMaxDelay ? _reconnectRetryMaxDelay : delay;
  }

  Future<void> _attemptInitialProtocolStartup({required Protocol protocol, required Duration? remaining}) async {
    assert(identical(protocol, _protocolInstance));
    if (remaining == null) {
      await _openProtocol(initial: false);
      return;
    }

    await _openProtocol(initial: false).timeout(remaining);
  }

  Future<void> _attemptReconnect({required Protocol protocol, required Duration? remaining}) async {
    try {
      if (remaining == null) {
        await _completeReconnect();
      } else {
        await _completeReconnect().timeout(remaining);
      }
    } on TimeoutException {
      _allowDisconnectedRequests = false;
      await sync._onRoomDisconnect();
      messaging._onRoomDisconnect(reason: protocol.closeReason);
      rethrow;
    } on _ProtocolStartupFailure {
      rethrow;
    } catch (error) {
      _allowDisconnectedRequests = false;
      await sync._onRoomDisconnect();
      messaging._onRoomDisconnect(reason: protocol.closeReason);
      rethrow;
    }
  }

  String _formatDuration(Duration duration) {
    if (duration.inMilliseconds % 1000 == 0) {
      return '${duration.inSeconds}s';
    }
    return '${duration.inMilliseconds / 1000}s';
  }

  String _reconnectTimeoutReason({required String? disconnectReason}) {
    final configuredTimeout = _reconnectTimeout;
    if (configuredTimeout == null) {
      throw StateError('reconnect timeout reason requires a timeout');
    }
    final normalizedDisconnectReason = _normalizeCloseReason(disconnectReason);
    final timeoutDisplay = _formatDuration(configuredTimeout);
    if (normalizedDisconnectReason == null) {
      return 'room reconnect timed out after $timeoutDisplay';
    }
    return 'room reconnect timed out after $timeoutDisplay ($normalizedDisconnectReason)';
  }

  _ProtocolRetryResult _timedOutRetryResult({required String? disconnectReason}) {
    if (_reconnectTimeout == null) {
      throw StateError('timed out retry result requires a timeout');
    }

    return _ProtocolRetryResult(
      connected: false,
      closeKind: ProtocolCloseKind.error,
      closeReason: _reconnectTimeoutReason(disconnectReason: disconnectReason),
    );
  }

  void _completeRoomClosed() {
    if (_roomClosed.isCompleted) {
      return;
    }
    _roomClosed.complete();
  }

  Future<void> _closeAfterUnexpectedDisconnect({required String? closeReason}) async {
    final normalized = _normalizeCloseReason(closeReason);
    final state = _unexpectedCloseTerminalState(closeReason: normalized);
    _closeKind = ProtocolCloseKind.error;
    _closeReason = normalized;
    _setTerminalState(state: state);
    _completeRoomClosed();
    _invokeTerminalCallbacks(useErrorCallback: true, error: state.requestError());
  }

  Future<void> _closeProtocol(Protocol protocol) async {
    protocol.dispose();
    await protocol.waitForClose();
  }

  Future<_ProtocolRetryResult> _retryProtocolConnection({
    required String? disconnectReason,
    required String protocolFactoryFailureLogMessage,
    required String attemptFailureLogMessage,
    required _ProtocolConnectAttempt attempt,
  }) async {
    var failureReason = _normalizeCloseReason(disconnectReason);

    void recordFailureReason(String? reason) {
      final normalizedReason = _normalizeCloseReason(reason);
      if (failureReason == null && normalizedReason != null) {
        failureReason = normalizedReason;
      }
    }

    DateTime? deadline;
    if (_reconnectTimeout != null) {
      deadline = DateTime.now().add(_reconnectTimeout);
    }

    var firstAttempt = true;
    var retryCount = 0;
    while (!_closing) {
      if (firstAttempt) {
        firstAttempt = false;
        if (_reconnectTimeout == null) {
          await Future<void>.delayed(_reconnectRetryDelay(retryCount: retryCount));
          retryCount++;
        }
      } else {
        final remaining = _remainingReconnectTimeout(deadline);
        if (remaining != null && remaining == Duration.zero) {
          return _timedOutRetryResult(disconnectReason: failureReason);
        }

        if (remaining == null) {
          await Future<void>.delayed(_reconnectRetryDelay(retryCount: retryCount));
        } else {
          final backoffDelay = _reconnectRetryDelay(retryCount: retryCount);
          final delay = remaining.compareTo(backoffDelay) < 0 ? remaining : backoffDelay;
          if (delay > Duration.zero) {
            await Future<void>.delayed(delay);
          }
        }
        retryCount++;
      }

      final remaining = _remainingReconnectTimeout(deadline);
      if (remaining != null && remaining == Duration.zero) {
        return _timedOutRetryResult(disconnectReason: failureReason);
      }

      late final Protocol nextProtocol;
      try {
        nextProtocol = _protocolFactory();
      } on ProtocolReconnectUnsupportedException {
        return _ProtocolRetryResult(connected: false, closeKind: ProtocolCloseKind.error, closeReason: failureReason);
      } catch (error, stackTrace) {
        recordFailureReason('$error');
        _roomClientLogger.log(Level.FINE, protocolFactoryFailureLogMessage, error, stackTrace);
        continue;
      }

      _replaceProtocol(nextProtocol);
      try {
        await attempt(protocol: nextProtocol, remaining: remaining);
      } on TimeoutException {
        recordFailureReason(nextProtocol.closeReason);
        await _closeProtocol(nextProtocol);
        return _timedOutRetryResult(disconnectReason: failureReason);
      } on _ProtocolStartupFailure catch (error) {
        recordFailureReason(error.reason);
        await _closeProtocol(nextProtocol);
        if (!_isRetryableStartupClose(kind: error.kind, reason: error.reason)) {
          return _ProtocolRetryResult(connected: false, closeKind: error.kind, closeReason: error.reason);
        }
      } catch (error, stackTrace) {
        final nonRetryableCloseReason = _nonRetryableConnectFailureReason(error);
        if (nonRetryableCloseReason != null) {
          await _closeProtocol(nextProtocol);
          return _ProtocolRetryResult(connected: false, closeKind: ProtocolCloseKind.error, closeReason: nonRetryableCloseReason);
        }

        recordFailureReason(_connectionFailureReason(error));
        _roomClientLogger.log(Level.FINE, attemptFailureLogMessage, error, stackTrace);
        await _closeProtocol(nextProtocol);
        continue;
      }

      return const _ProtocolRetryResult(connected: true);
    }

    return _ProtocolRetryResult(connected: false, closeKind: ProtocolCloseKind.client, closeReason: closeReason);
  }

  Future<bool> _reconnect({required String? disconnectReason}) async {
    final retryResult = await _retryProtocolConnection(
      disconnectReason: disconnectReason,
      protocolFactoryFailureLogMessage: 'unable to create replacement room protocol',
      attemptFailureLogMessage: 'room reconnect attempt failed',
      attempt: _attemptReconnect,
    );
    if (retryResult.connected) {
      _emitStatus(status: 'reconnected', message: 'room connection restored');
      return true;
    }

    final closeKind = retryResult.closeKind;
    if (closeKind == ProtocolCloseKind.error) {
      final closeReason = retryResult.closeReason;
      if (closeReason != null && closeReason.startsWith('room reconnect timed out after')) {
        _roomClientLogger.warning('$closeReason; closing room client');
      }
      await _closeAfterUnexpectedDisconnect(closeReason: closeReason);
      return false;
    }

    if (closeKind == null) {
      throw StateError('reconnect failure requires a close kind');
    }

    _setTerminalState(state: _protocolTerminalState(protocol: _protocolInstance));
    _closeKind = closeKind;
    _closeReason = _normalizeCloseReason(retryResult.closeReason);
    _completeRoomClosed();
    _invokeTerminalCallbacks(useErrorCallback: false);
    return false;
  }

  Future<void> _connectionLifecycle() async {
    while (true) {
      final protocol = _protocolInstance;
      await protocol.done;
      final closeKind = protocol.closeKind ?? ProtocolCloseKind.error;
      final closeReason = protocol.closeReason;
      final state = _protocolTerminalState(protocol: protocol);

      if (_closing) {
        _completeRoomClosed();
        return;
      }

      final shouldReconnect = closeKind == ProtocolCloseKind.error || closeKind == ProtocolCloseKind.server;

      if (!shouldReconnect) {
        _setTerminalState(state: state);
      }

      _markDisconnected(reason: closeReason, kind: closeKind);
      _emitStatus(status: 'disconnected', message: closeReason ?? 'room connection lost');
      await sync._onRoomDisconnect();
      messaging._onRoomDisconnect(reason: closeReason);
      await _failPendingWork(state: state);
      await _closeProtocol(protocol);

      if (shouldReconnect) {
        final normalizedReason = _normalizeCloseReason(closeReason);
        if (_reconnectTimeout == Duration.zero) {
          if (normalizedReason == null) {
            _roomClientLogger.warning('room connection lost; automatic reconnect disabled');
          } else {
            _roomClientLogger.warning('room connection lost ($normalizedReason); automatic reconnect disabled');
          }
          await _closeAfterUnexpectedDisconnect(closeReason: normalizedReason);
          return;
        }

        if (normalizedReason == null) {
          _roomClientLogger.warning('room connection lost; automatically attempting to reconnect');
        } else {
          _roomClientLogger.warning('room connection lost ($normalizedReason); automatically attempting to reconnect');
        }
        if (await _reconnect(disconnectReason: normalizedReason)) {
          continue;
        }
        return;
      }

      _closeKind = closeKind;
      _closeReason = _normalizeCloseReason(closeReason);
      _completeRoomClosed();
      _invokeTerminalCallbacks(useErrorCallback: false);
      return;
    }
  }

  static String? _normalizeCloseReason(String? reason) {
    if (reason == null) {
      return null;
    }
    final normalized = reason.trim();
    return normalized.isEmpty ? null : normalized;
  }

  String? _connectionFailureReason(Object error) {
    if (error is RoomServerException) {
      return _normalizeCloseReason(error.message);
    }

    return _normalizeCloseReason('$error');
  }

  String _formatClosedMessage({required String baseMessage, Protocol? protocol, String? closeReason}) {
    final normalizedCloseReason = _normalizeCloseReason(closeReason) ?? _normalizeCloseReason((protocol ?? _protocolInstance).closeReason);
    if (normalizedCloseReason == null) {
      return baseMessage;
    }
    return '$baseMessage: $normalizedCloseReason';
  }

  _RoomClientTerminalState _protocolTerminalState({Protocol? protocol}) {
    return _RoomClientTerminalState(
      requestMessage: _formatClosedMessage(baseMessage: 'room connection closed before request completed', protocol: protocol),
      toolCallMessage: _formatClosedMessage(baseMessage: 'room connection closed before tool call completed', protocol: protocol),
      messageSendMessage: _formatClosedMessage(baseMessage: 'room connection closed before message send completed', protocol: protocol),
    );
  }

  _RoomClientTerminalState _clientClosedTerminalState() {
    return const _RoomClientTerminalState(
      requestMessage: 'room client was closed before request completed',
      toolCallMessage: 'room client was closed before tool call completed',
      messageSendMessage: 'room client was closed before message send completed',
    );
  }

  _RoomClientTerminalState _unexpectedCloseTerminalState({required String? closeReason}) {
    return _RoomClientTerminalState(
      requestMessage: _formatClosedMessage(
        baseMessage: 'room connection unexpectedly closed before request completed',
        closeReason: closeReason,
      ),
      toolCallMessage: _formatClosedMessage(
        baseMessage: 'room connection unexpectedly closed before tool call completed',
        closeReason: closeReason,
      ),
      messageSendMessage: _formatClosedMessage(
        baseMessage: 'room connection unexpectedly closed before message send completed',
        closeReason: closeReason,
      ),
    );
  }

  void _setStartupTerminalState({required ProtocolCloseKind closeKind, required String? closeReason, Protocol? protocol}) {
    final normalizedCloseReason = _normalizeCloseReason(closeReason);
    _closeKind = closeKind;
    _closeReason = normalizedCloseReason;
    if (closeKind == ProtocolCloseKind.error) {
      _setTerminalState(state: _unexpectedCloseTerminalState(closeReason: normalizedCloseReason));
    } else if (closeKind == ProtocolCloseKind.client) {
      _setTerminalState(state: _clientClosedTerminalState());
    } else {
      _setTerminalState(state: _protocolTerminalState(protocol: protocol));
    }
    if (!_ready.isCompleted) {
      _ready.completeError(_startupException(closeKind: closeKind, closeReason: normalizedCloseReason, protocol: protocol));
    }
    _completeRoomClosed();
  }

  _RoomClientTerminalState _setTerminalState({required _RoomClientTerminalState state}) {
    return _terminalState ??= state;
  }

  void _raiseIfTerminal() {
    final state = _terminalState;
    if (state != null) {
      throw state.requestError();
    }
  }

  void _raiseIfTerminalForMessages() {
    final state = _terminalState;
    if (state != null) {
      throw state.messageSendError();
    }
  }

  RoomServerException _disconnectedError({required String baseMessage}) {
    return RoomServerException(_formatClosedMessage(baseMessage: baseMessage));
  }

  RoomServerException _messageDisconnectedError({required String baseMessage}) {
    return RoomServerException(_formatClosedMessage(baseMessage: baseMessage));
  }

  RoomServerException _startupException({required ProtocolCloseKind closeKind, required String? closeReason, Protocol? protocol}) {
    final baseMessage = switch (closeKind) {
      ProtocolCloseKind.error => 'room connection unexpectedly closed before the room became ready',
      ProtocolCloseKind.client => 'room client was closed before the room became ready',
      _ => 'room connection closed before the room became ready',
    };

    return RoomServerException(_formatClosedMessage(baseMessage: baseMessage, protocol: protocol, closeReason: closeReason));
  }

  Never _finalizeInitialStartupRetryFailure({required _ProtocolRetryResult retryResult}) {
    final closeKind = retryResult.closeKind;
    if (closeKind == null) {
      throw StateError('initial startup retry failure requires a close kind');
    }

    _setStartupTerminalState(closeKind: closeKind, closeReason: retryResult.closeReason, protocol: _protocolInstance);
    throw _startupException(closeKind: closeKind, closeReason: retryResult.closeReason, protocol: _protocolInstance);
  }

  RoomServerException _coerceMessageSendError(RoomServerException error) {
    final state = _terminalState;
    if (state == null) {
      return error;
    }
    if (error.message == state.requestMessage || error.message == state.toolCallMessage) {
      return state.messageSendError();
    }
    return error;
  }

  void _emitStatus({required String status, required String message}) {
    _eventsController.add(RoomStatusEvent(status: status, message: message));
  }

  void dispose() {
    _closing = true;
    _markDisconnected(reason: closeReason, kind: closeKind ?? ProtocolCloseKind.client);
    final closingState = _clientClosedTerminalState();
    _setTerminalState(state: closingState);
    _failPendingRequests(closingState.requestError());
    unawaited(_failToolCallStreams(error: closingState.toolCallError()));
    sync.dispose();
    unawaited(messaging.stop());
    _protocolInstance.dispose();
    _entered = false;
    _closeKind = ProtocolCloseKind.client;
    _completeRoomClosed();
    _invokeTerminalCallbacks(useErrorCallback: false);
    _localParticipant = null;
  }

  int? _sendProtocolNowait({
    required String type,
    required Uint8List data,
    required String label,
    int? messageId,
    bool expectResponse = false,
  }) {
    try {
      _raiseIfTerminal();
    } catch (error, stackTrace) {
      _roomClientLogger.log(Level.FINE, 'skipping $label because the room is closed', error, stackTrace);
      return null;
    }

    if (_entered && !_connected && !_allowDisconnectedRequests) {
      _roomClientLogger.fine('skipping $label while room is disconnected');
      return null;
    }

    final protocol = _protocolInstance;
    final resolvedMessageId = messageId ?? protocol.getNextMessageId();
    if (expectResponse) {
      _ignoredResponseLabels[resolvedMessageId] = label;
    }

    try {
      protocol.sendNowait(type, data, id: resolvedMessageId);
    } catch (error, stackTrace) {
      _ignoredResponseLabels.remove(resolvedMessageId);
      if (isClosed) {
        _roomClientLogger.log(Level.FINE, 'skipping $label because the room is closed', error, stackTrace);
      } else {
        _roomClientLogger.log(Level.WARNING, 'unable to queue $label', error, stackTrace);
      }
      return null;
    }

    return resolvedMessageId;
  }

  int? _sendRoomRequestNowait(
    String type,
    Map<String, dynamic> request, {
    Uint8List? data,
    required String label,
    bool expectResponse = false,
  }) {
    return _sendProtocolNowait(type: type, data: packMessage(request, data), label: label, expectResponse: expectResponse);
  }

  void invokeNowait({required String toolkit, required String tool, Content? input, String? participantId, String? onBehalfOfId}) {
    final resolvedInput = input ?? EmptyContent();
    final packedInput = unpackMessage(resolvedInput.pack());
    final request = <String, dynamic>{
      'toolkit': toolkit,
      'tool': tool,
      'participant_id': participantId,
      'on_behalf_of_id': onBehalfOfId,
      'tool_call_id': _uuid.v4(),
      'arguments': packedInput.header,
    };
    _sendRoomRequestNowait(
      'room.invoke_tool',
      request,
      data: packedInput.payload.isEmpty ? null : packedInput.payload,
      label: '$toolkit.$tool',
      expectResponse: true,
    );
  }

  void _sendLocalAttributesNowait(Map<String, dynamic> attributes) {
    _sendProtocolNowait(type: 'set_attributes', data: packMessage(attributes), label: 'local participant attribute update');
  }

  void _resendLocalAttributesNowait() {
    final localParticipant = _localParticipant;
    if (localParticipant == null || localParticipant._attributes.isEmpty) {
      return;
    }
    _sendLocalAttributesNowait(Map<String, dynamic>.from(localParticipant._attributes));
  }

  // send a request, optionally with a binary trailer
  Future<Content> sendRequest(String type, Map<String, dynamic> request, {Uint8List? data}) async {
    _raiseIfTerminal();
    if (_entered && !_connected && !_allowDisconnectedRequests) {
      throw _disconnectedError(baseMessage: 'room connection is disconnected');
    }
    final requestId = _protocolInstance.getNextMessageId();

    final pr = _PendingRequest();

    _pendingRequests[requestId] = pr;

    final message = packMessage(request, data);

    try {
      await _protocolInstance.send(type, message, id: requestId);
      final response = await pr.fut;
      if (response is ErrorContent) {
        throw RoomServerException(response.text, code: response.code);
      }
      return response;
    } catch (error) {
      _pendingRequests.remove(requestId);
      rethrow;
    }
  }

  Future<void> call({required String name, required String url, required Map<String, dynamic> arguments}) async {
    await sendRequest("room.call", {"name": name, "url": url, "arguments": arguments});
  }

  Future<List<ToolkitDescription>> listToolkits({String? participantId, String? participantName, int? timeout}) async {
    final request = <String, dynamic>{};
    if (participantId != null) {
      request["participant_id"] = participantId;
    }
    if (participantName != null) {
      request["participant_name"] = participantName;
    }
    if (timeout != null) {
      request["timeout"] = timeout;
    }

    final result = await sendRequest("room.list_toolkits", request);
    if (result is! JsonContent) {
      throw RoomServerException("unexpected return type from room.list_toolkits");
    }

    final toolsValue = result.json["tools"];
    if (toolsValue is! Map) {
      throw RoomServerException("unexpected return type from room.list_toolkits");
    }

    final tools = Map<String, dynamic>.from(toolsValue);
    final toolkits = <ToolkitDescription>[];

    for (final entry in tools.entries) {
      final json = entry.value;
      if (json is! Map) {
        throw RoomServerException("unexpected toolkit description from room.list_toolkits");
      }
      toolkits.add(ToolkitDescription.fromJson(Map<String, dynamic>.from(json), name: entry.key));
    }

    return toolkits;
  }

  Future<Content> _awaitInvokeResponse({required String toolCallId, required Future<Content> requestFuture}) async {
    final pending = Completer<Content>();
    _pendingInvokeResponses[toolCallId] = pending;
    try {
      return await Future.any([requestFuture, pending.future]);
    } finally {
      final current = _pendingInvokeResponses[toolCallId];
      if (identical(current, pending)) {
        _pendingInvokeResponses.remove(toolCallId);
      }
    }
  }

  Future<ToolCallOutput> invoke({
    required String toolkit,
    required String tool,
    required ToolInput input,
    String? participantId,
    String? onBehalfOfId,
  }) async {
    final toolCallId = _uuid.v4();
    final controller = StreamController<Content>(
      onCancel: () {
        _toolCallStreams.remove(toolCallId);
      },
    );
    _toolCallStreams[toolCallId] = controller;

    final request = <String, dynamic>{
      "toolkit": toolkit,
      "tool": tool,
      "participant_id": participantId,
      "on_behalf_of_id": onBehalfOfId,
      "tool_call_id": toolCallId,
    };

    Uint8List? invokeData;
    Future<void>? inputTask;

    if (input is ToolContentInput) {
      final packedInput = unpackMessage(input.content.pack());
      request["arguments"] = packedInput.header;
      invokeData = packedInput.payload.isEmpty ? null : packedInput.payload;
    } else if (input is ToolStreamInput) {
      final openChunk = unpackMessage(ControlContent(method: "open").pack());
      request["arguments"] = openChunk.header;
      inputTask = _streamInvokeToolRequestChunks(toolCallId: toolCallId, inputChunks: input.chunks);
    } else {
      await _closeToolCallStream(toolCallId: toolCallId, controller: controller);
      throw RoomServerException("invokeTool input must be ToolContentInput or ToolStreamInput");
    }

    try {
      final response = await _awaitInvokeResponse(
        toolCallId: toolCallId,
        requestFuture: sendRequest("room.invoke_tool", request, data: invokeData),
      );

      if (response is ControlContent && response.method == "open") {
        if (inputTask != null) {
          unawaited(
            inputTask.catchError((Object error, StackTrace stackTrace) async {
              final wrapped = error is RoomServerException ? error : RoomServerException("request stream failed: $error");
              if (!controller.isClosed) {
                controller.addError(wrapped, stackTrace);
              }
              await _closeToolCallStream(toolCallId: toolCallId, controller: controller);
            }),
          );
        }
        return ToolStreamOutput(controller.stream, inputClosed: inputTask);
      }

      if (inputTask != null) {
        await inputTask;
      }
      await _closeToolCallStream(toolCallId: toolCallId, controller: controller);
      return ToolContentOutput(response);
    } catch (error, stackTrace) {
      if (inputTask != null) {
        await Future.wait([inputTask.catchError((_) {})]);
      }
      if (!controller.isClosed) {
        controller.addError(error, stackTrace);
      }
      await _closeToolCallStream(toolCallId: toolCallId, controller: controller);
      rethrow;
    }
  }

  Future<void> _failToolCallStreams({required RoomServerException error}) async {
    if (_toolCallStreams.isEmpty) {
      return;
    }

    final streams = Map<String, StreamController<Content>>.from(_toolCallStreams);
    _toolCallStreams.clear();
    for (final stream in streams.values) {
      if (!stream.isClosed) {
        stream.addError(error);
        unawaited(stream.close());
      }
    }
  }

  Future<void> _closeToolCallStream({required String toolCallId, required StreamController<Content> controller}) async {
    _toolCallStreams.remove(toolCallId);
    if (!controller.isClosed) {
      unawaited(controller.close());
    }
  }

  Future<void> _sendToolCallRequestChunk({required String toolCallId, required Content chunk}) async {
    final packedChunk = unpackMessage(chunk.pack());
    await sendRequest("room.tool_call_request_chunk", {
      "tool_call_id": toolCallId,
      "chunk": packedChunk.header,
    }, data: packedChunk.payload.isEmpty ? null : packedChunk.payload);
  }

  Future<void> _streamInvokeToolRequestChunks({required String toolCallId, required Stream<Content> inputChunks}) async {
    await Future<void>.delayed(Duration.zero);
    try {
      await for (final item in inputChunks) {
        await _sendToolCallRequestChunk(toolCallId: toolCallId, chunk: item);
      }
    } finally {
      await _sendToolCallRequestChunk(
        toolCallId: toolCallId,
        chunk: ControlContent(method: "close"),
      );
    }
  }

  Future<void> _handleToolCallResponseChunk(Protocol protocol, int messageId, String type, Uint8List data) async {
    if (!identical(protocol, _protocolInstance)) {
      return;
    }
    final message = unpackMessage(data);
    final header = message.header;
    final payload = message.payload;

    final toolCallId = header["tool_call_id"];
    if (toolCallId is! String || toolCallId.isEmpty) {
      Logger.root.warning("ignoring tool call chunk without tool_call_id");
      return;
    }

    final content = _decodeToolCallContent(header: header, payload: payload);

    final pendingInvoke = _pendingInvokeResponses[toolCallId];
    if (pendingInvoke != null && !pendingInvoke.isCompleted) {
      if (content is ErrorContent) {
        pendingInvoke.completeError(RoomServerException(content.text, code: content.code));
      } else if (content is ControlContent && content.method == "close") {
        var detail = "tool call closed before initial invoke response";
        final closeStatus = content.statusCode ?? ControlCloseStatus.normal.code;
        if (closeStatus != ControlCloseStatus.normal.code) {
          detail = content.message ?? "tool call stream closed abnormally";
        }
        pendingInvoke.completeError(RoomServerException(detail, statusCode: closeStatus));
      }
    }

    final stream = _toolCallStreams[toolCallId];
    if (stream == null || stream.isClosed) {
      return;
    }

    if (content is ControlContent) {
      if (content.method == "close") {
        final closeStatus = content.statusCode ?? ControlCloseStatus.normal.code;
        if (closeStatus != ControlCloseStatus.normal.code) {
          final detail = content.message ?? "tool call stream closed abnormally";
          stream.addError(RoomServerException(detail, statusCode: closeStatus));
        }
        await _closeToolCallStream(toolCallId: toolCallId, controller: stream);
      }
      return;
    }

    stream.add(content);
  }

  Content _decodeToolCallContent({required Map<String, dynamic> header, required Uint8List payload}) {
    final chunk = header["chunk"];
    if (chunk is Map) {
      final chunkMap = Map<String, dynamic>.from(chunk);
      if (chunkMap["type"] is String) {
        try {
          return unpackContent(packMessage(chunkMap, payload.isEmpty ? null : payload));
        } catch (_) {
          return JsonContent(json: chunkMap);
        }
      }
      return JsonContent(json: chunkMap);
    }

    return JsonContent(json: {"chunk": chunk});
  }

  Future<void> _handleResponse(Protocol protocol, int messageId, String type, Uint8List data) async {
    if (!identical(protocol, _protocolInstance)) {
      return;
    }
    final response = unpackContent(data);
    final requestId = messageId;

    if (_pendingRequests.containsKey(requestId)) {
      final pr = _pendingRequests.remove(requestId)!;
      if (response is ErrorContent) {
        pr._completer.completeError(RoomServerException(response.text, code: response.code));
      } else {
        pr._completer.complete(response);
      }
    } else if (_ignoredResponseLabels.containsKey(requestId)) {
      final label = _ignoredResponseLabels.remove(requestId)!;
      if (response is ErrorContent) {
        _roomClientLogger.warning('one-way room request failed for $label: ${response.text}');
      }
    } else {
      _roomClientLogger.fine('received a response for a request that is not pending $requestId');
    }
    return;
  }

  Future<void> _handleRoomStatus(Protocol protocol, int messageId, String type, Uint8List bytes) async {
    if (!identical(protocol, _protocolInstance)) {
      return;
    }
    final payload = unpackMessage(bytes).header;

    _eventsController.add(RoomStatusEvent.fromJson(payload));
  }

  Future<void> _handleRoomReady(Protocol protocol, int messageId, String type, Uint8List bytes) async {
    if (!identical(protocol, _protocolInstance)) {
      return;
    }
    final init = unpackMessage(bytes).header;

    _roomName = init["room_name"];
    _roomUrl = init["room_url"];
    _sessionId = init["session_id"];
    if (!_ready.isCompleted) {
      _ready.complete();
    }
    if (!_connectionReady.isCompleted) {
      _connectionReady.complete();
    }
  }

  String? _roomName;
  String? get roomName {
    return _roomName;
  }

  String? _roomUrl;
  String? get roomUrl {
    return _roomUrl;
  }

  String? _sessionId;
  String? get sessionId {
    return _sessionId;
  }

  LocalParticipant? _localParticipant;

  LocalParticipant? get localParticipant {
    return _localParticipant;
  }

  void _onParticipantInit(String participantId, Map<String, dynamic> attributes) {
    if (_localParticipant == null) {
      _localParticipant = LocalParticipant(client: this, id: participantId);
      _localParticipant!._applyAttributes(attributes);
    } else {
      final mergedAttributes = Map<String, dynamic>.from(attributes)..addAll(_localParticipant!._attributes);
      _localParticipant!._replaceIdentity(participantId: participantId, attributes: mergedAttributes);
    }
    if (!_localParticipantReady.isCompleted) {
      _localParticipantReady.complete();
    }
    notifyListeners();
  }

  Stream<RoomEvent> get events {
    return _eventsController.stream;
  }

  StreamSubscription<RoomEvent> listen(void Function(RoomEvent event) handler) {
    return _eventsController.stream.listen(handler);
  }

  Future<void> _handleParticipant(Protocol protocol, int messageId, String type, Uint8List bytes) async {
    if (!identical(protocol, _protocolInstance)) {
      return;
    }
    final message = unpackMessage(bytes).header;
    final type = message["type"];

    switch (type) {
      case "init":
        final participantId = message["participantId"];
        final attributes = message["attributes"];
        _onParticipantInit(participantId, attributes);
    }
  }
}

class LogProgress {
  LogProgress({required this.message, required this.current, required this.total, this.layer});

  String? layer;
  String message;
  int? current;
  int? total;
}

class LogStream<T> {
  LogStream._(this._completer, this.stream, this.progress, this._cancel);

  final Stream<LogProgress> progress;
  final Stream<String> stream;
  final Completer<T> _completer;
  final Future<void> Function() _cancel;

  Future<T> get result {
    return _completer.future;
  }

  Future<void> cancel() async {
    await _cancel();
  }
}

class ContainerRunResult {
  ContainerRunResult({required this.logs, required this.status});

  final List<String> logs;
  final int? status;
}

enum ContextEncoding { gzip }

class DockerSecret {
  const DockerSecret({required this.username, required this.password, required this.registry, required this.email});

  final String username;
  final String password;
  final String registry;
  final String email;

  factory DockerSecret.fromJson(Map<String, dynamic> json) => DockerSecret(
    username: json['username'] as String,
    password: json['password'] as String,
    registry: json['registry'] as String,
    email: json['email'] as String,
  );

  Map<String, String> toJson() => {'username': username, 'password': password, 'registry': registry, 'email': email};
}

// ─────────────────────────────────────────────────────────────────────────────
// Data‑transfer objects
// ─────────────────────────────────────────────────────────────────────────────

class BuildInfo {
  BuildInfo({required this.id, required this.tag, required this.status, this.exitCode});

  final String id;
  final String tag;
  final String status;
  final int? exitCode;

  factory BuildInfo.fromJson(Map<String, dynamic> json) => BuildInfo(
    id: json['id'] as String,
    tag: json['tag'] as String,
    status: json['status'] as String,
    exitCode: json['exit_code'] as int?,
  );
}

class ImportedImage {
  ImportedImage({required this.resolvedRef, required this.refs});

  final String resolvedRef;
  final List<String> refs;

  factory ImportedImage.fromJson(Map<String, dynamic> json) =>
      ImportedImage(resolvedRef: json['resolved_ref'] as String, refs: (json['refs'] as List?)?.cast<String>() ?? const []);
}

/// Lightweight image description (from `containers.list_images`)
class ContainerImage {
  ContainerImage({
    required this.id,
    required this.preferredRef,
    required this.references,
    required this.labels,
    required this.createdAt,
    required this.updatedAt,
    required this.targetMediaType,
  });

  final String id;
  final String? preferredRef;
  final List<String> references;
  final Map<String, String> labels;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? targetMediaType;

  static Map<String, String> _stringMapFromJson(Object? value) {
    if (value is List) {
      final result = <String, String>{};
      for (final entry in value) {
        if (entry is! Map) {
          continue;
        }
        final key = entry['key'];
        final itemValue = entry['value'];
        if (key is String && itemValue is String) {
          result[key] = itemValue;
        }
      }
      return result;
    }
    if (value is Map) {
      return Map<String, String>.from(value);
    }
    return <String, String>{};
  }

  static List<String> _referencesFromJson(Map<String, dynamic> json) {
    final references = json['references'];
    if (references is List) {
      return references.cast<String>();
    }
    final tags = json['tags'];
    if (tags is List) {
      return tags.cast<String>();
    }
    return const [];
  }

  static DateTime? _dateTimeFromJson(Object? value) {
    if (value is! String) {
      return null;
    }
    return DateTime.parse(value);
  }

  factory ContainerImage.fromJson(Map<String, dynamic> json) => ContainerImage(
    id: json['id'] as String,
    preferredRef:
        (json['preferred_ref'] as String?) ??
        (() {
          final references = _referencesFromJson(json);
          return references.isEmpty ? null : references.first;
        })(),
    references: _referencesFromJson(json),
    labels: _stringMapFromJson(json['labels']),
    createdAt: _dateTimeFromJson(json['created_at']),
    updatedAt: _dateTimeFromJson(json['updated_at']),
    targetMediaType: json['target_media_type'] as String?,
  );
}

class ContainerImageDescriptor {
  ContainerImageDescriptor({required this.digest, required this.mediaType, required this.size, required this.annotations});

  final String digest;
  final String? mediaType;
  final int? size;
  final Map<String, String> annotations;

  factory ContainerImageDescriptor.fromJson(Map<String, dynamic> json) => ContainerImageDescriptor(
    digest: json['digest'] as String,
    mediaType: json['media_type'] as String?,
    size: json['size'] as int?,
    annotations: ContainerImage._stringMapFromJson(json['annotations']),
  );
}

class ContainerImageManifest {
  ContainerImageManifest({
    required this.descriptor,
    required this.platformOs,
    required this.platformArchitecture,
    required this.platformVariant,
  });

  final ContainerImageDescriptor descriptor;
  final String? platformOs;
  final String? platformArchitecture;
  final String? platformVariant;

  factory ContainerImageManifest.fromJson(Map<String, dynamic> json) => ContainerImageManifest(
    descriptor: ContainerImageDescriptor.fromJson(Map<String, dynamic>.from(json['descriptor'] as Map)),
    platformOs: json['platform_os'] as String?,
    platformArchitecture: json['platform_architecture'] as String?,
    platformVariant: json['platform_variant'] as String?,
  );
}

class ContainerImageInspection {
  ContainerImageInspection({
    required this.image,
    required this.target,
    required this.selectedManifest,
    required this.manifests,
    required this.config,
    required this.layers,
    required this.contentSize,
  });

  final ContainerImage image;
  final ContainerImageDescriptor target;
  final ContainerImageDescriptor? selectedManifest;
  final List<ContainerImageManifest> manifests;
  final ContainerImageDescriptor? config;
  final List<ContainerImageDescriptor> layers;
  final int? contentSize;

  factory ContainerImageInspection.fromJson(Map<String, dynamic> json) => ContainerImageInspection(
    image: ContainerImage.fromJson(Map<String, dynamic>.from(json['image'] as Map)),
    target: ContainerImageDescriptor.fromJson(Map<String, dynamic>.from(json['target'] as Map)),
    selectedManifest: json['selected_manifest'] == null
        ? null
        : ContainerImageDescriptor.fromJson(Map<String, dynamic>.from(json['selected_manifest'] as Map)),
    manifests: ((json['manifests'] as List?) ?? const [])
        .map((entry) => ContainerImageManifest.fromJson(Map<String, dynamic>.from(entry as Map)))
        .toList(),
    config: json['config'] == null ? null : ContainerImageDescriptor.fromJson(Map<String, dynamic>.from(json['config'] as Map)),
    layers: ((json['layers'] as List?) ?? const [])
        .map((entry) => ContainerImageDescriptor.fromJson(Map<String, dynamic>.from(entry as Map)))
        .toList(),
    contentSize: json['content_size'] as int?,
  );
}

List<Map<String, dynamic>> _containerStringPairList(Map<String, String> values) {
  return values.entries.map((entry) => {'key': entry.key, 'value': entry.value}).toList(growable: false);
}

List<Map<String, dynamic>> _containerPortPairs(Map<int, int> values) {
  return values.entries.map((entry) => {'container_port': entry.key, 'host_port': entry.value}).toList(growable: false);
}

List<Map<String, dynamic>> _containerCredentials(List<DockerSecret> values) {
  return values
      .map((entry) => {'registry': entry.registry, 'username': entry.username, 'password': entry.password})
      .toList(growable: false);
}

class _BuildInputStream {
  _BuildInputStream({
    required this.tags,
    required this.mountPath,
    required this.contextPath,
    required this.chunks,
    this.dockerfilePath,
    this.optimizeImage = true,
    this.private = false,
    this.credentials = const [],
    this.builderName,
    this.size,
  });

  final List<String> tags;
  final String mountPath;
  final String contextPath;
  final Stream<Uint8List> chunks;
  final String? dockerfilePath;
  final bool optimizeImage;
  final bool private;
  final List<DockerSecret> credentials;
  final String? builderName;
  final int? size;

  Stream<Content> inputStream() async* {
    yield BinaryContent(
      data: Uint8List(0),
      headers: {
        'kind': 'start',
        'tags': tags,
        'mount_path': mountPath,
        'context_path': contextPath,
        'dockerfile_path': dockerfilePath,
        'optimize_image': optimizeImage,
        'private': private,
        'credentials': _containerCredentials(credentials),
        'builder_name': builderName,
        'size': size,
      },
    );

    await for (final chunk in chunks) {
      yield BinaryContent(data: chunk, headers: const {'kind': 'data'});
    }
  }
}

String _decodeContainerUtf8(Uint8List data, {required String operation}) {
  try {
    return utf8.decode(data);
  } on FormatException {
    throw RoomServerException('containers.$operation returned invalid UTF-8 data');
  }
}

int _decodeContainerStatusPayload(Uint8List data, {required String operation}) {
  final payload = jsonDecode(_decodeContainerUtf8(data, operation: operation));
  if (payload is Map && payload['status'] is int) {
    return payload['status'] as int;
  }
  throw RoomServerException('containers.$operation returned an invalid status payload');
}

class ExecSession {
  ExecSession._({required String requestId, required this.command, required String containerId, bool? tty})
    : _requestId = requestId,
      _containerId = containerId,
      _tty = tty;

  final String command;
  final String _requestId;
  final String _containerId;
  final bool? _tty;
  final _result = Completer<int>();
  final _inputController = StreamController<Content>();

  Future<int> get result {
    return _result.future;
  }

  bool _closed = false;
  bool _inputClosed = false;
  int? _lastResizeWidth;
  int? _lastResizeHeight;
  bool get closed {
    return _closed;
  }

  Stream<Content> inputStream() async* {
    yield BinaryContent(
      data: Uint8List(0),
      headers: {'kind': 'start', 'request_id': _requestId, 'container_id': _containerId, 'command': command, 'tty': _tty},
    );
    yield* _inputController.stream;
  }

  void _queueInput({required int channel, Uint8List? data, int? width, int? height}) {
    if (_inputClosed) {
      throw RoomServerException('container exec session is already closed');
    }
    _inputController.add(
      BinaryContent(data: data ?? Uint8List(0), headers: {'kind': 'input', 'channel': channel, 'width': width, 'height': height}),
    );
  }

  void _closeInputStream() {
    if (_inputClosed) {
      return;
    }
    _inputClosed = true;
    unawaited(_inputController.close());
  }

  Future<void> write(Uint8List data) async {
    _queueInput(channel: 1, data: data);
  }

  Future<void> resize({required int width, required int height}) async {
    if (_lastResizeWidth == width && _lastResizeHeight == height) {
      return;
    }
    _lastResizeWidth = width;
    _lastResizeHeight = height;
    _queueInput(channel: 4, width: width, height: height);
  }

  late final _stdoutController = StreamController<Uint8List>.broadcast()..stream.listen((data) => previousOutput.add(data));
  late final _stderrController = StreamController<Uint8List>.broadcast()..stream.listen((data) => previousError.add(data));

  List<Uint8List> previousOutput = [];
  List<Uint8List> previousError = [];

  Stream<Uint8List> get output {
    return _stdoutController.stream;
  }

  Stream<Uint8List> get stderr {
    return _stderrController.stream;
  }

  void _close(int code) {
    if (!_result.isCompleted) {
      _result.complete(code);
    }
    _closed = true;
    _closeInputStream();
    _stdoutController.close();
    _stderrController.close();
  }

  void _closeError(Object error) {
    if (!_result.isCompleted) {
      _result.completeError(error);
    }
    _closed = true;
    _closeInputStream();
    _stdoutController.close();
    _stderrController.close();
  }

  Future<void> stop() async {
    _closeInputStream();
  }

  Future<void> kill() async {
    if (_inputClosed) {
      return;
    }
    _queueInput(channel: 5);
  }
}

class ContainersClient extends ChangeEmitter {
  ContainersClient({required this.room});

  RoomClient room;

  RoomServerException _unexpectedResponseError({required String operation}) {
    return RoomServerException('unexpected return type from containers.$operation');
  }

  Future<List<ContainerImage>> listImages() async {
    final output = await room.invoke(
      toolkit: 'containers',
      tool: 'list_images',
      input: ToolContentInput(JsonContent(json: {})),
    );
    if (output is! ToolContentOutput || output.content is! JsonContent) {
      throw _unexpectedResponseError(operation: 'list_images');
    }
    final res = output.content as JsonContent;
    return (res.json['images'] as List).map((i) => ContainerImage.fromJson(i as Map<String, dynamic>)).toList();
  }

  Future<ContainerImageInspection> inspectImage({required String imageId}) async {
    final output = await room.invoke(
      toolkit: 'containers',
      tool: 'inspect_image',
      input: ToolContentInput(JsonContent(json: {'image_id': imageId})),
    );
    if (output is! ToolContentOutput || output.content is! JsonContent) {
      throw _unexpectedResponseError(operation: 'inspect_image');
    }
    return ContainerImageInspection.fromJson(Map<String, dynamic>.from((output.content as JsonContent).json));
  }

  Future<void> deleteImage({required String image}) async {
    await room.invoke(
      toolkit: 'containers',
      tool: 'delete_image',
      input: ToolContentInput(JsonContent(json: {'image': image})),
    );
  }

  Future<void> pullImage({required String tag, List<DockerSecret> credentials = const []}) async {
    await room.invoke(
      toolkit: 'containers',
      tool: 'pull_image',
      input: ToolContentInput(JsonContent(json: {'tag': tag, 'credentials': _containerCredentials(credentials)})),
    );
  }

  Future<String> pushImage({required String tag, List<DockerSecret> credentials = const [], bool private = false}) async {
    final output = await room.invoke(
      toolkit: 'containers',
      tool: 'push_image',
      input: ToolContentInput(JsonContent(json: {'tag': tag, 'credentials': _containerCredentials(credentials), 'private': private})),
    );
    if (output is! ToolContentOutput || output.content is! JsonContent) {
      throw _unexpectedResponseError(operation: 'push_image');
    }
    return (output.content as JsonContent).json['container_id'] as String;
  }

  Future<ImportedImage> load({required String archivePath}) async {
    final output = await room.invoke(
      toolkit: 'containers',
      tool: 'load',
      input: ToolContentInput(JsonContent(json: {'archive_path': archivePath})),
    );
    if (output is! ToolContentOutput || output.content is! JsonContent) {
      throw _unexpectedResponseError(operation: 'load');
    }
    return ImportedImage.fromJson((output.content as JsonContent).json);
  }

  Future<String> loadImage({required List<ContainerMountSpec> mounts, required String archivePath, bool private = false}) async {
    final output = await room.invoke(
      toolkit: 'containers',
      tool: 'load_image',
      input: ToolContentInput(
        JsonContent(
          json: {'mounts': mounts.map((entry) => entry.toJson()).toList(growable: false), 'archive_path': archivePath, 'private': private},
        ),
      ),
    );
    if (output is! ToolContentOutput || output.content is! JsonContent) {
      throw _unexpectedResponseError(operation: 'load_image');
    }
    return (output.content as JsonContent).json['container_id'] as String;
  }

  Future<String> saveImage({
    required String tag,
    required List<ContainerMountSpec> mounts,
    required String archivePath,
    bool private = false,
  }) async {
    final output = await room.invoke(
      toolkit: 'containers',
      tool: 'save_image',
      input: ToolContentInput(
        JsonContent(
          json: {
            'tag': tag,
            'mounts': mounts.map((entry) => entry.toJson()).toList(growable: false),
            'archive_path': archivePath,
            'private': private,
          },
        ),
      ),
    );
    if (output is! ToolContentOutput || output.content is! JsonContent) {
      throw _unexpectedResponseError(operation: 'save_image');
    }
    return (output.content as JsonContent).json['container_id'] as String;
  }

  Future<String> run({
    required String image,
    String? command,
    String? workingDir,
    Map<String, String> env = const {},
    String? mountPath,
    String? mountSubpath,
    String? role,
    String? participantName,
    Map<int, int> ports = const {},
    List<DockerSecret> credentials = const [],
    String? name,
    ContainerMountSpec? mounts,
    bool? writableRootFs,
    bool? private,
  }) async {
    final output = await room.invoke(
      toolkit: 'containers',
      tool: 'run',
      input: ToolContentInput(
        JsonContent(
          json: {
            'image': image,
            'command': command,
            'working_dir': workingDir,
            'env': _containerStringPairList(env),
            'mount_path': mountPath,
            'mount_subpath': mountSubpath,
            'role': role,
            'participant_name': participantName,
            'ports': _containerPortPairs(ports),
            'credentials': _containerCredentials(credentials),
            'name': name,
            'mounts': mounts?.toJson(),
            'writable_root_fs': writableRootFs,
            'private': private,
          },
        ),
      ),
    );
    if (output is! ToolContentOutput || output.content is! JsonContent) {
      throw _unexpectedResponseError(operation: 'run');
    }
    return (output.content as JsonContent).json['container_id'] as String;
  }

  Future<String> runService({required String serviceId, Map<String, String> env = const {}}) async {
    final output = await room.invoke(
      toolkit: 'containers',
      tool: 'run_service',
      input: ToolContentInput(JsonContent(json: {'service_id': serviceId, 'env': _containerStringPairList(env)})),
    );
    if (output is! ToolContentOutput || output.content is! JsonContent) {
      throw _unexpectedResponseError(operation: 'run_service');
    }
    return (output.content as JsonContent).json['container_id'] as String;
  }

  ExecSession exec({required String containerId, required String command, bool tty = false, String? name}) {
    final requestId = const Uuid().v4();
    final session = ExecSession._(requestId: requestId, command: command, containerId: containerId, tty: tty);

    room
        .invoke(toolkit: 'containers', tool: 'exec', input: ToolStreamInput(session.inputStream()))
        .then((output) async {
          if (output is! ToolStreamOutput) {
            throw _unexpectedResponseError(operation: 'exec');
          }

          await for (final chunk in output.stream) {
            if (chunk is ErrorContent) {
              throw RoomServerException(chunk.text, code: chunk.code);
            }
            if (chunk is ControlContent) {
              if (chunk.method == 'close') {
                break;
              }
              throw _unexpectedResponseError(operation: 'exec');
            }
            if (chunk is! BinaryContent) {
              throw _unexpectedResponseError(operation: 'exec');
            }

            final rawChannel = chunk.headers['channel'];
            if (rawChannel is! int) {
              throw RoomServerException('containers.exec returned a chunk without a valid channel');
            }

            if (rawChannel == 1) {
              session._stdoutController.add(chunk.data);
              continue;
            }
            if (rawChannel == 2) {
              session._stderrController.add(chunk.data);
              continue;
            }
            if (rawChannel == 3) {
              session._close(_decodeContainerStatusPayload(chunk.data, operation: 'exec'));
              return;
            }
          }

          throw RoomServerException('containers.exec stream closed before a status was returned');
        })
        .catchError((Object error) {
          session._closeError(error);
        });

    return session;
  }

  Future<String> build({
    List<String>? tags,
    @Deprecated('Use tags instead.') String? tag,
    required String mountPath,
    required String contextPath,
    required Stream<Uint8List> chunks,
    String? dockerfilePath,
    bool optimizeImage = true,
    bool private = false,
    List<DockerSecret> credentials = const [],
    String? builderName,
    int? size,
  }) async {
    final resolvedTags = tags ?? (tag == null ? const <String>[] : <String>[tag]);
    if (resolvedTags.isEmpty) {
      throw ArgumentError.value(resolvedTags, 'tags', 'must not be empty');
    }
    final input = _BuildInputStream(
      tags: resolvedTags,
      mountPath: mountPath,
      contextPath: contextPath,
      chunks: chunks,
      dockerfilePath: dockerfilePath,
      optimizeImage: optimizeImage,
      private: private,
      credentials: credentials,
      builderName: builderName,
      size: size,
    );
    final output = await room.invoke(toolkit: 'containers', tool: 'build', input: ToolStreamInput(input.inputStream()));
    if (output is! ToolContentOutput || output.content is! JsonContent) {
      throw _unexpectedResponseError(operation: 'build');
    }
    return (output.content as JsonContent).json['build_id'] as String;
  }

  Future<List<BuildInfo>> listBuilds() async {
    final output = await room.invoke(
      toolkit: 'containers',
      tool: 'list_builds',
      input: ToolContentInput(JsonContent(json: {})),
    );
    if (output is! ToolContentOutput || output.content is! JsonContent) {
      throw _unexpectedResponseError(operation: 'list_builds');
    }
    final builds = (output.content as JsonContent).json['builds'];
    if (builds is! List) {
      throw _unexpectedResponseError(operation: 'list_builds');
    }
    return builds.map((entry) => BuildInfo.fromJson(entry as Map<String, dynamic>)).toList(growable: false);
  }

  Future<void> cancelBuild({required String buildId}) async {
    await room.invoke(
      toolkit: 'containers',
      tool: 'cancel_build',
      input: ToolContentInput(JsonContent(json: {'build_id': buildId})),
    );
  }

  Future<void> deleteBuild({required String buildId}) async {
    await room.invoke(
      toolkit: 'containers',
      tool: 'delete_build',
      input: ToolContentInput(JsonContent(json: {'build_id': buildId})),
    );
  }

  Future<void> stop({required String containerId, bool force = false}) async {
    await room.invoke(
      toolkit: 'containers',
      tool: 'stop_container',
      input: ToolContentInput(JsonContent(json: {'container_id': containerId, 'force': force})),
    );
  }

  Future<int> waitForExit({required String containerId}) async {
    final output = await room.invoke(
      toolkit: 'containers',
      tool: 'wait_for_exit',
      input: ToolContentInput(JsonContent(json: {'container_id': containerId})),
    );
    if (output is! ToolContentOutput || output.content is! JsonContent) {
      throw _unexpectedResponseError(operation: 'wait_for_exit');
    }
    final exitCode = (output.content as JsonContent).json['exit_code'];
    if (exitCode is! int) {
      throw _unexpectedResponseError(operation: 'wait_for_exit');
    }
    return exitCode;
  }

  Future<void> deleteContainer({required String containerId}) async {
    await room.invoke(
      toolkit: 'containers',
      tool: 'delete_container',
      input: ToolContentInput(JsonContent(json: {'container_id': containerId})),
    );
  }

  LogStream<void> logs({required String containerId, bool follow = false}) {
    final requestId = const Uuid().v4();
    final closeInput = Completer<void>();
    var inputClosed = false;

    void closeInputStream() {
      if (inputClosed) {
        return;
      }
      inputClosed = true;
      if (!closeInput.isCompleted) {
        closeInput.complete();
      }
    }

    Stream<Content> inputStream() async* {
      yield BinaryContent(
        data: Uint8List(0),
        headers: {'kind': 'start', 'request_id': requestId, 'container_id': containerId, 'follow': follow},
      );
      await closeInput.future;
    }

    final completer = Completer<void>();
    final controller = StreamController<String>(
      onCancel: () async {
        closeInputStream();
        await completer.future.catchError((_) {});
      },
    );
    final progress = StreamController<LogProgress>();

    final stream = LogStream._(completer, controller.stream, progress.stream, () async {
      closeInputStream();
      await completer.future.catchError((_) {});
    });

    room
        .invoke(toolkit: 'containers', tool: 'logs', input: ToolStreamInput(inputStream()))
        .then((output) async {
          if (output is! ToolStreamOutput) {
            throw _unexpectedResponseError(operation: 'logs');
          }

          await for (final chunk in output.stream) {
            if (chunk is ErrorContent) {
              throw RoomServerException(chunk.text, code: chunk.code);
            }
            if (chunk is ControlContent) {
              if (chunk.method == 'close') {
                closeInputStream();
                unawaited(controller.close());
                unawaited(progress.close());
                if (!completer.isCompleted) {
                  completer.complete();
                }
                return;
              }
              throw _unexpectedResponseError(operation: 'logs');
            }
            if (chunk is! BinaryContent) {
              throw _unexpectedResponseError(operation: 'logs');
            }

            final rawChannel = chunk.headers['channel'];
            if (rawChannel is! int) {
              throw RoomServerException('containers.logs returned a chunk without a valid channel');
            }
            if (rawChannel != 1) {
              continue;
            }
            controller.add(_decodeContainerUtf8(chunk.data, operation: 'logs'));
          }
          closeInputStream();
          unawaited(controller.close());
          unawaited(progress.close());
          if (!completer.isCompleted) {
            completer.complete();
          }
        })
        .catchError((Object error) async {
          closeInputStream();
          unawaited(controller.close());
          unawaited(progress.close());
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        });

    return stream;
  }

  LogStream<int?> getBuildLogs({required String buildId, bool follow = true}) {
    final requestId = const Uuid().v4();
    final closeInput = Completer<void>();
    var inputClosed = false;

    void closeInputStream() {
      if (inputClosed) {
        return;
      }
      inputClosed = true;
      if (!closeInput.isCompleted) {
        closeInput.complete();
      }
    }

    Stream<Content> inputStream() async* {
      yield BinaryContent(data: Uint8List(0), headers: {'kind': 'start', 'request_id': requestId, 'build_id': buildId, 'follow': follow});
      await closeInput.future;
    }

    final completer = Completer<int?>();
    final controller = StreamController<String>(
      onCancel: () async {
        closeInputStream();
        await completer.future.catchError((_) => null);
      },
    );
    final progress = StreamController<LogProgress>();

    final stream = LogStream._(completer, controller.stream, progress.stream, () async {
      closeInputStream();
      await completer.future.catchError((_) => null);
    });

    room
        .invoke(toolkit: 'containers', tool: 'get_build_logs', input: ToolStreamInput(inputStream()))
        .then((output) async {
          if (output is! ToolStreamOutput) {
            throw _unexpectedResponseError(operation: 'get_build_logs');
          }

          await for (final chunk in output.stream) {
            if (chunk is ErrorContent) {
              throw RoomServerException(chunk.text, code: chunk.code);
            }
            if (chunk is ControlContent) {
              if (chunk.method == 'close') {
                closeInputStream();
                unawaited(controller.close());
                unawaited(progress.close());
                if (!completer.isCompleted) {
                  completer.complete(null);
                }
                return;
              }
              throw _unexpectedResponseError(operation: 'get_build_logs');
            }
            if (chunk is! BinaryContent) {
              throw _unexpectedResponseError(operation: 'get_build_logs');
            }

            final rawChannel = chunk.headers['channel'];
            if (rawChannel is! int) {
              throw RoomServerException('containers.get_build_logs returned a chunk without a valid channel');
            }
            if (rawChannel == 1) {
              controller.add(_decodeContainerUtf8(chunk.data, operation: 'get_build_logs'));
              continue;
            }
            if (rawChannel == 3) {
              closeInputStream();
              unawaited(controller.close());
              unawaited(progress.close());
              if (!completer.isCompleted) {
                completer.complete(_decodeContainerStatusPayload(chunk.data, operation: 'get_build_logs'));
              }
              return;
            }
          }
          closeInputStream();
          unawaited(controller.close());
          unawaited(progress.close());
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        })
        .catchError((Object error) async {
          closeInputStream();
          unawaited(controller.close());
          unawaited(progress.close());
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        });

    return stream;
  }

  Future<List<RoomContainer>> list({bool? all}) async {
    final output = await room.invoke(
      toolkit: 'containers',
      tool: 'list_containers',
      input: ToolContentInput(JsonContent(json: {'all': all})),
    );
    if (output is! ToolContentOutput || output.content is! JsonContent) {
      throw _unexpectedResponseError(operation: 'list');
    }
    final res = output.content as JsonContent;
    return (res.json['containers'] as List).map((i) => RoomContainer.fromJson(i as Map<String, dynamic>)).toList();
  }
}

class ParticipantInfo {
  ParticipantInfo({required this.id, required this.name});

  final String id;
  final String name;
}

class RoomContainer {
  RoomContainer({
    required this.id,
    required this.image,
    this.name,
    this.ports = const [],
    required this.startedBy,
    required this.state,
    required this.private,
    required this.serviceId,
  });
  final String id;
  final String image;
  final String? name;
  final List<int> ports;
  final ParticipantInfo startedBy;
  final String state;
  final bool private;
  final String? serviceId;

  static RoomContainer fromJson(Map<String, dynamic> json) {
    return RoomContainer(
      id: json["id"],
      image: json["image"],
      name: json["name"],
      ports: ((json["ports"] as List?) ?? const []).map((item) => item as int).toList(),
      startedBy: ParticipantInfo(id: json["started_by"]["id"], name: json["started_by"]["name"]),
      state: json["state"],
      private: json["private"],
      serviceId: json["service_id"],
    );
  }
}

class ServiceRuntimeState {
  ServiceRuntimeState({
    required this.serviceId,
    required this.state,
    required this.containerId,
    required this.restartScheduledAt,
    required this.startedAt,
    required this.restartCount,
    required this.lastExitCode,
    required this.lastExitAt,
  });

  final String serviceId;
  final String state;
  final String? containerId;
  final double? restartScheduledAt;
  final double? startedAt;
  final int restartCount;
  final int? lastExitCode;
  final double? lastExitAt;

  DateTime? get restartScheduledAtTime => _timestampToDateTime(restartScheduledAt);
  DateTime? get startedAtTime => _timestampToDateTime(startedAt);
  DateTime? get lastExitAtTime => _timestampToDateTime(lastExitAt);

  static ServiceRuntimeState fromJson(Map<String, dynamic> json) {
    return ServiceRuntimeState(
      serviceId: json["service_id"] as String,
      state: (json["state"] as String?) ?? "unknown",
      containerId: json["container_id"] as String?,
      restartScheduledAt: _toDouble(json["restart_scheduled_at"]),
      startedAt: _toDouble(json["started_at"]),
      restartCount: _toInt(json["restart_count"]) ?? 0,
      lastExitCode: _toInt(json["last_exit_code"]),
      lastExitAt: _toDouble(json["last_exit_at"]),
    );
  }

  static int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  static double? _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return null;
  }

  static DateTime? _timestampToDateTime(double? timestamp) {
    if (timestamp == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch((timestamp * 1000).round(), isUtc: true).toLocal();
  }
}

class ListServicesResult {
  ListServicesResult({required this.services, required this.serviceStates});

  final List<ServiceSpec> services;
  final Map<String, ServiceRuntimeState> serviceStates;

  static ListServicesResult fromJson(Map<String, dynamic> json) {
    final statesRaw = (json["service_states"] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    return ListServicesResult(
      services: (json["services"] as List).map((item) => ServiceSpec.fromJson((item as Map).cast<String, dynamic>())).toList(),
      serviceStates: {
        for (final entry in statesRaw.entries) entry.key: ServiceRuntimeState.fromJson((entry.value as Map).cast<String, dynamic>()),
      },
    );
  }
}

RoomServerException _memoryUnexpectedResponseError(String operation) {
  return RoomServerException("Invalid return type from memory.$operation call");
}

Map<String, dynamic> _memoryJsonMap(dynamic value, String operation) {
  if (value is! Map) {
    throw _memoryUnexpectedResponseError(operation);
  }
  return Map<String, dynamic>.fromEntries(
    value.entries.map((entry) {
      final key = entry.key;
      if (key is! String) {
        throw _memoryUnexpectedResponseError(operation);
      }
      return MapEntry(key, entry.value);
    }),
  );
}

List<String>? _memoryOptionalStringList(dynamic value, String operation) {
  if (value == null) {
    return null;
  }
  if (value is! List) {
    throw _memoryUnexpectedResponseError(operation);
  }
  return value
      .map((item) {
        if (item is! String) {
          throw _memoryUnexpectedResponseError(operation);
        }
        return item;
      })
      .toList(growable: false);
}

Map<String, String>? _memoryOptionalStringMap(dynamic value, String operation) {
  if (value == null) {
    return null;
  }
  if (value is! Map) {
    throw _memoryUnexpectedResponseError(operation);
  }
  return Map<String, String>.fromEntries(
    value.entries.map((entry) {
      if (entry.key is! String || entry.value is! String) {
        throw _memoryUnexpectedResponseError(operation);
      }
      return MapEntry(entry.key as String, entry.value as String);
    }),
  );
}

String _memoryRequiredString(dynamic value, String operation) {
  if (value is! String) {
    throw _memoryUnexpectedResponseError(operation);
  }
  return value;
}

int? _memoryOptionalInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}

double? _memoryOptionalDouble(dynamic value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  return null;
}

dynamic _memoryDecodeRowsValue(dynamic value, String operation) {
  final json = _memoryJsonMap(value, operation);
  final type = json["type"];
  if (type is! String) {
    throw _memoryUnexpectedResponseError(operation);
  }

  switch (type) {
    case "null":
      return null;
    case "bool":
      final decoded = json["value"];
      if (decoded is! bool) {
        throw _memoryUnexpectedResponseError(operation);
      }
      return decoded;
    case "int":
      final decoded = _memoryOptionalInt(json["value"]);
      if (decoded == null) {
        throw _memoryUnexpectedResponseError(operation);
      }
      return decoded;
    case "float":
      final decoded = _memoryOptionalDouble(json["value"]);
      if (decoded == null) {
        throw _memoryUnexpectedResponseError(operation);
      }
      return decoded;
    case "text":
    case "date":
    case "timestamp":
      final decoded = json["value"];
      if (decoded is! String) {
        throw _memoryUnexpectedResponseError(operation);
      }
      return decoded;
    case "binary":
      final data = json["data"];
      if (data is! String) {
        throw _memoryUnexpectedResponseError(operation);
      }
      return base64Decode(data);
    case "list":
      final items = json["items"];
      if (items is! List) {
        throw _memoryUnexpectedResponseError(operation);
      }
      return items.map((item) => _memoryDecodeRowsValue(item, operation)).toList(growable: false);
    case "struct":
      final fields = json["fields"];
      if (fields is! List) {
        throw _memoryUnexpectedResponseError(operation);
      }
      return Map<String, dynamic>.fromEntries(
        fields.map((field) {
          final fieldJson = _memoryJsonMap(field, operation);
          final name = fieldJson["name"];
          if (name is! String) {
            throw _memoryUnexpectedResponseError(operation);
          }
          return MapEntry(name, _memoryDecodeRowsValue(fieldJson["value"], operation));
        }),
      );
  }

  throw _memoryUnexpectedResponseError(operation);
}

List<Map<String, dynamic>> _memoryRecordsFromRowsChunk(Map<String, dynamic> json, String operation) {
  if (json["kind"] != "rows") {
    throw _memoryUnexpectedResponseError(operation);
  }
  final rows = json["rows"];
  if (rows is! List) {
    throw _memoryUnexpectedResponseError(operation);
  }

  return rows
      .map((row) {
        final rowJson = _memoryJsonMap(row, operation);
        final columns = rowJson["columns"];
        if (columns is! List) {
          throw _memoryUnexpectedResponseError(operation);
        }
        return Map<String, dynamic>.fromEntries(
          columns.map((column) {
            final columnJson = _memoryJsonMap(column, operation);
            final name = columnJson["name"];
            if (name is! String) {
              throw _memoryUnexpectedResponseError(operation);
            }
            return MapEntry(name, _memoryDecodeRowsValue(columnJson["value"], operation));
          }),
        );
      })
      .toList(growable: false);
}

enum MemoryIngestStrategy { heuristic, llm }

extension MemoryIngestStrategyValue on MemoryIngestStrategy {
  String get value {
    switch (this) {
      case MemoryIngestStrategy.heuristic:
        return "heuristic";
      case MemoryIngestStrategy.llm:
        return "llm";
    }
  }
}

class MemoryEntityRecord {
  MemoryEntityRecord({
    this.entityId,
    required this.name,
    this.entityType,
    this.context,
    this.confidence,
    this.createdAt,
    this.validAt,
    this.metadata,
  });

  final String? entityId;
  final String name;
  final String? entityType;
  final String? context;
  final double? confidence;
  final String? createdAt;
  final String? validAt;
  final Map<String, String>? metadata;

  factory MemoryEntityRecord.fromJson(Map<String, dynamic> json) {
    return MemoryEntityRecord(
      entityId: json["entity_id"] as String?,
      name: _memoryRequiredString(json["name"], "upsert_nodes"),
      entityType: json["entity_type"] as String?,
      context: json["context"] as String?,
      confidence: _memoryOptionalDouble(json["confidence"]),
      createdAt: json["created_at"] as String?,
      validAt: json["valid_at"] as String?,
      metadata: _memoryOptionalStringMap(json["metadata"], "upsert_nodes"),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "entity_id": entityId,
      "name": name,
      "entity_type": entityType,
      "context": context,
      "confidence": confidence,
      "created_at": createdAt,
      "valid_at": validAt,
      "metadata": metadata,
    };
  }
}

class MemoryRelationshipRecord {
  MemoryRelationshipRecord({
    required this.sourceEntityId,
    required this.targetEntityId,
    this.relationshipType = "RELATED_TO",
    this.description,
    this.confidence,
    this.createdAt,
    this.validAt,
    this.expiredAt,
    this.invalidAt,
    this.sourceEntityName,
    this.targetEntityName,
    this.metadata,
  });

  final String sourceEntityId;
  final String targetEntityId;
  final String relationshipType;
  final String? description;
  final double? confidence;
  final String? createdAt;
  final String? validAt;
  final String? expiredAt;
  final String? invalidAt;
  final String? sourceEntityName;
  final String? targetEntityName;
  final Map<String, String>? metadata;

  factory MemoryRelationshipRecord.fromJson(Map<String, dynamic> json) {
    final relationshipType = json["relationship_type"];
    return MemoryRelationshipRecord(
      sourceEntityId: _memoryRequiredString(json["source_entity_id"], "upsert_relationships"),
      targetEntityId: _memoryRequiredString(json["target_entity_id"], "upsert_relationships"),
      relationshipType: relationshipType is String && relationshipType.isNotEmpty ? relationshipType : "RELATED_TO",
      description: json["description"] as String?,
      confidence: _memoryOptionalDouble(json["confidence"]),
      createdAt: json["created_at"] as String?,
      validAt: json["valid_at"] as String?,
      expiredAt: json["expired_at"] as String?,
      invalidAt: json["invalid_at"] as String?,
      sourceEntityName: json["source_entity_name"] as String?,
      targetEntityName: json["target_entity_name"] as String?,
      metadata: _memoryOptionalStringMap(json["metadata"], "upsert_relationships"),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "source_entity_id": sourceEntityId,
      "target_entity_id": targetEntityId,
      "relationship_type": relationshipType,
      "description": description,
      "confidence": confidence,
      "created_at": createdAt,
      "valid_at": validAt,
      "expired_at": expiredAt,
      "invalid_at": invalidAt,
      "source_entity_name": sourceEntityName,
      "target_entity_name": targetEntityName,
      "metadata": metadata,
    };
  }
}

class MemoryDatasetSummary {
  MemoryDatasetSummary({required this.name, required this.rows, required this.columns});

  final String name;
  final int rows;
  final List<String> columns;

  factory MemoryDatasetSummary.fromJson(Map<String, dynamic> json) {
    return MemoryDatasetSummary(
      name: _memoryRequiredString(json["name"], "inspect"),
      rows: _memoryOptionalInt(json["rows"]) ?? 0,
      columns: _memoryOptionalStringList(json["columns"], "inspect") ?? const <String>[],
    );
  }

  Map<String, dynamic> toJson() {
    return {"name": name, "rows": rows, "columns": columns};
  }
}

class MemoryDetails {
  MemoryDetails({required this.name, required this.namespace, required this.path, required this.datasets});

  final String name;
  final List<String>? namespace;
  final String path;
  final List<MemoryDatasetSummary> datasets;

  factory MemoryDetails.fromJson(Map<String, dynamic> json) {
    final rawDatasets = json["datasets"];
    if (rawDatasets != null && rawDatasets is! List) {
      throw _memoryUnexpectedResponseError("inspect");
    }

    return MemoryDetails(
      name: _memoryRequiredString(json["name"], "inspect"),
      namespace: _memoryOptionalStringList(json["namespace"], "inspect"),
      path: _memoryRequiredString(json["path"], "inspect"),
      datasets: (rawDatasets as List? ?? const [])
          .map((item) => MemoryDatasetSummary.fromJson(_memoryJsonMap(item, "inspect")))
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "name": name,
      "namespace": namespace,
      "path": path,
      "datasets": datasets.map((entry) => entry.toJson()).toList(growable: false),
    };
  }
}

class MemoryIngestStats {
  MemoryIngestStats({required this.entities, required this.relationships, required this.sources});

  final int entities;
  final int relationships;
  final int sources;

  factory MemoryIngestStats.fromJson(Map<String, dynamic> json) {
    return MemoryIngestStats(
      entities: _memoryOptionalInt(json["entities"]) ?? 0,
      relationships: _memoryOptionalInt(json["relationships"]) ?? 0,
      sources: _memoryOptionalInt(json["sources"]) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {"entities": entities, "relationships": relationships, "sources": sources};
  }
}

class MemoryIngestResult {
  MemoryIngestResult({required this.name, required this.stats, required this.entityIds});

  final String name;
  final MemoryIngestStats stats;
  final List<String> entityIds;

  factory MemoryIngestResult.fromJson(Map<String, dynamic> json, {String operation = "ingest_text"}) {
    return MemoryIngestResult(
      name: _memoryRequiredString(json["name"], operation),
      stats: MemoryIngestStats.fromJson(_memoryJsonMap(json["stats"], operation)),
      entityIds: _memoryOptionalStringList(json["entity_ids"], operation) ?? const <String>[],
    );
  }

  Map<String, dynamic> toJson() {
    return {"name": name, "stats": stats.toJson(), "entity_ids": entityIds};
  }
}

class MemoryRecallRelationship {
  MemoryRecallRelationship({
    required this.sourceEntityId,
    required this.targetEntityId,
    required this.relationshipType,
    this.description,
    this.createdAt,
    this.validAt,
    this.expiredAt,
    this.invalidAt,
  });

  final String sourceEntityId;
  final String targetEntityId;
  final String relationshipType;
  final String? description;
  final String? createdAt;
  final String? validAt;
  final String? expiredAt;
  final String? invalidAt;

  factory MemoryRecallRelationship.fromJson(Map<String, dynamic> json) {
    return MemoryRecallRelationship(
      sourceEntityId: _memoryRequiredString(json["source_entity_id"], "recall"),
      targetEntityId: _memoryRequiredString(json["target_entity_id"], "recall"),
      relationshipType: _memoryRequiredString(json["relationship_type"], "recall"),
      description: json["description"] as String?,
      createdAt: json["created_at"] as String?,
      validAt: json["valid_at"] as String?,
      expiredAt: json["expired_at"] as String?,
      invalidAt: json["invalid_at"] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "source_entity_id": sourceEntityId,
      "target_entity_id": targetEntityId,
      "relationship_type": relationshipType,
      "description": description,
      "created_at": createdAt,
      "valid_at": validAt,
      "expired_at": expiredAt,
      "invalid_at": invalidAt,
    };
  }
}

class MemoryRecallItem {
  MemoryRecallItem({
    required this.entityId,
    required this.name,
    required this.entityType,
    this.context,
    this.confidence,
    this.createdAt,
    this.validAt,
    required this.score,
    required this.relationships,
  });

  final String entityId;
  final String name;
  final String entityType;
  final String? context;
  final double? confidence;
  final String? createdAt;
  final String? validAt;
  final double score;
  final List<MemoryRecallRelationship> relationships;

  factory MemoryRecallItem.fromJson(Map<String, dynamic> json) {
    final rawRelationships = json["relationships"];
    if (rawRelationships != null && rawRelationships is! List) {
      throw _memoryUnexpectedResponseError("recall");
    }

    final score = _memoryOptionalDouble(json["score"]);
    if (score == null) {
      throw _memoryUnexpectedResponseError("recall");
    }

    return MemoryRecallItem(
      entityId: _memoryRequiredString(json["entity_id"], "recall"),
      name: _memoryRequiredString(json["name"], "recall"),
      entityType: _memoryRequiredString(json["entity_type"], "recall"),
      context: json["context"] as String?,
      confidence: _memoryOptionalDouble(json["confidence"]),
      createdAt: json["created_at"] as String?,
      validAt: json["valid_at"] as String?,
      score: score,
      relationships: (rawRelationships as List? ?? const [])
          .map((item) => MemoryRecallRelationship.fromJson(_memoryJsonMap(item, "recall")))
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "entity_id": entityId,
      "name": name,
      "entity_type": entityType,
      "context": context,
      "confidence": confidence,
      "created_at": createdAt,
      "valid_at": validAt,
      "score": score,
      "relationships": relationships.map((entry) => entry.toJson()).toList(growable: false),
    };
  }
}

class MemoryRecallResult {
  MemoryRecallResult({required this.name, required this.query, required this.items});

  final String name;
  final String query;
  final List<MemoryRecallItem> items;

  factory MemoryRecallResult.fromJson(Map<String, dynamic> json) {
    final rawItems = json["items"];
    if (rawItems != null && rawItems is! List) {
      throw _memoryUnexpectedResponseError("recall");
    }

    return MemoryRecallResult(
      name: _memoryRequiredString(json["name"], "recall"),
      query: _memoryRequiredString(json["query"], "recall"),
      items: (rawItems as List? ?? const [])
          .map((item) => MemoryRecallItem.fromJson(_memoryJsonMap(item, "recall")))
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return {"name": name, "query": query, "items": items.map((entry) => entry.toJson()).toList(growable: false)};
  }
}

class MemoryDeleteEntitiesResult {
  MemoryDeleteEntitiesResult({required this.name, required this.deletedEntities, required this.deletedRelationships});

  final String name;
  final int deletedEntities;
  final int deletedRelationships;

  factory MemoryDeleteEntitiesResult.fromJson(Map<String, dynamic> json) {
    return MemoryDeleteEntitiesResult(
      name: _memoryRequiredString(json["name"], "delete_entities"),
      deletedEntities: _memoryOptionalInt(json["deleted_entities"]) ?? 0,
      deletedRelationships: _memoryOptionalInt(json["deleted_relationships"]) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {"name": name, "deleted_entities": deletedEntities, "deleted_relationships": deletedRelationships};
  }
}

class MemoryRelationshipSelector {
  MemoryRelationshipSelector({required this.sourceEntityId, required this.targetEntityId, this.relationshipType});

  final String sourceEntityId;
  final String targetEntityId;
  final String? relationshipType;

  factory MemoryRelationshipSelector.fromJson(Map<String, dynamic> json) {
    return MemoryRelationshipSelector(
      sourceEntityId: _memoryRequiredString(json["source_entity_id"], "delete_relationships"),
      targetEntityId: _memoryRequiredString(json["target_entity_id"], "delete_relationships"),
      relationshipType: json["relationship_type"] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {"source_entity_id": sourceEntityId, "target_entity_id": targetEntityId, "relationship_type": relationshipType};
  }
}

class MemoryDeleteRelationshipsResult {
  MemoryDeleteRelationshipsResult({required this.name, required this.deletedRelationships});

  final String name;
  final int deletedRelationships;

  factory MemoryDeleteRelationshipsResult.fromJson(Map<String, dynamic> json) {
    return MemoryDeleteRelationshipsResult(
      name: _memoryRequiredString(json["name"], "delete_relationships"),
      deletedRelationships: _memoryOptionalInt(json["deleted_relationships"]) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {"name": name, "deleted_relationships": deletedRelationships};
  }
}

class MemoryOptimizeDatasetStats {
  MemoryOptimizeDatasetStats({
    required this.dataset,
    required this.fragmentsAdded,
    required this.fragmentsRemoved,
    required this.filesAdded,
    required this.filesRemoved,
    required this.oldVersionsRemoved,
    required this.bytesRemoved,
  });

  final String dataset;
  final int fragmentsAdded;
  final int fragmentsRemoved;
  final int filesAdded;
  final int filesRemoved;
  final int oldVersionsRemoved;
  final int bytesRemoved;

  factory MemoryOptimizeDatasetStats.fromJson(Map<String, dynamic> json) {
    return MemoryOptimizeDatasetStats(
      dataset: _memoryRequiredString(json["dataset"], "optimize"),
      fragmentsAdded: _memoryOptionalInt(json["fragments_added"]) ?? 0,
      fragmentsRemoved: _memoryOptionalInt(json["fragments_removed"]) ?? 0,
      filesAdded: _memoryOptionalInt(json["files_added"]) ?? 0,
      filesRemoved: _memoryOptionalInt(json["files_removed"]) ?? 0,
      oldVersionsRemoved: _memoryOptionalInt(json["old_versions_removed"]) ?? 0,
      bytesRemoved: _memoryOptionalInt(json["bytes_removed"]) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "dataset": dataset,
      "fragments_added": fragmentsAdded,
      "fragments_removed": fragmentsRemoved,
      "files_added": filesAdded,
      "files_removed": filesRemoved,
      "old_versions_removed": oldVersionsRemoved,
      "bytes_removed": bytesRemoved,
    };
  }
}

class MemoryOptimizeResult {
  MemoryOptimizeResult({required this.name, required this.datasets});

  final String name;
  final List<MemoryOptimizeDatasetStats> datasets;

  factory MemoryOptimizeResult.fromJson(Map<String, dynamic> json) {
    final rawDatasets = json["datasets"];
    if (rawDatasets != null && rawDatasets is! List) {
      throw _memoryUnexpectedResponseError("optimize");
    }

    return MemoryOptimizeResult(
      name: _memoryRequiredString(json["name"], "optimize"),
      datasets: (rawDatasets as List? ?? const [])
          .map((item) => MemoryOptimizeDatasetStats.fromJson(_memoryJsonMap(item, "optimize")))
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return {"name": name, "datasets": datasets.map((entry) => entry.toJson()).toList(growable: false)};
  }
}

class MemoryClient {
  MemoryClient({required this.room});

  final RoomClient room;

  RoomServerException _unexpectedResponseError(String operation) {
    return _memoryUnexpectedResponseError(operation);
  }

  Future<Content> _invoke(String operation, Map<String, dynamic> input) async {
    final output = await room.invoke(
      toolkit: "memory",
      tool: operation,
      input: ToolContentInput(JsonContent(json: input)),
    );
    if (output is! ToolContentOutput) {
      throw _unexpectedResponseError(operation);
    }
    return output.content;
  }

  Future<JsonContent> _invokeJson(String operation, Map<String, dynamic> input) async {
    final response = await _invoke(operation, input);
    if (response is! JsonContent) {
      throw _unexpectedResponseError(operation);
    }
    return response;
  }

  Future<List<String>> list({List<String>? namespace}) async {
    final response = await _invokeJson("list", {"namespace": namespace});
    final memories = response.json["memories"];
    if (memories is! List) {
      return [];
    }
    return memories.whereType<String>().toList();
  }

  Future<void> create({required String name, List<String>? namespace, bool overwrite = false, bool ignoreExists = false}) async {
    await _invoke("create", {"name": name, "namespace": namespace, "overwrite": overwrite, "ignore_exists": ignoreExists});
  }

  Future<void> drop({required String name, List<String>? namespace, bool ignoreMissing = false}) async {
    await _invoke("drop", {"name": name, "namespace": namespace, "ignore_missing": ignoreMissing});
  }

  Future<MemoryDetails> inspect({required String name, List<String>? namespace}) async {
    final response = await _invokeJson("inspect", {"name": name, "namespace": namespace});
    return MemoryDetails.fromJson(response.json);
  }

  Future<List<Map<String, dynamic>>> query({required String name, required String statement, List<String>? namespace}) async {
    final response = await _invokeJson("query", {"name": name, "namespace": namespace, "statement": statement});
    final results = response.json["results"];
    if (results is List) {
      return results.map((item) => _memoryJsonMap(item, "query")).toList(growable: false);
    }
    return _memoryRecordsFromRowsChunk(response.json, "query");
  }

  Future<void> upsertTable({
    required String name,
    required String table,
    required List<Map<String, dynamic>> records,
    List<String>? namespace,
    bool merge = true,
  }) async {
    await _invoke("upsert_table", {
      "name": name,
      "namespace": namespace,
      "table": table,
      "records_json": jsonEncode(encodeRecords(records)),
      "merge": merge,
    });
  }

  Future<void> upsertNodes({
    required String name,
    required List<MemoryEntityRecord> records,
    List<String>? namespace,
    bool merge = true,
  }) async {
    await _invoke("upsert_nodes", {
      "name": name,
      "namespace": namespace,
      "records_json": jsonEncode(records.map((record) => record.toJson()).toList(growable: false)),
      "merge": merge,
    });
  }

  Future<void> upsertRelationships({
    required String name,
    required List<MemoryRelationshipRecord> records,
    List<String>? namespace,
    bool merge = true,
  }) async {
    await _invoke("upsert_relationships", {
      "name": name,
      "namespace": namespace,
      "records_json": jsonEncode(records.map((record) => record.toJson()).toList(growable: false)),
      "merge": merge,
    });
  }

  Future<MemoryIngestResult> ingestText({
    required String name,
    required String text,
    List<String>? namespace,
    MemoryIngestStrategy strategy = MemoryIngestStrategy.heuristic,
    String? llmModel,
    double? llmTemperature,
  }) async {
    final response = await _invokeJson("ingest_text", {
      "name": name,
      "namespace": namespace,
      "text": text,
      "strategy": strategy.value,
      "llm_model": llmModel,
      "llm_temperature": llmTemperature,
    });
    return MemoryIngestResult.fromJson(response.json, operation: "ingest_text");
  }

  Future<MemoryIngestResult> ingestImage({
    required String name,
    String? caption,
    Uint8List? data,
    String? mimeType,
    String? source,
    Map<String, String>? annotations,
    List<String>? namespace,
    MemoryIngestStrategy strategy = MemoryIngestStrategy.heuristic,
    String? llmModel,
    double? llmTemperature,
  }) async {
    final response = await _invokeJson("ingest_image", {
      "name": name,
      "namespace": namespace,
      "caption": caption,
      "data_base64": data == null ? null : base64Encode(data),
      "mime_type": mimeType,
      "source": source,
      "annotations_json": annotations == null ? null : jsonEncode(annotations),
      "strategy": strategy.value,
      "llm_model": llmModel,
      "llm_temperature": llmTemperature,
    });
    return MemoryIngestResult.fromJson(response.json, operation: "ingest_image");
  }

  Future<MemoryIngestResult> ingestFile({
    required String name,
    String? path,
    String? text,
    String? mimeType,
    List<String>? namespace,
    MemoryIngestStrategy strategy = MemoryIngestStrategy.heuristic,
    String? llmModel,
    double? llmTemperature,
  }) async {
    final response = await _invokeJson("ingest_file", {
      "name": name,
      "namespace": namespace,
      "path": path,
      "text": text,
      "mime_type": mimeType,
      "strategy": strategy.value,
      "llm_model": llmModel,
      "llm_temperature": llmTemperature,
    });
    return MemoryIngestResult.fromJson(response.json, operation: "ingest_file");
  }

  Future<MemoryIngestResult> ingestFromTable({
    required String name,
    required String table,
    List<String>? textColumns,
    List<String>? tableNamespace,
    int? limit,
    List<String>? namespace,
    MemoryIngestStrategy strategy = MemoryIngestStrategy.heuristic,
    String? llmModel,
    double? llmTemperature,
  }) async {
    final response = await _invokeJson("ingest_from_table", {
      "name": name,
      "namespace": namespace,
      "table": table,
      "table_namespace": tableNamespace,
      "text_columns": textColumns,
      "limit": limit,
      "strategy": strategy.value,
      "llm_model": llmModel,
      "llm_temperature": llmTemperature,
    });
    return MemoryIngestResult.fromJson(response.json, operation: "ingest_from_table");
  }

  Future<MemoryIngestResult> ingestFromStorage({
    required String name,
    required List<String> paths,
    List<String>? namespace,
    MemoryIngestStrategy strategy = MemoryIngestStrategy.heuristic,
    String? llmModel,
    double? llmTemperature,
  }) async {
    final response = await _invokeJson("ingest_from_storage", {
      "name": name,
      "namespace": namespace,
      "paths": paths,
      "strategy": strategy.value,
      "llm_model": llmModel,
      "llm_temperature": llmTemperature,
    });
    return MemoryIngestResult.fromJson(response.json, operation: "ingest_from_storage");
  }

  Future<MemoryRecallResult> recall({
    required String name,
    required String query,
    List<String>? namespace,
    int limit = 5,
    bool includeRelationships = true,
  }) async {
    final response = await _invokeJson("recall", {
      "name": name,
      "namespace": namespace,
      "query": query,
      "limit": limit,
      "include_relationships": includeRelationships,
    });
    return MemoryRecallResult.fromJson(response.json);
  }

  Future<MemoryDeleteEntitiesResult> deleteEntities({
    required String name,
    required List<String> entityIds,
    List<String>? namespace,
  }) async {
    final response = await _invokeJson("delete_entities", {"name": name, "namespace": namespace, "entity_ids": entityIds});
    return MemoryDeleteEntitiesResult.fromJson(response.json);
  }

  Future<MemoryDeleteRelationshipsResult> deleteRelationships({
    required String name,
    required List<MemoryRelationshipSelector> relationships,
    List<String>? namespace,
  }) async {
    final response = await _invokeJson("delete_relationships", {
      "name": name,
      "namespace": namespace,
      "relationships": relationships.map((relationship) => relationship.toJson()).toList(growable: false),
    });
    return MemoryDeleteRelationshipsResult.fromJson(response.json);
  }

  Future<MemoryOptimizeResult> optimize({required String name, List<String>? namespace, bool compact = true, bool cleanup = true}) async {
    final response = await _invokeJson("optimize", {"name": name, "namespace": namespace, "compact": compact, "cleanup": cleanup});
    return MemoryOptimizeResult.fromJson(response.json);
  }
}

class ServicesClient {
  ServicesClient({required this.room});

  final RoomClient room;

  RoomServerException _unexpectedResponseError(String operation) {
    return RoomServerException("unexpected return type from services.$operation");
  }

  Future<List<ServiceSpec>> list() async {
    return (await listWithState()).services;
  }

  Future<ListServicesResult> listWithState() async {
    final output = await room.invoke(
      toolkit: "services",
      tool: "list",
      input: ToolContentInput(JsonContent(json: {})),
    );
    if (output is! ToolContentOutput || output.content is! JsonContent) {
      throw _unexpectedResponseError("list");
    }

    final response = output.content as JsonContent;
    final servicesRaw = response.json["services_json"];
    final serviceStatesRaw = response.json["service_states"];
    if (servicesRaw is! List || serviceStatesRaw is! List) {
      throw _unexpectedResponseError("list");
    }

    final serviceStates = <String, ServiceRuntimeState>{};
    for (final item in serviceStatesRaw) {
      if (item is! Map) {
        throw _unexpectedResponseError("list");
      }
      final state = ServiceRuntimeState.fromJson(Map<String, dynamic>.from(item));
      serviceStates[state.serviceId] = state;
    }

    return ListServicesResult(
      services: servicesRaw.map((item) {
        if (item is! String) {
          throw _unexpectedResponseError("list");
        }
        final decoded = jsonDecode(item);
        if (decoded is! Map) {
          throw _unexpectedResponseError("list");
        }
        return ServiceSpec.fromJson(Map<String, dynamic>.from(decoded));
      }).toList(),
      serviceStates: serviceStates,
    );
  }

  Future<void> restart({required String serviceId}) async {
    await room.invoke(
      toolkit: "services",
      tool: "restart",
      input: ToolContentInput(JsonContent(json: {"service_id": serviceId})),
    );
  }
}

String _normalizeSyncPath(String path) {
  var normalized = path;
  while (normalized.startsWith("./")) {
    normalized = normalized.substring(2);
  }
  while (normalized.startsWith("/")) {
    normalized = normalized.substring(1);
  }
  if (normalized == ".") {
    return "";
  }
  return normalized;
}

class _SyncOpenStartChunkHeaders {
  _SyncOpenStartChunkHeaders({
    required this.path,
    required this.create,
    required this.vector,
    required this.schemaJson,
    required this.schemaPath,
    required this.initialJson,
  });

  final String path;
  final bool create;
  final String? vector;
  final Map<String, dynamic>? schemaJson;
  final String? schemaPath;
  final Map<String, dynamic>? initialJson;

  Map<String, dynamic> toHeaders() {
    return {
      "kind": "start",
      "path": path,
      "create": create,
      "vector": vector,
      "schema": schemaJson,
      "schema_path": schemaPath,
      "initial_json": initialJson,
    };
  }
}

class _SyncOpenStateChunkHeaders {
  _SyncOpenStateChunkHeaders({required this.path, required this.schemaJson});

  final String path;
  final Map<String, dynamic> schemaJson;

  static _SyncOpenStateChunkHeaders fromHeaders(Map<String, dynamic> headers) {
    final kind = headers["kind"];
    final path = headers["path"];
    final schemaJson = headers["schema"];
    if (kind != "state" || path is! String || schemaJson is! Map) {
      throw RoomServerException("Invalid return type from sync.open call");
    }
    return _SyncOpenStateChunkHeaders(path: path, schemaJson: Map<String, dynamic>.from(schemaJson));
  }
}

class _SyncOpenOutputChunkHeaders {
  _SyncOpenOutputChunkHeaders({required this.path, required this.kind});

  final String path;
  final String kind;

  static _SyncOpenOutputChunkHeaders fromHeaders(Map<String, dynamic> headers) {
    final kind = headers["kind"];
    final path = headers["path"];
    if ((kind != "state" && kind != "sync") || path is! String) {
      throw RoomServerException("Invalid return type from sync.open call");
    }
    return _SyncOpenOutputChunkHeaders(path: path, kind: kind as String);
  }
}

class _SyncOpenStreamState {
  _SyncOpenStreamState({
    required this.path,
    required this.create,
    required this.vector,
    required this.schemaJson,
    required this.schemaPath,
    required this.initialJson,
  });

  final String path;
  final bool create;
  final String? vector;
  final Map<String, dynamic>? schemaJson;
  final String? schemaPath;
  final Map<String, dynamic>? initialJson;

  final _input = StreamController<Content>();
  Future<void>? _task;
  Object? _error;
  StackTrace? _errorStackTrace;
  bool _inputClosed = false;

  Stream<Content> inputStream() async* {
    yield BinaryContent(
      data: Uint8List(0),
      headers: _SyncOpenStartChunkHeaders(
        path: path,
        create: create,
        vector: vector,
        schemaJson: schemaJson,
        schemaPath: schemaPath,
        initialJson: initialJson,
      ).toHeaders(),
    );
    yield* _input.stream;
  }

  void attachTask(Future<void> task) {
    _task = task;
    unawaited(
      task
          .catchError((Object error, StackTrace stackTrace) {
            _error = error;
            _errorStackTrace = stackTrace;
          })
          .whenComplete(closeInputStream),
    );
  }

  void closeInputStream() {
    if (_inputClosed) {
      return;
    }
    _inputClosed = true;
    unawaited(_input.close());
  }

  void queueSync(Uint8List data) {
    final error = _error;
    if (error != null) {
      final stackTrace = _errorStackTrace;
      if (stackTrace != null) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      throw error;
    }
    if (_inputClosed) {
      throw RoomServerException("attempted to sync to a document that is not connected");
    }
    _input.add(BinaryContent(data: data, headers: {"kind": "sync"}));
  }

  Future<void> wait() async {
    final task = _task;
    if (task != null) {
      await task;
    }
  }
}

class _SyncOpenDocumentConfig {
  const _SyncOpenDocumentConfig({required this.create, required this.schemaJson, required this.schemaPath});

  final bool create;
  final Map<String, dynamic>? schemaJson;
  final String? schemaPath;
}

class SyncClient extends ChangeEmitter {
  SyncClient({required this.room});

  void start() {
    if (_started) {
      throw RoomServerException("client already started");
    }
    _started = true;
  }

  void dispose() {
    for (final streamState in _documentStreams.values) {
      streamState.closeInputStream();
    }
    _documentStreams.clear();
    _documentConfigs.clear();
    _reconnectBaseVectors.clear();
    for (final doc in _connectedDocuments.values) {
      DocumentRuntime.instance!.unregisterDocument(doc.ref);
    }
    _connectedDocuments.clear();
    _connectingDocuments.clear();
    _closingDocuments.clear();
    _started = false;
  }

  final _connectingDocuments = <String, Future<_RefCount<MeshDocument>>>{};
  final _closingDocuments = <String, Future<void>>{};
  final _connectedDocuments = <String, _RefCount<MeshDocument>>{};
  final _documentStreams = <String, _SyncOpenStreamState>{};
  final _documentConfigs = <String, _SyncOpenDocumentConfig>{};
  final _reconnectBaseVectors = <String, Uint8List>{};
  bool _started = false;

  void _applySyncPayload(_RefCount<MeshDocument> doc, Uint8List payload) {
    if (payload.isNotEmpty) {
      final base64 = utf8.decode(payload);
      DocumentRuntime.instance!.applyBackendChanges(documentId: doc.ref.id, base64: base64);
    }

    if (!doc.ref._synchronized.isCompleted) {
      doc.ref._synchronized.complete(true);
    }
  }

  RoomServerException _unexpectedResponseError({required String operation}) {
    return RoomServerException("unexpected return type from sync.$operation");
  }

  Future<ToolCallOutput> _invoke(String operation, ToolInput input) async {
    final output = await room.invoke(toolkit: "sync", tool: operation, input: input);
    return output;
  }

  Future<void> create(String path, [Map<String, dynamic>? json]) async {
    final normalizedPath = _normalizeSyncPath(path);
    final output = await _invoke(
      "create",
      ToolContentInput(JsonContent(json: {"path": normalizedPath, "json": json, "schema": null, "schema_path": null})),
    );
    if (output is! ToolContentOutput) {
      throw _unexpectedResponseError(operation: "create");
    }
  }

  Future<MeshDocument> open(String path, {bool create = true, Map<String, dynamic>? initialJson, MeshSchema? schema}) async {
    final normalizedPath = _normalizeSyncPath(path);
    final closing = _closingDocuments[normalizedPath];
    if (closing != null) {
      await closing;
    }
    final pending = _connectingDocuments[normalizedPath];

    if (pending != null) {
      await pending;
    }

    if (_connectedDocuments[normalizedPath] != null) {
      final connectedDoc = _connectedDocuments[normalizedPath];
      connectedDoc!.count++;
      return connectedDoc.ref;
    }

    final c = Completer<_RefCount<MeshDocument>>();
    _connectingDocuments[normalizedPath] = c.future;
    try {
      final config = _SyncOpenDocumentConfig(create: create, schemaJson: schema?.toJson(), schemaPath: null);
      final openResult = await _openStream(path: normalizedPath, config: config, vector: null, initialJson: initialJson);
      schema = MeshSchema.fromJson(openResult.stateHeaders.schemaJson);

      final doc = MeshDocument(
        schema: schema,
        sendChangesToBackend: (base64) {
          final currentStream = _documentStreams[normalizedPath];
          if (currentStream == null) {
            _roomClientLogger.fine('dropping sync for disconnected document stream $normalizedPath');
            return;
          }
          try {
            currentStream.queueSync(Uint8List.fromList(utf8.encode(base64)));
          } catch (error, stackTrace) {
            _roomClientLogger.log(Level.FINE, 'dropping sync for closed document stream $normalizedPath', error, stackTrace);
          }
        },
      );
      final rc = _RefCount(doc);
      _connectedDocuments[normalizedPath] = rc;
      _documentConfigs[normalizedPath] = config;
      _documentStreams[normalizedPath] = openResult.streamState;
      _reconnectBaseVectors.remove(normalizedPath);
      _applySyncPayload(rc, openResult.firstChunk.data);
      _attachStreamConsumer(path: normalizedPath, doc: rc, streamState: openResult.streamState, iterator: openResult.iterator);
      notifyListeners();

      c.complete(rc);
      await doc.synchronized;
      return doc;
    } catch (err) {
      c.completeError(err);
      rethrow;
    } finally {
      _connectingDocuments.remove(normalizedPath);
    }
  }

  Future<void> close(String path) async {
    final normalizedPath = _normalizeSyncPath(path);
    if (!_connectedDocuments.containsKey(normalizedPath)) {
      throw RoomServerException("Not connected to $normalizedPath");
    }

    final doc = _connectedDocuments[normalizedPath];
    doc!.count--;
    if (doc.count == 0) {
      _connectedDocuments.remove(normalizedPath);
      _documentConfigs.remove(normalizedPath);
      _reconnectBaseVectors.remove(normalizedPath);
      final streamState = _documentStreams.remove(normalizedPath);
      late final Future<void> closeFuture;
      closeFuture = () async {
        if (streamState != null) {
          streamState.closeInputStream();
          try {
            await streamState.wait();
          } finally {
            DocumentRuntime.instance!.unregisterDocument(doc.ref);
          }
        } else {
          DocumentRuntime.instance!.unregisterDocument(doc.ref);
        }
      }();
      _closingDocuments[normalizedPath] = closeFuture;
      try {
        await closeFuture;
      } finally {
        if (identical(_closingDocuments[normalizedPath], closeFuture)) {
          _closingDocuments.remove(normalizedPath);
        }
      }
    }
  }

  Future<void> sync(String path, Uint8List data) async {
    final normalizedPath = _normalizeSyncPath(path);
    if (!_connectedDocuments.containsKey(normalizedPath)) {
      throw RoomServerException("attempted to sync to a document that is not connected");
    }
    final streamState = _documentStreams[normalizedPath];
    if (streamState == null) {
      throw RoomServerException("attempted to sync to a document that is not connected");
    }
    streamState.queueSync(data);
  }

  Future<void> _consumeOpenStream({
    required String path,
    required _RefCount<MeshDocument> doc,
    required StreamIterator<Content> iterator,
    required _SyncOpenStreamState streamState,
  }) async {
    try {
      while (await iterator.moveNext()) {
        final chunk = iterator.current;
        if (chunk is ErrorContent) {
          throw RoomServerException(chunk.text, code: chunk.code);
        }
        if (chunk is ControlContent) {
          if (chunk.method == "close") {
            return;
          }
          throw _unexpectedResponseError(operation: "open");
        }
        if (chunk is! BinaryContent) {
          throw _unexpectedResponseError(operation: "open");
        }

        final headers = _SyncOpenOutputChunkHeaders.fromHeaders(chunk.headers);
        if (_normalizeSyncPath(headers.path) != path) {
          throw RoomServerException("sync.open stream returned a mismatched path");
        }
        _applySyncPayload(doc, chunk.data);
      }
    } finally {
      streamState.closeInputStream();
      await iterator.cancel();
    }
  }

  Future<_SyncOpenResult> _openStream({
    required String path,
    required _SyncOpenDocumentConfig config,
    required String? vector,
    required Map<String, dynamic>? initialJson,
  }) async {
    final streamState = _SyncOpenStreamState(
      path: path,
      create: config.create,
      vector: vector,
      schemaJson: config.schemaJson,
      schemaPath: config.schemaPath,
      initialJson: initialJson,
    );
    StreamIterator<Content>? iterator;
    try {
      final output = await _invoke("open", ToolStreamInput(streamState.inputStream()));
      if (output is! ToolStreamOutput) {
        throw _unexpectedResponseError(operation: "open");
      }

      iterator = StreamIterator(output.stream);
      if (!await iterator.moveNext()) {
        throw RoomServerException("sync.open stream closed before the initial document state was returned");
      }
      final firstChunk = iterator.current;
      if (firstChunk is ErrorContent) {
        throw RoomServerException(firstChunk.text, code: firstChunk.code);
      }
      if (firstChunk is! BinaryContent) {
        throw _unexpectedResponseError(operation: "open");
      }

      final stateHeaders = _SyncOpenStateChunkHeaders.fromHeaders(firstChunk.headers);
      if (_normalizeSyncPath(stateHeaders.path) != path) {
        throw RoomServerException("sync.open stream returned a mismatched path");
      }

      return _SyncOpenResult(streamState: streamState, iterator: iterator, stateHeaders: stateHeaders, firstChunk: firstChunk);
    } catch (error) {
      streamState.closeInputStream();
      if (iterator != null) {
        await iterator.cancel();
      }
      rethrow;
    }
  }

  void _attachStreamConsumer({
    required String path,
    required _RefCount<MeshDocument> doc,
    required _SyncOpenStreamState streamState,
    required StreamIterator<Content> iterator,
  }) {
    streamState.attachTask(_consumeOpenStream(path: path, doc: doc, iterator: iterator, streamState: streamState));
  }

  Future<void> _onRoomDisconnect() async {
    for (final entry in _connectedDocuments.entries) {
      _reconnectBaseVectors.putIfAbsent(entry.key, () => entry.value.ref.getStateVector());
    }
    final openStreams = List<_SyncOpenStreamState>.from(_documentStreams.values);
    _documentStreams.clear();
    for (final streamState in openStreams) {
      streamState.closeInputStream();
    }
  }

  Future<void> _onRoomReconnect() async {
    for (final entry in List<MapEntry<String, _RefCount<MeshDocument>>>.from(_connectedDocuments.entries)) {
      final path = entry.key;
      final ref = entry.value;
      final config = _documentConfigs[path];
      if (config == null) {
        continue;
      }

      final reconnectBaseVector = _reconnectBaseVectors.remove(path);
      Uint8List? reconnectSyncPayload;
      if (reconnectBaseVector != null) {
        final reconnectState = ref.ref.getState(vector: reconnectBaseVector);
        if (reconnectState.isNotEmpty) {
          reconnectSyncPayload = Uint8List.fromList(utf8.encode(base64Encode(reconnectState)));
        }
      }

      final vector = base64Encode(ref.ref.getStateVector());
      final openResult = await _openStream(path: path, config: config, vector: vector, initialJson: null);
      _documentStreams[path] = openResult.streamState;
      _applySyncPayload(ref, openResult.firstChunk.data);
      if (reconnectSyncPayload != null) {
        openResult.streamState.queueSync(reconnectSyncPayload);
      }
      _attachStreamConsumer(path: path, doc: ref, streamState: openResult.streamState, iterator: openResult.iterator);
    }
  }

  final RoomClient room;
}

class _SyncOpenResult {
  _SyncOpenResult({required this.streamState, required this.iterator, required this.stateHeaders, required this.firstChunk});

  final _SyncOpenStreamState streamState;
  final StreamIterator<Content> iterator;
  final _SyncOpenStateChunkHeaders stateHeaders;
  final BinaryContent firstChunk;
}

class MeshDocument extends RuntimeDocument {
  MeshDocument({super.sendChangesToBackend, required super.schema})
    : super(id: const Uuid().v4(), sendChanges: DocumentRuntime.instance!.sendChanges) {
    DocumentRuntime.instance!.registerDocument(this);
  }

  final _synchronized = Completer();
  Future get synchronized {
    return _synchronized.future;
  }

  void dispose() {
    DocumentRuntime.instance!.unregisterDocument(this);
  }

  String encode() {
    return jsonEncode({"initial_json": root.toJson(), "schema": schema.toJson()});
  }
}

enum ToolContentType { binary, json, text, file, link, empty }

String _toolContentTypeToWire(ToolContentType kind) {
  return switch (kind) {
    ToolContentType.binary => "binary",
    ToolContentType.json => "json",
    ToolContentType.text => "text",
    ToolContentType.file => "file",
    ToolContentType.link => "link",
    ToolContentType.empty => "empty",
  };
}

ToolContentType _toolContentTypeFromWire(String value) {
  return switch (value) {
    "binary" => ToolContentType.binary,
    "json" => ToolContentType.json,
    "text" => ToolContentType.text,
    "file" => ToolContentType.file,
    "link" => ToolContentType.link,
    "empty" => ToolContentType.empty,
    _ => throw ArgumentError.value(value, "value", "Unsupported tool content type"),
  };
}

class ToolContentSpec {
  ToolContentSpec({required List<ToolContentType> types, this.stream = false, this.schema})
    : types = List<ToolContentType>.unmodifiable(types) {
    if (types.isEmpty) {
      throw ArgumentError.value(types, "types", "At least one content type is required");
    }
  }

  final List<ToolContentType> types;
  final bool stream;
  final Map<String, dynamic>? schema;

  Map<String, dynamic> toJson() {
    return {"types": types.map(_toolContentTypeToWire).toList(growable: false), "stream": stream, if (schema != null) "schema": schema};
  }

  static ToolContentSpec? fromJson(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is! Map) {
      throw ArgumentError.value(value, "value", "Tool content type must be a JSON object");
    }

    final rawTypes = value["types"];
    if (rawTypes is! List) {
      throw ArgumentError.value(rawTypes, "types", "Tool content type requires a types array");
    }

    final types = rawTypes
        .map((item) {
          if (item is! String) {
            throw ArgumentError.value(item, "types", "Tool content types must be strings");
          }
          return _toolContentTypeFromWire(item);
        })
        .toList(growable: false);

    final rawStream = value["stream"];
    final stream = rawStream is bool ? rawStream : false;
    Map<String, dynamic>? schema;
    final rawSchema = value["schema"];
    if (rawSchema != null) {
      if (rawSchema is! Map) {
        throw ArgumentError.value(rawSchema, "schema", "Tool content type schema must be a JSON object");
      }
      schema = rawSchema.cast<String, dynamic>();
    }
    return ToolContentSpec(types: types, stream: stream, schema: schema);
  }
}

class ToolkitDescription {
  ToolkitDescription({required this.title, required this.name, required this.description, required this.tools, this.participantId});

  final String? title;
  final String name;
  final String? description;
  final String? participantId;

  late final Map<String, ToolDescription> _byName = Map<String, ToolDescription>.fromEntries(tools.map((e) => MapEntry(e.name, e)));

  final List<ToolDescription> tools;

  ToolDescription? operator [](String name) {
    return _byName[name];
  }

  Map<String, dynamic> toJson() {
    return {
      "name": name,
      "description": description,
      "title": title,
      if (participantId != null) "participant_id": participantId,
      "tools": tools
          .map(
            (tool) => {
              "name": tool.name,
              "title": tool.title,
              "description": tool.description,
              "input_spec": tool.inputSpec?.toJson(),
              "output_spec": tool.outputSpec?.toJson(),
              "defs": tool.defs,
            },
          )
          .toList(),
    };
  }

  static ToolkitDescription fromJson(Map<String, dynamic> json, {String? name}) {
    return ToolkitDescription(
      title: json["title"],
      name: name ?? json["name"],
      description: json["description"],
      participantId: json["participant_id"],
      tools: [
        if (json["tools"] is List)
          ...(json["tools"] as List).map((tool) {
            return ToolDescription(
              title: tool["title"],
              name: tool["name"],
              description: tool["description"],
              inputSpec: ToolContentSpec.fromJson(tool["input_spec"]),
              outputSpec: ToolContentSpec.fromJson(tool["output_spec"]),
              defs: tool["defs"],
            );
          }),
        if (json["tools"] is Map)
          ...(json["tools"] as Map).keys.map((toolName) {
            final tool = json["tools"][toolName];
            return ToolDescription(
              title: tool["title"],
              name: toolName,
              description: tool["description"],
              inputSpec: ToolContentSpec.fromJson(tool["input_spec"]),
              outputSpec: ToolContentSpec.fromJson(tool["output_spec"]),
              defs: tool["defs"],
            );
          }),
      ],
    );
  }
}

class ToolDescription {
  ToolDescription({
    required this.title,
    required this.name,
    required this.description,
    this.inputSpec,
    this.outputSpec,
    required this.defs,
  });

  final String title;
  final String name;
  final String description;
  final ToolContentSpec? inputSpec;
  final ToolContentSpec? outputSpec;
  final Map<String, dynamic>? defs;
}

class StorageClient extends ChangeEmitter {
  static const String _defaultUploadMimeTypeValue = 'application/octet-stream';
  static const Map<String, String> _uploadMimeTypesBySuffix = {'.tar.gz': 'application/x-tar', '.tgz': 'application/x-tar'};
  static const Map<String, String> _uploadMimeTypesByExtension = {
    '.bin': 'application/octet-stream',
    '.css': 'text/css',
    '.csv': 'text/csv',
    '.gif': 'image/gif',
    '.gz': 'application/gzip',
    '.htm': 'text/html',
    '.html': 'text/html',
    '.jpeg': 'image/jpeg',
    '.jpg': 'image/jpeg',
    '.js': 'text/javascript',
    '.json': 'application/json',
    '.md': 'text/markdown',
    '.mp3': 'audio/mpeg',
    '.mp4': 'video/mp4',
    '.pdf': 'application/pdf',
    '.png': 'image/png',
    '.svg': 'image/svg+xml',
    '.tar': 'application/x-tar',
    '.ts': 'text/typescript',
    '.tsx': 'text/tsx',
    '.txt': 'text/plain',
    '.wasm': 'application/wasm',
    '.wav': 'audio/wav',
    '.webp': 'image/webp',
    '.xml': 'application/xml',
    '.yaml': 'application/yaml',
    '.yml': 'application/yaml',
    '.zip': 'application/zip',
  };

  StorageClient({required this.room}) {
    room.protocol.addHandler("storage.file.deleted", _handleFileDeleted);
    room.protocol.addHandler("storage.file.moved", _handleFileMoved);
    room.protocol.addHandler("storage.file.updated", _handleFileUpdated);
  }

  RoomClient room;

  Future<void> _handleFileUpdated(Protocol protocol, int messageId, String type, Uint8List bytes) async {
    if (!identical(protocol, room._protocolInstance)) {
      return;
    }
    final data = unpackMessage(bytes).header;
    room._eventsController.add(FileUpdatedEvent(path: data["path"], participantId: data["participant_id"]));
  }

  Future<void> _handleFileDeleted(Protocol protocol, int messageId, String type, Uint8List bytes) async {
    if (!identical(protocol, room._protocolInstance)) {
      return;
    }
    final data = unpackMessage(bytes).header;
    room._eventsController.add(FileDeletedEvent(path: data["path"], participantId: data["participant_id"]));
  }

  Future<void> _handleFileMoved(Protocol protocol, int messageId, String type, Uint8List bytes) async {
    if (!identical(protocol, room._protocolInstance)) {
      return;
    }
    final data = unpackMessage(bytes).header;
    room._eventsController.add(
      FileMovedEvent(sourcePath: data["source_path"], destinationPath: data["destination_path"], participantId: data["participant_id"]),
    );
  }

  RoomServerException _unexpectedResponseError(String operation) {
    return RoomServerException("unexpected return type from storage.$operation");
  }

  Future<Content> _invoke(String operation, dynamic input) async {
    final ToolInput toolInput;
    if (input is Content) {
      toolInput = ToolContentInput(input);
    } else if (input is Map<String, dynamic>) {
      toolInput = ToolContentInput(JsonContent(json: input));
    } else {
      throw RoomServerException("storage.$operation input must be Content or Map<String, dynamic>");
    }

    final output = await room.invoke(toolkit: "storage", tool: operation, input: toolInput);
    if (output is! ToolContentOutput) {
      throw _unexpectedResponseError(operation);
    }
    return output.content;
  }

  Future<List<StorageEntry>> list(String path) async {
    final response = await _invoke("list", {"path": path});
    if (response is! JsonContent) {
      throw _unexpectedResponseError("list");
    }
    return (response.json["files"] as List).map((f) {
      return StorageEntry(
        name: f["name"],
        isFolder: f["is_folder"],
        size: f["size"] is int ? f["size"] : null,
        createdAt: f["created_at"] == null ? null : DateTime.parse(f["created_at"]),
        updatedAt: f["updated_at"] == null ? null : DateTime.parse(f["updated_at"]),
      );
    }).toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<void> delete(String path, {bool? recursive}) async {
    await _invoke("delete", {"path": path, "recursive": recursive});
  }

  Future<void> move(String sourcePath, String destinationPath, {bool overwrite = false}) async {
    await _invoke("move", {"source_path": sourcePath, "destination_path": destinationPath, "overwrite": overwrite});
  }

  Future<bool> exists(String path) async {
    final result = await _invoke("exists", {"path": path});
    if (result is! JsonContent) {
      throw _unexpectedResponseError("exists");
    }
    return result.json["exists"];
  }

  Future<StorageEntry?> stat(String path) async {
    final response = await _invoke("stat", {"path": path});
    if (response is! JsonContent) {
      throw _unexpectedResponseError("stat");
    }
    if (response.json["exists"] == false) {
      return null;
    }
    return StorageEntry(
      name: response.json["name"],
      isFolder: response.json["is_folder"],
      size: response.json["size"] is int ? response.json["size"] : null,
      createdAt: response.json["created_at"] == null ? null : DateTime.parse(response.json["created_at"]),
      updatedAt: response.json["updated_at"] == null ? null : DateTime.parse(response.json["updated_at"]),
    );
  }

  String _defaultUploadName(String uploadPath, {String? name}) {
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return path.basename(uploadPath);
  }

  String _defaultUploadMimeType(String name, {String? mimeType}) {
    if (mimeType != null && mimeType.isNotEmpty) {
      return mimeType;
    }
    final lowerName = name.toLowerCase();
    for (final entry in _uploadMimeTypesBySuffix.entries) {
      if (lowerName.endsWith(entry.key)) {
        return entry.value;
      }
    }
    return _uploadMimeTypesByExtension[path.extension(lowerName)] ?? _defaultUploadMimeTypeValue;
  }

  Future<void> upload(String path, Uint8List bytes, {bool overwrite = false, String? name, String? mimeType}) async {
    await uploadStream(path, Stream.value(bytes), overwrite: overwrite, size: bytes.length, name: name, mimeType: mimeType);
  }

  Future<void> uploadStream(
    String path,
    Stream<Uint8List> chunks, {
    bool overwrite = false,
    int chunkSize = 64 * 1024,
    int? size,
    String? name,
    String? mimeType,
  }) async {
    final resolvedName = _defaultUploadName(path, name: name);
    final input = _StorageUploadInputStream(
      path: path,
      overwrite: overwrite,
      chunks: chunks,
      chunkSize: chunkSize,
      size: size,
      name: resolvedName,
      mimeType: _defaultUploadMimeType(resolvedName, mimeType: mimeType),
    );
    final output = await room.invoke(toolkit: "storage", tool: "upload", input: ToolStreamInput(input.inputStream()));

    if (output is! ToolStreamOutput) {
      input.close();
      throw _unexpectedResponseError("upload");
    }

    try {
      await for (final chunk in output.stream) {
        if (chunk is ErrorContent) {
          throw RoomServerException(chunk.text, code: chunk.code);
        }
        if (chunk is ControlContent) {
          if (chunk.method == "close") {
            return;
          }
          throw _unexpectedResponseError("upload");
        }
        if (chunk is! BinaryContent || chunk.headers["kind"] != "pull") {
          throw _unexpectedResponseError("upload");
        }
        final rawChunkSize = chunk.headers["chunk_size"];
        input.requestNext(rawChunkSize is int && rawChunkSize > 0 ? rawChunkSize : null);
      }
    } finally {
      input.close();
    }
  }

  Future<Stream<BinaryContent>> downloadStream(String path, {int chunkSize = 64 * 1024}) async {
    final input = _StorageDownloadInputStream(path: path, chunkSize: chunkSize);
    final output = await room.invoke(toolkit: "storage", tool: "download", input: ToolStreamInput(input.inputStream()));
    if (output is! ToolStreamOutput) {
      input.close();
      throw _unexpectedResponseError("download");
    }

    Stream<BinaryContent> stream() async* {
      var metadataReceived = false;
      int? expectedSize;
      var bytesReceived = 0;
      try {
        await for (final chunk in output.stream) {
          if (chunk is ErrorContent) {
            throw RoomServerException(chunk.text, code: chunk.code);
          }
          if (chunk is ControlContent) {
            if (chunk.method == "close") {
              if (!metadataReceived || expectedSize == null || bytesReceived != expectedSize) {
                throw _unexpectedResponseError("download");
              }
              return;
            }
            throw _unexpectedResponseError("download");
          }
          if (chunk is! BinaryContent) {
            throw _unexpectedResponseError("download");
          }

          final kind = chunk.headers["kind"];
          if (kind == "start") {
            if (metadataReceived) {
              throw _unexpectedResponseError("download");
            }
            final chunkName = chunk.headers["name"];
            final chunkMimeType = chunk.headers["mime_type"];
            final chunkSizeValue = chunk.headers["size"];
            if (chunkName is! String || chunkMimeType is! String || chunkSizeValue is! int || chunkSizeValue < 0) {
              throw _unexpectedResponseError("download");
            }
            metadataReceived = true;
            expectedSize = chunkSizeValue;
            yield chunk;
            if (expectedSize > 0) {
              input.requestNext();
            }
            continue;
          }

          if (kind != "data" || !metadataReceived || expectedSize == null) {
            throw _unexpectedResponseError("download");
          }

          bytesReceived += chunk.data.length;
          if (bytesReceived > expectedSize) {
            throw _unexpectedResponseError("download");
          }
          yield chunk;
          if (bytesReceived < expectedSize) {
            input.requestNext();
          }
        }
      } finally {
        input.close();
      }
    }

    return stream();
  }

  Future<FileContent> download(String path) async {
    String? name;
    String? mimeType;
    int? expectedSize;
    var bytesReceived = 0;
    final bytes = BytesBuilder(copy: false);
    final stream = await downloadStream(path);
    await for (final chunk in stream) {
      final kind = chunk.headers["kind"];
      if (kind == "start") {
        final chunkName = chunk.headers["name"];
        final chunkMimeType = chunk.headers["mime_type"];
        final chunkSizeValue = chunk.headers["size"];
        if (chunkName is! String || chunkMimeType is! String || chunkSizeValue is! int || chunkSizeValue < 0) {
          throw _unexpectedResponseError("download");
        }
        name = chunkName;
        mimeType = chunkMimeType;
        expectedSize = chunkSizeValue;
        continue;
      }
      if (kind != "data") {
        throw _unexpectedResponseError("download");
      }
      bytes.add(chunk.data);
      bytesReceived += chunk.data.length;
    }
    if (name == null || mimeType == null || expectedSize == null || bytesReceived != expectedSize) {
      throw _unexpectedResponseError("download");
    }
    return FileContent(data: bytes.takeBytes(), name: name, mimeType: mimeType);
  }

  Future<String> downloadUrl(String path) async {
    final response = await _invoke("download_url", {"path": path});
    if (response is! JsonContent) {
      throw _unexpectedResponseError("download_url");
    }

    return response.json["url"];
  }
}

class _StorageDownloadInputStream {
  _StorageDownloadInputStream({required this.path, required this.chunkSize});

  final String path;
  final int chunkSize;
  final _pulls = StreamController<void>();
  bool _closed = false;

  Stream<Content> inputStream() async* {
    yield BinaryContent(data: Uint8List(0), headers: {"kind": "start", "path": path, "chunk_size": chunkSize});
    await for (final _ in _pulls.stream) {
      if (_closed) {
        return;
      }
      yield BinaryContent(data: Uint8List(0), headers: {"kind": "pull"});
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

class _StorageUploadInputStream {
  _StorageUploadInputStream({
    required this.path,
    required this.overwrite,
    required Stream<Uint8List> chunks,
    required this.chunkSize,
    required this.size,
    required this.name,
    required this.mimeType,
  }) : _source = StreamQueue(chunks);

  final String path;
  final bool overwrite;
  final int chunkSize;
  final int? size;
  final String name;
  final String? mimeType;
  final StreamQueue<Uint8List> _source;
  final _pulls = StreamController<int?>();
  bool _closed = false;
  Uint8List _pendingChunk = Uint8List(0);
  int _pendingOffset = 0;
  bool _sourceExhausted = false;

  Stream<Content> inputStream() async* {
    yield BinaryContent(
      data: Uint8List(0),
      headers: {"kind": "start", "path": path, "overwrite": overwrite, "name": name, "mime_type": mimeType, "size": size},
    );
    await for (final requestedChunkSize in _pulls.stream) {
      if (_closed) {
        return;
      }
      final chunk = await _nextChunk(requestedChunkSize is int && requestedChunkSize > 0 ? requestedChunkSize : chunkSize);
      if (chunk == null) {
        return;
      }
      yield BinaryContent(data: chunk, headers: const {"kind": "data"});
    }
  }

  Future<Uint8List?> _nextChunk(int requestedChunkSize) async {
    final bytes = BytesBuilder(copy: false);

    while (bytes.length < requestedChunkSize) {
      if (_pendingOffset < _pendingChunk.length) {
        final remaining = requestedChunkSize - bytes.length;
        final end = math.min(_pendingOffset + remaining, _pendingChunk.length);
        bytes.add(Uint8List.sublistView(_pendingChunk, _pendingOffset, end));
        _pendingOffset = end;
        continue;
      }

      if (_sourceExhausted) {
        break;
      }

      if (!await _source.hasNext) {
        _sourceExhausted = true;
        break;
      }

      final nextChunk = await _source.next;
      if (nextChunk.isEmpty) {
        continue;
      }
      _pendingChunk = nextChunk;
      _pendingOffset = 0;
    }

    if (bytes.length == 0) {
      return null;
    }
    return bytes.takeBytes();
  }

  void requestNext([int? requestedChunkSize]) {
    if (_closed) {
      return;
    }
    _pulls.add(requestedChunkSize);
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

class DeveloperClient extends ChangeEmitter {
  DeveloperClient({required this.room}) {
    room.protocol.addHandler("developer.log", _handleDeveloperLog);
  }

  RoomClient room;

  Future<void> _handleDeveloperLog(Protocol protocol, int messageId, String type, Uint8List bytes) async {
    if (!identical(protocol, room._protocolInstance)) {
      return;
    }
    final rawJson = unpackMessage(bytes).header;

    room._eventsController.add(RoomLogEvent.fromJson(rawJson));
  }

  RoomServerException _unexpectedResponseError(String operation) {
    return RoomServerException("unexpected return type from developer.$operation");
  }

  Future<void> _invoke(String operation, Map<String, dynamic> input) async {
    await room.invoke(
      toolkit: "developer",
      tool: operation,
      input: ToolContentInput(JsonContent(json: input)),
    );
  }

  Future<void> log(String type, Map<String, dynamic> data) async {
    await _invoke("log", {"type": type, "data": data});
  }

  Future<void> info(String message, {Map<String, dynamic>? extra}) async {
    await _invoke("info", {"message": message, "extra": extra ?? {}});
  }

  Future<void> warning(String message, {Map<String, dynamic>? extra}) async {
    await _invoke("warning", {"message": message, "extra": extra ?? {}});
  }

  Future<void> error(String message, {Map<String, dynamic>? extra}) async {
    await _invoke("error", {"message": message, "extra": extra ?? {}});
  }

  Stream<RoomLogEvent> logs() async* {
    final inputClosed = Completer<void>();

    Stream<Content> inputStream() async* {
      await inputClosed.future;
    }

    final output = await room.invoke(toolkit: "developer", tool: "logs", input: ToolStreamInput(inputStream()));
    if (output is! ToolStreamOutput) {
      if (!inputClosed.isCompleted) {
        inputClosed.complete();
      }
      throw _unexpectedResponseError("logs");
    }

    try {
      await for (final chunk in output.stream) {
        if (chunk is ErrorContent) {
          throw RoomServerException(chunk.text, code: chunk.code);
        }
        if (chunk is ControlContent) {
          if (chunk.method == "close") {
            return;
          }
          throw _unexpectedResponseError("logs");
        }
        if (chunk is! BinaryContent) {
          throw _unexpectedResponseError("logs");
        }

        final logType = chunk.headers["type"];
        if (logType is! String || logType.isEmpty) {
          throw RoomServerException("developer.logs returned a chunk without a valid type");
        }

        final dynamic decoded = chunk.data.isEmpty ? <String, dynamic>{} : jsonDecode(utf8.decode(chunk.data));
        if (decoded is! Map) {
          throw RoomServerException("developer.logs returned invalid JSON data");
        }

        yield RoomLogEvent(type: logType, data: Map<String, dynamic>.from(decoded));
      }
    } finally {
      if (!inputClosed.isCompleted) {
        inputClosed.complete();
      }
    }
  }
}

class Queue {
  Queue({required this.name, required this.size});

  final String name;
  final int size;
}

class MessagingClient extends ChangeEmitter {
  MessagingClient({required this.room}) {
    room.protocol.addHandler("messaging.send", _handleMessageSend);
  }

  final RoomClient room;
  final _participants = <String, RemoteParticipant>{};
  final ListQueue<_QueuedRoomMessage> _messageQueue = ListQueue<_QueuedRoomMessage>();
  Completer<void>? _messageQueueSignal;
  Future<void>? _sendTask;
  bool _messageQueueClosed = false;
  bool _desiredEnabled = false;
  bool _online = false;
  bool _enableInFlight = false;

  bool get isEnabled {
    return _desiredEnabled;
  }

  bool get online {
    return _online;
  }

  Iterable<RemoteParticipant> get remoteParticipants {
    return _participants.values;
  }

  Map<String, dynamic> _messageInput({
    required String type,
    required Map<String, dynamic> message,
    Uint8List? attachment,
    String? toParticipantId,
  }) {
    final input = <String, dynamic>{"type": type, "message_json": jsonEncode(message)};

    if (attachment != null) {
      input["attachment_base64"] = base64Encode(attachment);
    }

    if (toParticipantId != null) {
      input["to_participant_id"] = toParticipantId;
    }

    return input;
  }

  Future<void> _invoke({required String operation, required Map<String, dynamic> input}) async {
    await room.invoke(
      toolkit: "messaging",
      tool: operation,
      input: ToolContentInput(JsonContent(json: input)),
    );
  }

  void _invokeNowait({required String operation, required Map<String, dynamic> input}) {
    room.invokeNowait(
      toolkit: "messaging",
      tool: operation,
      input: JsonContent(json: input),
    );
  }

  void start() {
    if (_sendTask != null) {
      return;
    }
    _sendTask = _sendMessages();
    if (_desiredEnabled && room.isConnected) {
      _enableCurrentConnectionNowait();
    }
  }

  Future<void> stop() async {
    final stoppedError = room._closing && room._terminalState != null
        ? room._terminalState!.messageSendError()
        : RoomServerException("Cannot send messages because messaging has been stopped");
    _messageQueueClosed = true;
    _wakeMessageQueue();
    _drainQueuedMessages(error: stoppedError);
    final sendTask = _sendTask;
    if (sendTask != null) {
      await sendTask;
    }
    _sendTask = null;
    _desiredEnabled = false;
    _clearCurrentConnectionState();
  }

  Future<_QueuedRoomMessage?> _nextQueuedMessage() async {
    while (true) {
      if (_messageQueue.isNotEmpty) {
        return _messageQueue.removeFirst();
      }
      if (_messageQueueClosed) {
        return null;
      }
      final signal = _messageQueueSignal ??= Completer<void>();
      await signal.future;
    }
  }

  void _wakeMessageQueue() {
    final signal = _messageQueueSignal;
    _messageQueueSignal = null;
    if (signal != null && !signal.isCompleted) {
      signal.complete();
    }
  }

  void _queueMessage(_QueuedRoomMessage message) {
    if (_messageQueueClosed) {
      throw RoomServerException("Cannot send messages because messaging has been stopped");
    }
    _messageQueue.add(message);
    _wakeMessageQueue();
  }

  void _setOnline(bool online) {
    if (_online == online) {
      return;
    }
    _online = online;
    notifyListeners();
  }

  Future<void> _waitUntilOnline() async {
    while (!_online) {
      if (!room.isConnected && !room._allowDisconnectedRequests) {
        await room._waitUntilConnectedForMessages();
        continue;
      }
      room._raiseIfTerminalForMessages();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  void _enableCurrentConnectionNowait() {
    if (_online || _enableInFlight) {
      return;
    }
    _enableInFlight = true;
    _invokeNowait(operation: "enable", input: {});
  }

  void _clearCurrentConnectionState() {
    _enableInFlight = false;
    _setOnline(false);
    if (_participants.isEmpty) {
      return;
    }
    for (final participantId in List<String>.from(_participants.keys)) {
      _removeParticipant(participantId);
    }
    notifyListeners();
  }

  void _onRoomDisconnect({String? reason}) {
    _clearCurrentConnectionState();
  }

  void _onRoomReconnect() {
    if (_desiredEnabled) {
      _enableCurrentConnectionNowait();
    }
  }

  RemoteParticipant? _removeParticipant(String participantId) {
    final participant = _participants.remove(participantId);
    if (participant == null) {
      return null;
    }

    participant._setOnline(false);
    notifyListeners();

    return participant;
  }

  void _markParticipantOffline(Participant? participant) {
    if (participant is! RemoteParticipant) {
      return;
    }
    participant._setOnline(false);
    if (_participants.containsKey(participant.id)) {
      _removeParticipant(participant.id);
    }
  }

  Participant? _resolveMessageRecipient(Participant? to) {
    if (to == null) {
      return null;
    }
    if (to is! RemoteParticipant) {
      return to;
    }

    if (to.online == false) {
      return null;
    }

    return _participants[to.id];
  }

  void _dropQueuedMessage({required _QueuedRoomMessage message, required RoomServerException error}) {
    final completer = message.completer;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error);
    }
  }

  void _drainQueuedMessages({required RoomServerException error}) {
    while (_messageQueue.isNotEmpty) {
      final message = _messageQueue.removeFirst();
      _dropQueuedMessage(message: message, error: error);
    }
  }

  Future<void> _sendMessages() async {
    while (true) {
      final message = await _nextQueuedMessage();
      if (message == null) {
        return;
      }

      try {
        await room._waitUntilConnectedForMessages();
        if (_desiredEnabled) {
          await _waitUntilOnline();
        }
      } on RoomServerException catch (error) {
        _dropQueuedMessage(message: message, error: error);
        _drainQueuedMessages(error: error);
        return;
      }

      final resolvedTo = _resolveMessageRecipient(message.to);
      if (resolvedTo == null) {
        _dropQueuedMessage(message: message, error: RoomServerException("the participant was not found"));
        continue;
      }

      try {
        await _invoke(
          operation: "send",
          input: _messageInput(
            toParticipantId: resolvedTo.id,
            type: message.type,
            message: message.message,
            attachment: message.attachment,
          ),
        );
        final completer = message.completer;
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
      } on RoomServerException catch (error) {
        final wrapped = room._coerceMessageSendError(error);
        if (wrapped.message == "the participant was not found") {
          _markParticipantOffline(message.to);
          if (message.dropIfOffline) {
            _dropQueuedMessage(message: message, error: wrapped);
            continue;
          }
        }
        _roomClientLogger.log(Level.INFO, 'unable to send message to participant', wrapped, StackTrace.current);
        _dropQueuedMessage(message: message, error: wrapped);
      } catch (error, stackTrace) {
        _roomClientLogger.log(Level.INFO, 'unable to send message to participant', error, stackTrace);
        final completer = message.completer;
        if (completer != null && !completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    }
  }

  Future<void> sendMessage({
    required Participant to,
    required String type,
    required Map<String, dynamic> message,
    Uint8List? attachment,
    bool ignoreOffline = false,
  }) async {
    if (_sendTask == null) {
      throw RoomServerException("Cannot send messages because messaging has not been started");
    }
    final queued = _QueuedRoomMessage(
      fromParticipantId: room.localParticipant?.id ?? "",
      to: to,
      type: type,
      message: message,
      attachment: attachment,
      dropIfOffline: ignoreOffline,
    );
    _queueMessage(queued);
    final completer = queued.completer;
    if (completer != null) {
      await completer.future;
    }
  }

  Future<void> enable() {
    _desiredEnabled = true;
    if (room.isConnected) {
      _enableCurrentConnectionNowait();
    }
    return Future<void>.value();
  }

  Future<void> disable() {
    final wasOnline = _online;
    _desiredEnabled = false;
    _clearCurrentConnectionState();
    if (room.isConnected && wasOnline) {
      _invokeNowait(operation: "disable", input: {});
    }
    return Future<void>.value();
  }

  Future<void> broadcastMessage({required String type, required Map<String, dynamic> message, Uint8List? attachment}) async {
    if (_sendTask == null) {
      throw RoomServerException("Cannot send messages because messaging has not been started");
    }
    await room._waitUntilConnectedForMessages();
    if (_desiredEnabled) {
      await _waitUntilOnline();
    }
    try {
      await _invoke(
        operation: "broadcast",
        input: _messageInput(type: type, message: message, attachment: attachment),
      );
    } on RoomServerException catch (error) {
      throw room._coerceMessageSendError(error);
    }
  }

  Future<void> _handleMessageSend(Protocol protocol, int messageId, String type, Uint8List bytes) async {
    if (!identical(protocol, room._protocolInstance)) {
      return;
    }
    final headerStr = splitMessageHeader(bytes);
    final payload = splitMessagePayload(bytes);

    final header = jsonDecode(headerStr);

    final message = RoomMessage(
      fromParticipantId: header["from_participant_id"],
      type: header["type"],
      message: header["message"],
      attachment: payload.isEmpty ? null : payload,
    );

    if (message.type == "messaging.enabled") {
      _onMessagingEnabled(message);
    } else if (message.type == "participant.attributes") {
      _onParticipantAttributes(message);
    } else if (message.type == "participant.enabled") {
      _onParticipantEnabled(message);
    } else if (message.type == "participant.disabled") {
      _onParticipantDisabled(message);
    }

    room._eventsController.add(RoomMessageEvent(message: message));
  }

  void _onParticipantEnabled(RoomMessage message) {
    final data = message.message;
    final participant = RemoteParticipant(client: room, id: data["id"], role: data["role"], online: true);

    participant._applyAttributes(Map<String, dynamic>.from(data["attributes"] as Map));
    _participants[data["id"]] = participant;
    notifyListeners();
  }

  void _onParticipantAttributes(RoomMessage message) {
    final part = _participants[message.fromParticipantId];
    if (part == null) {
      return;
    }
    part._applyAttributes(Map<String, dynamic>.from(message.message["attributes"] as Map));
    notifyListeners();
  }

  void _onParticipantDisabled(RoomMessage message) {
    _removeParticipant(message.message["id"]);
  }

  void _onMessagingEnabled(RoomMessage message) {
    _enableInFlight = false;
    _participants.clear();
    for (var data in message.message["participants"]) {
      final participant = RemoteParticipant(client: room, id: data["id"], role: data["role"], online: true);

      participant._applyAttributes(Map<String, dynamic>.from(data["attributes"] as Map));
      _participants[data["id"]] = participant;
    }
    _setOnline(true);
    if (!_desiredEnabled) {
      _invokeNowait(operation: "disable", input: {});
      _clearCurrentConnectionState();
      return;
    }
    notifyListeners();
  }
}

class FileHandle {
  FileHandle({required this.id});

  final String id;
}

class StorageEntry {
  StorageEntry({required this.name, required this.isFolder, required this.size, required this.createdAt, required this.updatedAt});

  final String name;
  final bool isFolder;
  final int? size;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get nameWithoutExtension {
    return path.basenameWithoutExtension(name);
  }
}

/// Abstract Content class
abstract class Content {
  Content();

  /// Abstract pack method to be implemented by subclasses.
  Uint8List pack();
}

/// A dictionary-like structure to map a 'type' string to an 'unpack' function.
final Map<String, Content Function(Map<String, dynamic> header, Uint8List payload)> _contentTypes = {
  'binary': BinaryContent.unpack,
  'link': LinkContent.unpack,
  'file': FileContent.unpack,
  'text': TextContent.unpack,
  'error': ErrorContent.unpack,
  'json': JsonContent.unpack,
  'empty': EmptyContent.unpack,
  'control': ControlContent.unpack,
};

class BinaryContent extends Content {
  BinaryContent({required this.data, Map<String, dynamic>? headers}) : headers = Map<String, dynamic>.from(headers ?? const {});

  final Uint8List data;
  final Map<String, dynamic> headers;

  static BinaryContent unpack(Map<String, dynamic> header, Uint8List payload) {
    final rawHeaders = header['headers'];
    return BinaryContent(data: payload, headers: rawHeaders is Map ? rawHeaders.cast<String, dynamic>() : const {});
  }

  @override
  Uint8List pack() {
    return packMessage({'type': 'binary', 'headers': headers}, data);
  }

  @override
  String toString() {
    return "BinaryContent: headers=$headers length=${data.length}";
  }
}

//
// LinkContent
//
class LinkContent extends Content {
  final String url;
  final String name;

  LinkContent({required this.url, required this.name});

  static LinkContent unpack(Map<String, dynamic> header, Uint8List payload) {
    return LinkContent(url: header['url'] as String, name: header['name'] as String);
  }

  @override
  Uint8List pack() {
    return packMessage({'type': 'link', 'name': name, 'url': url});
  }

  @override
  String toString() {
    return "LinkContent ($name): $url";
  }
}

//
// FileContent
//
class FileContent extends Content {
  final Uint8List data;
  final String name;
  final String mimeType;

  FileContent({required this.data, required this.name, required this.mimeType});

  static FileContent unpack(Map<String, dynamic> header, Uint8List payload) {
    return FileContent(data: payload, name: header['name'] as String, mimeType: header['mime_type'] as String);
  }

  @override
  Uint8List pack() {
    return packMessage({'type': 'file', 'name': name, 'mime_type': mimeType}, data);
  }

  @override
  String toString() {
    return "FileContent ($mimeType): $name ";
  }
}

//
// TextContent
//
class TextContent extends Content {
  final String text;

  TextContent({required this.text});

  static TextContent unpack(Map<String, dynamic> header, Uint8List payload) {
    return TextContent(text: header['text'] as String);
  }

  @override
  Uint8List pack() {
    return packMessage({'type': 'text', 'text': text});
  }

  @override
  String toString() {
    return "TextContent: $text";
  }
}

//
// ErrorContent
//
class ErrorContent extends Content {
  final String text;
  final int? code;

  ErrorContent({required this.text, this.code});

  static ErrorContent unpack(Map<String, dynamic> header, Uint8List payload) {
    final rawCode = header['code'];
    int? parsedCode;
    if (rawCode is int) {
      parsedCode = rawCode;
    } else if (rawCode is num) {
      parsedCode = rawCode.toInt();
    } else if (rawCode is String) {
      parsedCode = int.tryParse(rawCode);
    }
    return ErrorContent(text: header['text'] as String, code: parsedCode);
  }

  @override
  Uint8List pack() {
    final payload = <String, dynamic>{'type': 'error', 'text': text};
    if (code != null) {
      payload['code'] = code;
    }
    return packMessage(payload);
  }

  @override
  String toString() {
    return "ErrorContent: text=$text, code=$code";
  }
}

//
// JsonContent
//
class JsonContent extends Content {
  final Map<String, dynamic> json;

  JsonContent({required this.json});

  static JsonContent unpack(Map<String, dynamic> header, Uint8List payload) {
    return JsonContent(json: header['json'] as Map<String, dynamic>);
  }

  @override
  Uint8List pack() {
    return packMessage({'type': 'json', 'json': json});
  }
}

//
// EmptyContent
//
class EmptyContent extends Content {
  EmptyContent();

  static EmptyContent unpack(Map<String, dynamic> header, Uint8List payload) {
    return EmptyContent();
  }

  @override
  Uint8List pack() {
    return packMessage({'type': 'empty'});
  }

  @override
  String toString() {
    return "EmptyContent";
  }
}

enum ControlCloseStatus {
  normal(1000),
  invalidData(1007);

  const ControlCloseStatus(this.code);
  final int code;
}

class ControlContent extends Content {
  final String method;
  final int? statusCode;
  final String? message;

  ControlContent({required this.method, this.statusCode, this.message});

  static ControlContent unpack(Map<String, dynamic> header, Uint8List payload) {
    final status = header['status_code'];
    int? statusCode;
    if (status is int) {
      statusCode = status;
    } else if (status is num) {
      statusCode = status.toInt();
    } else if (status is String) {
      statusCode = int.tryParse(status);
    }
    return ControlContent(method: header['method'] as String, statusCode: statusCode, message: header['message'] as String?);
  }

  @override
  Uint8List pack() {
    final header = <String, dynamic>{'type': 'control', 'method': method};
    if (method == "close") {
      final closeStatus = statusCode ?? ControlCloseStatus.normal.code;
      header['status_code'] = closeStatus;
      if (message != null) {
        header['message'] = message;
      }
    }
    return packMessage(header);
  }

  @override
  String toString() {
    return "ControlContent: $method";
  }
}

Content unpackContent(Uint8List data) {
  final header = jsonDecode(splitMessageHeader(data)) as Map<String, dynamic>;
  final payload = splitMessagePayload(data);

  final typeKey = header['type'] as String;
  final unpacker = _contentTypes[typeKey];
  if (unpacker == null) {
    throw StateError('Unknown content type: $typeKey');
  }

  return unpacker(header, payload);
}

/// ---------------------------------------------------------------------------
///  Generated on 2025‑08‑01
///  Service Template models – updated to align with the latest Python schema
/// ---------------------------------------------------------------------------

/// Represents the `num` field of `PortSpec`, which can be `'*'` or a
/// positive integer.
class PortNum {
  final int? value; // null ⇒ '*'

  PortNum._(this.value);

  factory PortNum.star() => PortNum._(null);

  factory PortNum.fromInt(int v) {
    if (v <= 0) {
      throw ArgumentError('Port number must be > 0');
    }
    return PortNum._(v);
  }

  factory PortNum.fromJson(dynamic json) {
    if (json == '*' || json == null) return PortNum.star();
    if (json is int) return PortNum.fromInt(json);
    throw ArgumentError('Invalid PortNum value: $json');
  }

  dynamic toJson() => value ?? '*';

  @override
  String toString() => value?.toString() ?? '*';
}

/// ---------------------------------------------------------------------------
///  EndpointSpec
/// ---------------------------------------------------------------------------

class AllowedMcpToolFilter {
  final List<String>? toolNames;
  final bool? readOnly;

  AllowedMcpToolFilter({this.toolNames, this.readOnly});

  factory AllowedMcpToolFilter.fromJson(Map<String, dynamic> json) {
    return AllowedMcpToolFilter(
      toolNames: json['tool_names'] == null ? null : List<String>.from(json['tool_names']),
      readOnly: json['read_only'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {if (toolNames != null) 'tool_names': toolNames, if (readOnly != null) 'read_only': readOnly};
}

class ConnectorRef {
  String? openaiConnectorId;
  String? serverUrl;
  String? clientSecretId;

  ConnectorRef({this.openaiConnectorId, this.serverUrl, this.clientSecretId});

  factory ConnectorRef.fromJson(Map<String, dynamic> json) {
    return ConnectorRef(
      serverUrl: json['server_url'] as String?,
      openaiConnectorId: json['openai_connector_id'] as String?,
      clientSecretId: json['client_secret_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    if (openaiConnectorId != null) 'openai_connector_id': openaiConnectorId,
    if (serverUrl != null) 'server_url': serverUrl,
    if (clientSecretId != null) 'client_secret_id': clientSecretId,
  };
}

class OAuthClientConfig {
  final String? clientId;
  final String? clientSecret;
  final String? authorizationEndpoint;
  final String? tokenEndpoint;
  final bool? noPkce;
  final List<String>? scopes;

  OAuthClientConfig({this.clientId, this.clientSecret, this.authorizationEndpoint, this.tokenEndpoint, this.noPkce, this.scopes});

  factory OAuthClientConfig.fromJson(Map<String, dynamic> json) {
    return OAuthClientConfig(
      clientId: json['client_id'] as String?,
      clientSecret: json['client_secret'] as String?,
      authorizationEndpoint: json['authorization_endpoint'] as String?,
      tokenEndpoint: json['token_endpoint'] as String?,
      noPkce: json['no_pkce'] as bool?,
      scopes: (json['scopes'] as List?)?.cast<String>(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (clientId != null) 'client_id': clientId,
    if (authorizationEndpoint != null) 'authorization_endpoint': authorizationEndpoint,
    if (tokenEndpoint != null) 'token_endpoint': tokenEndpoint,
    if (clientSecret != null) 'client_secret': clientSecret,
    if (noPkce != null) 'no_pkce': noPkce,
    if (scopes != null) 'scopes': scopes,
  };

  OAuthClientConfig copyWith({
    String? clientId,
    String? clientSecret,
    String? authorizationEndpoint,
    String? tokenEndpoint,
    bool? noPkce,
    List<String>? scopes,
  }) {
    return OAuthClientConfig(
      clientId: clientId ?? this.clientId,
      clientSecret: clientSecret ?? this.clientSecret,
      authorizationEndpoint: authorizationEndpoint ?? this.authorizationEndpoint,
      tokenEndpoint: tokenEndpoint ?? this.tokenEndpoint,
      noPkce: noPkce ?? this.noPkce,
      scopes: scopes ?? this.scopes,
    );
  }
}

class MCPEndpointSpec {
  final String label;
  final String? description;
  final List<AllowedMcpToolFilter>? allowedTools;
  final Map<String, String>? headers;
  final String? requireApproval; // "always" | "never"
  final OAuthClientConfig? oauth;
  final String? openaiConnectorId;

  MCPEndpointSpec({
    required this.label,
    this.description,
    this.allowedTools,
    this.headers,
    this.requireApproval,
    this.oauth,
    this.openaiConnectorId,
  });

  MCPEndpointSpec copyWith({
    String? label,
    String? description,
    List<AllowedMcpToolFilter>? allowedTools,
    Map<String, String>? headers,
    String? requireApproval,
    OAuthClientConfig? oauth,
    String? openaiConnectorId,
  }) {
    return MCPEndpointSpec(
      label: label ?? this.label,
      description: description ?? this.description,
      allowedTools: allowedTools ?? this.allowedTools,
      headers: headers ?? this.headers,
      requireApproval: requireApproval ?? this.requireApproval,
      oauth: oauth ?? this.oauth,
      openaiConnectorId: openaiConnectorId ?? this.openaiConnectorId,
    );
  }

  factory MCPEndpointSpec.fromJson(Map<String, dynamic> json) {
    return MCPEndpointSpec(
      label: json['label'] as String,
      description: json['description'] as String?,
      allowedTools: json['allowed_tools'] == null
          ? null
          : (json['allowed_tools'] as List).map((e) => AllowedMcpToolFilter.fromJson(e)).toList(),
      headers: json['headers'] == null ? null : Map<String, String>.from(json['headers']),
      requireApproval: json['require_approval'] as String?,
      oauth: json['oauth'] == null ? null : OAuthClientConfig.fromJson(json['oauth']),
      openaiConnectorId: json['openai_connector_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'label': label,
    'description': description,
    if (allowedTools != null) 'allowed_tools': allowedTools!.map((e) => e.toJson()).toList(),
    if (headers != null) 'headers': headers,
    if (requireApproval != null) 'require_approval': requireApproval,
    if (oauth != null) 'oauth': oauth!.toJson(),
    if (openaiConnectorId != null) 'openai_connector_id': openaiConnectorId,
  };
}

class MeshagentEndpointSpec {
  MeshagentEndpointSpec({required this.identity, this.api});

  final String identity;
  final ApiScope? api;

  factory MeshagentEndpointSpec.fromJson(Map<String, dynamic> json) {
    return MeshagentEndpointSpec(identity: json['identity'] as String, api: json["api"] == null ? null : ApiScope.fromJson(json["api"]));
  }

  Map<String, dynamic> toJson() => {'identity': identity, if (api != null) 'api': api?.toJson()};

  MeshagentEndpointSpec copyWith({String? identity, ApiScope? api}) {
    return MeshagentEndpointSpec(identity: identity ?? this.identity, api: api ?? this.api);
  }
}

class EndpointSpec {
  final String path;
  final MeshagentEndpointSpec? meshagent;
  final MCPEndpointSpec? mcp;
  final Map<String, String>? annotations;

  EndpointSpec({required this.path, this.meshagent, this.mcp, this.annotations});

  factory EndpointSpec.fromJson(Map<String, dynamic> json) {
    return EndpointSpec(
      path: json['path'] as String,
      meshagent: json['meshagent'] == null ? null : MeshagentEndpointSpec.fromJson(json['meshagent']),
      mcp: json['mcp'] == null ? null : MCPEndpointSpec.fromJson(json['mcp']),
      annotations: (json['annotations'] as Map?)?.cast<String, String>(),
    );
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    if (meshagent != null) 'meshagent': meshagent!.toJson(),
    if (mcp != null) 'mcp': mcp!.toJson(),
    if (annotations != null) 'annotations': annotations,
  };

  EndpointSpec copyWith({String? path, MeshagentEndpointSpec? meshagent, MCPEndpointSpec? mcp, Map<String, String>? annotations}) {
    return EndpointSpec(
      path: path ?? this.path,
      meshagent: mcp != null ? null : meshagent ?? this.meshagent,
      mcp: meshagent != null ? null : mcp ?? this.mcp,
      annotations: annotations ?? this.annotations,
    );
  }
}

/// ---------------------------------------------------------------------------
///  PortSpec
/// ---------------------------------------------------------------------------

class PortSpec {
  final PortNum num;
  final String? type; // "http" | "tcp"
  final List<EndpointSpec> endpoints;
  final String? liveness;
  final bool? published;
  final bool? public;
  final Map<String, String>? annotations;

  PortSpec({required this.num, this.type, this.published, this.public, List<EndpointSpec>? endpoints, this.liveness, this.annotations})
    : endpoints = endpoints ?? [];

  factory PortSpec.fromJson(Map<String, dynamic> json) {
    return PortSpec(
      num: PortNum.fromJson(json['num']),
      type: json['type'] as String?,
      endpoints: (json['endpoints'] as List<dynamic>? ?? []).map((e) => EndpointSpec.fromJson(e as Map<String, dynamic>)).toList(),
      liveness: json['liveness'] as String?,
      published: json['published'],
      public: json['public'],
      annotations: (json['annotations'] as Map?)?.cast<String, String>(),
    );
  }

  Map<String, dynamic> toJson() => {
    'num': num.toJson(),

    if (type != null) 'type': type,
    if (endpoints.isNotEmpty) 'endpoints': endpoints.map((e) => e.toJson()).toList(),
    if (liveness != null) 'liveness': liveness,
    if (published != null) 'published': published,
    if (public != null) 'public': public,
    if (annotations != null) 'annotations': annotations,
  };

  PortSpec copyWith({
    PortNum? num,
    String? type,
    List<EndpointSpec>? endpoints,
    String? liveness,
    bool? public,
    bool? published,
    Map<String, String>? annotations,
  }) {
    return PortSpec(
      num: num ?? this.num,
      type: type ?? this.type,
      endpoints: endpoints ?? List<EndpointSpec>.from(this.endpoints),
      liveness: liveness ?? this.liveness,
      published: published ?? this.published,
      public: public ?? this.public,
      annotations: annotations ?? this.annotations,
    );
  }
}

/// ---------------------------------------------------------------------------
///  ServiceTemplateVariable
/// ---------------------------------------------------------------------------

class ServiceTemplateVariable {
  final String name;
  final String? title;
  final String? description;
  final bool obscure;
  final bool optional;
  final String? type;
  final List<String>? enumValues; // mapped to `enum` in JSON
  final Map<String, String>? annotations;

  ServiceTemplateVariable({
    required this.name,
    this.title,
    this.description,
    this.obscure = false,
    this.optional = false,
    this.enumValues,
    this.type,
    this.annotations,
  });

  factory ServiceTemplateVariable.fromJson(Map<String, dynamic> json) {
    return ServiceTemplateVariable(
      name: json['name'] as String,
      title: json['title'] as String?,
      description: json['description'] as String?,
      obscure: json['obscure'] ?? false,
      optional: json['optional'] ?? false,
      type: json['type'],
      enumValues: (json['enum'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
      annotations: (json["annotations"] as Map?)?.cast<String, String>(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (title != null) 'title': title,
    if (description != null) 'description': description,
    'obscure': obscure,
    'optional': optional,
    'type': type,
    if (enumValues != null) 'enum': enumValues,
    if (annotations != null) 'annotations': annotations,
  };
}

class TokenValue {
  final String identity;
  final ApiScope? api;
  final String? role;

  const TokenValue({required this.identity, this.api, this.role});

  factory TokenValue.fromJson(Map<String, dynamic> json) {
    return TokenValue(
      identity: json['identity'] as String,
      api: json['api'] != null ? ApiScope.fromJson(json['api']) : null,
      role: json['role'],
    );
  }

  Map<String, dynamic> toJson() => {'identity': identity, 'api': api?.toJson(), if (role != null) 'role': role};
}

class SecretValue {
  final String identity;
  final String id;

  const SecretValue({required this.identity, required this.id});

  factory SecretValue.fromJson(Map<String, dynamic> json) {
    return SecretValue(identity: json['identity'] as String, id: json['id'] as String);
  }

  Map<String, dynamic> toJson() => {'identity': identity, 'id': id};
}

class EnvironmentVariable {
  final String name;
  final String? value;
  final TokenValue? token;
  final SecretValue? secret;

  EnvironmentVariable({required this.name, this.value, this.token, this.secret});

  factory EnvironmentVariable.fromJson(Map<String, dynamic> json) {
    return EnvironmentVariable(
      name: json['name'] as String,
      value: json['value'] as String?,
      token: json['token'] == null ? null : TokenValue.fromJson(json['token']),
      secret: json['secret'] == null ? null : SecretValue.fromJson(json['secret']),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (value != null) 'value': value,
    if (token != null) 'token': token?.toJson(),
    'secret': secret?.toJson(),
  };
}

extension EnvList on List<EnvironmentVariable> {
  List<EnvironmentVariable> copy() {
    final l = <EnvironmentVariable>[];
    for (var v in this) {
      l.add(EnvironmentVariable(name: v.name, value: v.value));
    }
    return l;
  }
}

/// ---------------------------------------------------------------------------
///  Storage Mount Specs
/// ---------------------------------------------------------------------------

/// Represents a single room storage mount.
class RoomStorageMountSpec {
  final String path;
  final String? subpath;
  final bool? readOnly;

  RoomStorageMountSpec({required this.path, this.subpath, this.readOnly});

  factory RoomStorageMountSpec.fromJson(Map<String, dynamic> json) {
    return RoomStorageMountSpec(path: json['path'] as String, subpath: json['subpath'] as String?, readOnly: json['read_only']);
  }

  Map<String, dynamic> toJson() => {'path': path, if (subpath != null) 'subpath': subpath, if (readOnly != null) 'read_only': readOnly};

  RoomStorageMountSpec copyWith({String? path, String? subpath, bool? readOnly}) {
    return RoomStorageMountSpec(path: path ?? this.path, subpath: subpath ?? this.subpath, readOnly: readOnly ?? this.readOnly);
  }
}

class ConfigMountSpec {
  final String path;

  const ConfigMountSpec({this.path = '/var/run/meshagent'});

  Map<String, dynamic> toJson() => {'path': path};

  static ConfigMountSpec fromJson(Map<String, dynamic> json) {
    return ConfigMountSpec(path: json['path'] as String? ?? '/var/run/meshagent');
  }

  ConfigMountSpec copyWith({String? path}) {
    return ConfigMountSpec(path: path ?? this.path);
  }
}

Map<String, dynamic> _jsonObject(dynamic value) {
  return Map<String, dynamic>.from(value as Map);
}

/// Wrapper for all storage mounts on a template.
class ServiceTemplateContainerMountSpec {
  final List<RoomStorageMountSpec>? room;
  final List<ProjectStorageMountSpec>? project;
  final List<ImageStorageMountSpec>? images;
  final List<FileStorageMountSpec>? files;
  final List<EmptyDirMountSpec>? emptyDirs;
  final List<ConfigMountSpec>? configs;

  ServiceTemplateContainerMountSpec({this.room, this.project, this.images, this.files, this.emptyDirs, this.configs});

  factory ServiceTemplateContainerMountSpec.fromJson(Map<String, dynamic> json) {
    return ServiceTemplateContainerMountSpec(
      room: (json['room'] as List<dynamic>?)?.map((e) => RoomStorageMountSpec.fromJson(_jsonObject(e))).toList(),
      project: (json['project'] as List<dynamic>?)?.map((e) => ProjectStorageMountSpec.fromJson(_jsonObject(e))).toList(),
      images: (json['images'] as List<dynamic>?)?.map((e) => ImageStorageMountSpec.fromJson(_jsonObject(e))).toList(),
      files: (json['files'] as List<dynamic>?)?.map((e) => FileStorageMountSpec.fromJson(_jsonObject(e))).toList(),
      emptyDirs: (json['empty_dirs'] as List<dynamic>?)?.map((e) => EmptyDirMountSpec.fromJson(_jsonObject(e))).toList(),
      configs: (json['configs'] as List<dynamic>?)?.map((e) => ConfigMountSpec.fromJson(_jsonObject(e))).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (room != null) 'room': room!.map((e) => e.toJson()).toList(),
    if (project != null) 'project': project!.map((e) => e.toJson()).toList(),
    if (images != null) 'images': images!.map((e) => e.toJson()).toList(),
    if (files != null) 'files': files!.map((e) => e.toJson()).toList(),
    if (emptyDirs != null) 'empty_dirs': emptyDirs!.map((e) => e.toJson()).toList(),
    if (configs != null) 'configs': configs!.map((e) => e.toJson()).toList(),
  };
}

/// ---------------------------------------------------------------------------
///  ServiceTemplateSpec
/// ---------------------------------------------------------------------------

class ServiceTemplateMetadata {
  ServiceTemplateMetadata({required this.name, this.description, this.icon, this.repo, Map<String, String>? annotations})
    : annotations = annotations ?? {};

  final String name;
  final String? description;
  final String? icon;
  final String? repo;
  final Map<String, String> annotations;

  Map<String, dynamic> toJson() => {
    'name': name,
    if (description != null) 'description': description,
    if (repo != null) 'repo': repo,
    if (icon != null) 'icon': icon,
    'annotations': annotations,
  };

  static ServiceTemplateMetadata fromJson(Map<String, dynamic> json) {
    return ServiceTemplateMetadata(
      name: json['name'] as String,
      description: json['description'] as String?,
      repo: json['repo'] as String?,
      icon: json['icon'] as String?,
      annotations: json['annotations'] != null ? {for (final entry in (json['annotations'] as Map).entries) entry.key: entry.value} : {},
    );
  }
}

class TemplateEnvironmentVariable {
  final String name;
  final String? value;
  final TokenValue? token;

  TemplateEnvironmentVariable({required this.name, this.value, this.token});

  factory TemplateEnvironmentVariable.fromJson(Map<String, dynamic> json) {
    return TemplateEnvironmentVariable(
      name: json['name'] as String,
      value: json['value'] as String?,
      token: json['token'] == null ? null : TokenValue.fromJson(json['token']),
    );
  }

  Map<String, dynamic> toJson() => {'name': name, if (value != null) 'value': value, if (token != null) 'token': token?.toJson()};
}

class ContainerTemplateSpec {
  ContainerTemplateSpec({
    this.environment,
    this.private,
    this.image,
    this.command,
    this.workingDir,
    this.storage,
    this.onDemand,
    this.writableRootFs,
  });

  final String? image;
  final String? command;
  final String? workingDir;
  final List<TemplateEnvironmentVariable>? environment;
  final ServiceTemplateContainerMountSpec? storage;
  final bool? onDemand;
  final bool? writableRootFs;
  final bool? private;

  static ContainerTemplateSpec? fromJson(Map<String, dynamic> json) {
    return ContainerTemplateSpec(
      environment: (json['environment'] as List<dynamic>?)
          ?.map((e) => TemplateEnvironmentVariable.fromJson(e as Map<String, dynamic>))
          .toList(),
      onDemand: json['on_demand'],
      writableRootFs: json['writable_root_fs'],
      image: json['image'] as String?,
      command: json['command'] as String?,
      workingDir: json['working_dir'] as String?,
      storage: json['storage'] == null ? null : ServiceTemplateContainerMountSpec.fromJson(json['storage'] as Map<String, dynamic>),
      private: json['private'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (environment != null) 'environment': environment!.map((e) => e.toJson()).toList(),
      if (image != null) 'image': image,
      if (command != null) 'command': command,
      if (workingDir != null) 'working_dir': workingDir,
      if (storage != null) 'storage': storage!.toJson(),
      if (onDemand != null) 'on_demand': onDemand,
      if (writableRootFs != null) 'writable_root_fs': writableRootFs,
      if (private != null) 'private': private,
    };
  }

  ContainerSpec? toContainerSpec({required Map<String, String> values}) {
    // Build env map with {var} expansion.
    final env = <EnvironmentVariable>[];
    if (environment != null) {
      for (final e in environment!) {
        env.add(EnvironmentVariable(name: e.name, value: e.value?.formatWith(values), token: e.token));
      }
    }

    // Image is required on ServiceSpec; enforce like Pydantic would.
    final img = image;
    if (img == null || img.isEmpty) {
      throw ArgumentError('ServiceTemplateSpec.image is required to build a ServiceSpec');
    }
    return ContainerSpec(
      command: command?.formatWith(values),
      workingDir: workingDir?.formatWith(values),
      image: img,
      environment: env,
      onDemand: onDemand,
      writableRootFs: writableRootFs,
      private: private,
      storage: storage == null
          ? null
          : ContainerMountSpec(
              room: storage!.room,
              project: storage!.project,
              images: storage!.images,
              files: storage!.files,
              emptyDirs: storage!.emptyDirs,
              configs: storage!.configs,
            ),
    );
  }
}

class ExternalServiceTemplateSpec {
  ExternalServiceTemplateSpec({required this.url});

  final String? url;

  static ExternalServiceTemplateSpec fromJson(Map<String, dynamic> json) {
    return ExternalServiceTemplateSpec(url: json["url"]);
  }

  Map<String, dynamic> toJson() {
    return {"url": url};
  }

  ExternalServiceSpec? toExternalSpec({required Map<String, String> values}) {
    return ExternalServiceSpec(url: url?.formatWith(values));
  }
}

class PromptTemplate {
  PromptTemplate({required this.name, this.description, required this.prompt, Map<String, String>? annotations})
    : annotations = annotations ?? const <String, String>{};

  final String name;
  final String? description;
  final String prompt;
  final Map<String, String> annotations;

  Map<String, dynamic> toJson() => {
    'name': name,
    if (description != null) 'description': description,
    'prompt': prompt,
    if (annotations.isNotEmpty) 'annotations': annotations,
  };

  static PromptTemplate fromJson(Map<String, dynamic> json) {
    return PromptTemplate(
      name: json['name'] as String,
      description: json['description'] as String?,
      prompt: json['prompt'] as String,
      annotations: json['annotations'] != null
          ? {for (final entry in (json['annotations'] as Map).entries) entry.key as String: entry.value as String}
          : null,
    );
  }

  PromptTemplate formatWith(Map<String, String> values) {
    return PromptTemplate(
      name: name.formatWith(values),
      description: description?.formatWith(values),
      prompt: prompt.formatWith(values),
      annotations: _formatStringMap(annotations, values),
    );
  }
}

class ChannelSpec {
  const ChannelSpec({Map<String, String>? annotations}) : annotations = annotations ?? const <String, String>{};

  final Map<String, String> annotations;

  Map<String, dynamic> toJson() => {if (annotations.isNotEmpty) 'annotations': annotations};
}

class EmailChannel extends ChannelSpec {
  const EmailChannel({required this.address, this.private = true, super.annotations});

  final String address;
  final bool private;

  @override
  Map<String, dynamic> toJson() => {'address': address, 'private': private, ...super.toJson()};

  static EmailChannel fromJson(Map<String, dynamic> json) {
    return EmailChannel(
      address: json['address'] as String,
      private: (json['private'] as bool?) ?? true,
      annotations: json['annotations'] != null
          ? {for (final entry in (json['annotations'] as Map).entries) entry.key as String: entry.value as String}
          : null,
    );
  }

  EmailChannel formatWith(Map<String, String> values) {
    return EmailChannel(address: address.formatWith(values), private: private, annotations: _formatStringMap(annotations, values));
  }
}

class QueueChannel extends ChannelSpec {
  const QueueChannel({required this.queue, this.threadingMode, this.messageSchema, super.annotations});

  final String queue;
  final String? threadingMode;
  final Map<String, dynamic>? messageSchema;

  @override
  Map<String, dynamic> toJson() => {
    'queue': queue,
    if (threadingMode != null) 'threading_mode': threadingMode,
    if (messageSchema != null) 'message_schema': messageSchema,
    ...super.toJson(),
  };

  static QueueChannel fromJson(Map<String, dynamic> json) {
    return QueueChannel(
      queue: json['queue'] as String,
      threadingMode: json['threading_mode'] as String?,
      messageSchema: (json['message_schema'] as Map?)?.cast<String, dynamic>(),
      annotations: json['annotations'] != null
          ? {for (final entry in (json['annotations'] as Map).entries) entry.key as String: entry.value as String}
          : null,
    );
  }

  QueueChannel formatWith(Map<String, String> values) {
    return QueueChannel(
      queue: queue.formatWith(values),
      threadingMode: threadingMode?.formatWith(values),
      messageSchema: messageSchema == null ? null : Map<String, dynamic>.from(_formatJsonValue(messageSchema!, values) as Map),
      annotations: _formatStringMap(annotations, values),
    );
  }
}

class MessagingChannel extends ChannelSpec {
  const MessagingChannel({this.protocol = 'meshagent.agent-message.v1', List<PromptTemplate>? prompts, super.annotations})
    : prompts = prompts ?? const <PromptTemplate>[];

  final String protocol;
  final List<PromptTemplate> prompts;

  @override
  Map<String, dynamic> toJson() => {
    'protocol': protocol,
    if (prompts.isNotEmpty) 'prompts': prompts.map((entry) => entry.toJson()).toList(),
    ...super.toJson(),
  };

  static MessagingChannel fromJson(Map<String, dynamic> json) {
    return MessagingChannel(
      protocol: (json['protocol'] as String?) ?? 'meshagent.agent-message.v1',
      prompts: (json['prompts'] as List?)?.map((entry) => PromptTemplate.fromJson(entry as Map<String, dynamic>)).toList(),
      annotations: json['annotations'] != null
          ? {for (final entry in (json['annotations'] as Map).entries) entry.key as String: entry.value as String}
          : null,
    );
  }

  MessagingChannel formatWith(Map<String, String> values) {
    return MessagingChannel(
      protocol: protocol.formatWith(values),
      prompts: prompts.map((entry) => entry.formatWith(values)).toList(),
      annotations: _formatStringMap(annotations, values),
    );
  }
}

class ToolkitChannel extends ChannelSpec {
  const ToolkitChannel({required this.name, super.annotations});

  final String name;

  @override
  Map<String, dynamic> toJson() => {'name': name, ...super.toJson()};

  static ToolkitChannel fromJson(Map<String, dynamic> json) {
    return ToolkitChannel(
      name: json['name'] as String,
      annotations: json['annotations'] != null
          ? {for (final entry in (json['annotations'] as Map).entries) entry.key as String: entry.value as String}
          : null,
    );
  }

  ToolkitChannel formatWith(Map<String, String> values) {
    return ToolkitChannel(name: name.formatWith(values), annotations: _formatStringMap(annotations, values));
  }
}

class ChannelsSpec {
  const ChannelsSpec({
    List<EmailChannel>? email,
    List<MessagingChannel>? messaging,
    List<QueueChannel>? queue,
    List<ToolkitChannel>? toolkit,
  }) : email = email ?? const <EmailChannel>[],
       messaging = messaging ?? const <MessagingChannel>[],
       queue = queue ?? const <QueueChannel>[],
       toolkit = toolkit ?? const <ToolkitChannel>[];

  final List<EmailChannel> email;
  final List<MessagingChannel> messaging;
  final List<QueueChannel> queue;
  final List<ToolkitChannel> toolkit;

  Map<String, dynamic> toJson() => {
    if (email.isNotEmpty) 'email': email.map((entry) => entry.toJson()).toList(),
    if (messaging.isNotEmpty) 'messaging': messaging.map((entry) => entry.toJson()).toList(),
    if (queue.isNotEmpty) 'queue': queue.map((entry) => entry.toJson()).toList(),
    if (toolkit.isNotEmpty) 'toolkit': toolkit.map((entry) => entry.toJson()).toList(),
  };

  static ChannelsSpec fromJson(Map<String, dynamic> json) {
    return ChannelsSpec(
      email: (json['email'] as List?)?.map((entry) => EmailChannel.fromJson(entry as Map<String, dynamic>)).toList(),
      messaging: (json['messaging'] as List?)?.map((entry) => MessagingChannel.fromJson(entry as Map<String, dynamic>)).toList(),
      queue: (json['queue'] as List?)?.map((entry) => QueueChannel.fromJson(entry as Map<String, dynamic>)).toList(),
      toolkit: (json['toolkit'] as List?)?.map((entry) => ToolkitChannel.fromJson(entry as Map<String, dynamic>)).toList(),
    );
  }

  ChannelsSpec formatWith(Map<String, String> values) {
    return ChannelsSpec(
      email: email.map((entry) => entry.formatWith(values)).toList(),
      messaging: messaging.map((entry) => entry.formatWith(values)).toList(),
      queue: queue.map((entry) => entry.formatWith(values)).toList(),
      toolkit: toolkit.map((entry) => entry.formatWith(values)).toList(),
    );
  }
}

abstract class AgentInputContent {
  const AgentInputContent();

  Map<String, dynamic> toJson();

  AgentInputContent formatWith(Map<String, String> values);

  static AgentInputContent fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'text':
        return AgentTextContent.fromJson(json);
      case 'file':
        return AgentFileContent.fromJson(json);
    }
    throw ArgumentError.value(json['type'], 'json[type]', 'unsupported agent input content type');
  }
}

class AgentTextContent extends AgentInputContent {
  const AgentTextContent({required this.text});

  final String text;

  @override
  Map<String, dynamic> toJson() => {'type': 'text', 'text': text};

  static AgentTextContent fromJson(Map<String, dynamic> json) {
    return AgentTextContent(text: json['text'] as String);
  }

  @override
  AgentTextContent formatWith(Map<String, String> values) {
    return AgentTextContent(text: text.formatWith(values));
  }
}

class AgentFileContent extends AgentInputContent {
  const AgentFileContent({required this.url, this.name});

  final String url;
  final String? name;

  @override
  Map<String, dynamic> toJson() => {'type': 'file', 'url': url, if (name != null) 'name': name};

  static AgentFileContent fromJson(Map<String, dynamic> json) {
    return AgentFileContent(url: json['url'] as String, name: json['name'] as String?);
  }

  @override
  AgentFileContent formatWith(Map<String, String> values) {
    return AgentFileContent(url: url.formatWith(values), name: name?.formatWith(values));
  }
}

class EmailSpec {
  const EmailSpec({required this.address, this.public = false});

  final String address;
  final bool public;

  Map<String, dynamic> toJson() => {'address': address, 'public': public};

  static EmailSpec fromJson(Map<String, dynamic> json) {
    return EmailSpec(address: json['address'] as String, public: (json['public'] as bool?) ?? false);
  }

  EmailSpec formatWith(Map<String, String> values) {
    return EmailSpec(address: address.formatWith(values), public: public);
  }
}

class HeartbeatSpec {
  const HeartbeatSpec({required this.queue, this.threadId, List<AgentInputContent>? prompt, required this.minutes})
    : prompt = prompt ?? const <AgentInputContent>[];

  final String queue;
  final String? threadId;
  final List<AgentInputContent> prompt;
  final int minutes;

  Map<String, dynamic> toJson() => {
    'queue': queue,
    if (threadId != null) 'thread_id': threadId,
    if (prompt.isNotEmpty) 'prompt': prompt.map((entry) => entry.toJson()).toList(),
    'minutes': minutes,
  };

  static HeartbeatSpec fromJson(Map<String, dynamic> json) {
    return HeartbeatSpec(
      queue: json['queue'] as String,
      threadId: json['thread_id'] as String?,
      prompt: (json['prompt'] as List?)?.map((entry) => AgentInputContent.fromJson(entry as Map<String, dynamic>)).toList(),
      minutes: (json['minutes'] as num).toInt(),
    );
  }

  HeartbeatSpec formatWith(Map<String, String> values) {
    return HeartbeatSpec(
      queue: queue.formatWith(values),
      threadId: threadId?.formatWith(values),
      prompt: prompt.map((entry) => entry.formatWith(values)).toList(),
      minutes: minutes,
    );
  }
}

class AgentSpec {
  AgentSpec({required this.name, this.description, Map<String, dynamic>? annotations, this.channels, this.email, this.heartbeat})
    : annotations = annotations ?? {};

  final String name;
  final String? description;
  final Map<String, dynamic> annotations;
  final ChannelsSpec? channels;
  final EmailSpec? email;
  final HeartbeatSpec? heartbeat;

  Map<String, dynamic> toJson() {
    return {
      "name": name,
      if (description != null) "description": description,
      "annotations": annotations,
      if (channels != null) "channels": channels!.toJson(),
      if (email != null) "email": email!.toJson(),
      if (heartbeat != null) "heartbeat": heartbeat!.toJson(),
    };
  }

  static AgentSpec fromJson(Map<String, dynamic> json) {
    return AgentSpec(
      name: json["name"],
      description: json["description"],
      annotations: json['annotations'] != null ? {for (final entry in (json['annotations'] as Map).entries) entry.key: entry.value} : {},
      channels: json['channels'] != null ? ChannelsSpec.fromJson(json['channels'] as Map<String, dynamic>) : null,
      email: json['email'] != null ? EmailSpec.fromJson(json['email'] as Map<String, dynamic>) : null,
      heartbeat: json['heartbeat'] != null ? HeartbeatSpec.fromJson(json['heartbeat'] as Map<String, dynamic>) : null,
    );
  }
}

class AgentTemplateSpec {
  AgentTemplateSpec({required this.name, this.description, Map<String, dynamic>? annotations, this.channels, this.email, this.heartbeat})
    : annotations = annotations ?? {};

  final String name;
  final String? description;
  final Map<String, dynamic> annotations;
  final ChannelsSpec? channels;
  final EmailSpec? email;
  final HeartbeatSpec? heartbeat;

  Map<String, dynamic> toJson() {
    return {
      "name": name,
      if (description != null) "description": description,
      "annotations": annotations,
      if (channels != null) "channels": channels!.toJson(),
      if (email != null) "email": email!.toJson(),
      if (heartbeat != null) "heartbeat": heartbeat!.toJson(),
    };
  }

  static AgentTemplateSpec fromJson(Map<String, dynamic> json) {
    return AgentTemplateSpec(
      name: json["name"],
      description: json["description"],
      annotations: json['annotations'] != null ? {for (final entry in (json['annotations'] as Map).entries) entry.key: entry.value} : {},
      channels: json['channels'] != null ? ChannelsSpec.fromJson(json['channels'] as Map<String, dynamic>) : null,
      email: json['email'] != null ? EmailSpec.fromJson(json['email'] as Map<String, dynamic>) : null,
      heartbeat: json['heartbeat'] != null ? HeartbeatSpec.fromJson(json['heartbeat'] as Map<String, dynamic>) : null,
    );
  }

  AgentSpec toAgentSpec({required Map<String, String> values}) {
    return AgentSpec(
      name: name.formatWith(values),
      description: description?.formatWith(values),
      annotations: Map<String, dynamic>.from(_formatJsonValue(annotations, values) as Map),
      channels: channels?.formatWith(values),
      email: email?.formatWith(values),
      heartbeat: heartbeat?.formatWith(values),
    );
  }
}

class ServiceTemplateSpec {
  final String version; // default "v1"
  final String kind; // default "ServiceTemplate"
  final List<ServiceTemplateVariable>? variables;
  final ServiceTemplateMetadata metadata;
  final List<PortSpec> ports;
  final ContainerTemplateSpec? container;
  final ExternalServiceTemplateSpec? external;
  final List<AgentTemplateSpec> agents;

  ServiceTemplateSpec({
    this.version = 'v1',
    this.kind = 'ServiceTemplate',
    this.variables,
    required this.metadata,
    List<PortSpec>? ports,
    this.container,
    this.external,
    List<AgentTemplateSpec>? agents,
  }) : ports = ports ?? const [],
       agents = agents ?? const [];

  factory ServiceTemplateSpec.fromYaml(String yaml) {
    return ServiceTemplateSpec.fromJson(jsonDecode(jsonEncode(loadYaml(yaml))));
  }

  factory ServiceTemplateSpec.fromJson(Map<String, dynamic> json) {
    return ServiceTemplateSpec(
      version: json['version'] as String? ?? 'v1',
      kind: json['kind'] as String? ?? 'ServiceTemplate',
      variables: (json['variables'] as List<dynamic>?)?.map((e) => ServiceTemplateVariable.fromJson(e as Map<String, dynamic>)).toList(),
      metadata: ServiceTemplateMetadata.fromJson(json['metadata']),
      ports: (json['ports'] as List<dynamic>? ?? []).map((e) => PortSpec.fromJson(e as Map<String, dynamic>)).toList(),
      container: json['container'] == null ? null : ContainerTemplateSpec.fromJson(json['container']),
      external: json['external'] == null ? null : ExternalServiceTemplateSpec.fromJson(json['external']),
      agents: (json['agents'] as List<dynamic>? ?? []).map((e) => AgentTemplateSpec.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'kind': kind,
    if (variables != null) 'variables': variables!.map((e) => e.toJson()).toList(),
    'metadata': metadata.toJson(),
    if (ports.isNotEmpty) 'ports': ports.map((e) => e.toJson()).toList(),
    if (container != null) 'container': container?.toJson(),
    if (external != null) 'external': external?.toJson(),
    if (agents.isNotEmpty) 'agents': agents.map((e) => e.toJson()).toList(),
  };

  ServiceSpec toServiceSpec({required Map<String, String> values}) {
    return ServiceSpec(
      version: Version.v1,
      kind: Kind.service,
      agents: [for (final a in agents) a.toAgentSpec(values: values)],
      metadata: ServiceMetadata(
        name: metadata.name,
        description: metadata.description,
        repo: metadata.repo,
        icon: metadata.icon,
        annotations: metadata.annotations,
      ),
      ports: ports,
      container: container?.toContainerSpec(values: values),
      external: external?.toExternalSpec(values: values),
    );
  }
}

Map<String, String> _formatStringMap(Map<String, String> original, Map<String, String> values) {
  return {for (final entry in original.entries) entry.key: entry.value.formatWith(values)};
}

Object? _formatJsonValue(Object? value, Map<String, String> values) {
  if (value is String) {
    return value.formatWith(values);
  }
  if (value is Map) {
    return {for (final entry in value.entries) entry.key: _formatJsonValue(entry.value, values)};
  }
  if (value is List) {
    return value.map((entry) => _formatJsonValue(entry, values)).toList();
  }
  return value;
}

extension _StringTemplate on String {
  /// Replace {var} with values['var']; leaves unknown keys as-is.
  String formatWith(Map<String, String> values) {
    final re = RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)\}');
    return replaceAllMapped(re, (m) {
      final k = m.group(1)!;
      return values[k] ?? m.group(0)!; // keep original token if missing
    });
  }
}

enum Version { v1 }

enum Kind { service }

enum Role { user, tool, agent }

enum ApiKeyRole { admin }

enum PortType { mcpSse, meshagentCallable, http, tcp }

class ProjectStorageMountSpec {
  final String path;
  final String? subpath;
  final bool readOnly;

  const ProjectStorageMountSpec({required this.path, this.subpath, this.readOnly = true});

  Map<String, dynamic> toJson() => {'path': path, if (subpath != null) 'subpath': subpath, 'read_only': readOnly};

  static ProjectStorageMountSpec fromJson(Map<String, dynamic> json) {
    return ProjectStorageMountSpec(
      path: json['path'] as String,
      subpath: json['subpath'] as String?,
      readOnly: (json['read_only'] as bool?) ?? true,
    );
  }

  ProjectStorageMountSpec copyWith({String? path, String? subpath, bool? readOnly}) {
    return ProjectStorageMountSpec(path: path ?? this.path, subpath: subpath ?? this.subpath, readOnly: readOnly ?? this.readOnly);
  }
}

class ImageStorageMountSpec {
  final String image;
  final String path;
  final String? subpath;
  final bool readOnly;

  const ImageStorageMountSpec({required this.path, this.subpath, this.readOnly = true, required this.image});

  Map<String, dynamic> toJson() => {'path': path, if (subpath != null) 'subpath': subpath, 'read_only': readOnly, 'image': image};

  static ImageStorageMountSpec fromJson(Map<String, dynamic> json) {
    return ImageStorageMountSpec(
      path: json['path'] as String,
      subpath: json['subpath'] as String?,
      readOnly: (json['read_only'] as bool?) ?? true,
      image: json['image'] as String,
    );
  }

  ImageStorageMountSpec copyWith({String? path, String? subpath, bool? readOnly}) {
    return ImageStorageMountSpec(
      path: path ?? this.path,
      subpath: subpath ?? this.subpath,
      readOnly: readOnly ?? this.readOnly,
      image: image,
    );
  }
}

class FileStorageMountSpec {
  final String text;
  final String path;
  final String? subpath;
  final bool readOnly;

  const FileStorageMountSpec({required this.path, this.subpath, this.readOnly = true, required this.text});

  Map<String, dynamic> toJson() => {'path': path, if (subpath != null) 'subpath': subpath, 'read_only': readOnly, 'text': text};

  static FileStorageMountSpec fromJson(Map<String, dynamic> json) {
    return FileStorageMountSpec(
      path: json['path'] as String,
      subpath: json['subpath'] as String?,
      readOnly: (json['read_only'] as bool?) ?? true,
      text: json['text'] as String,
    );
  }

  FileStorageMountSpec copyWith({String? path, String? subpath, bool? readOnly}) {
    return FileStorageMountSpec(path: path ?? this.path, subpath: subpath ?? this.subpath, readOnly: readOnly ?? this.readOnly, text: text);
  }
}

class EmptyDirMountSpec {
  final String path;
  final bool readOnly;

  const EmptyDirMountSpec({required this.path, this.readOnly = false});

  Map<String, dynamic> toJson() => {'path': path, 'read_only': readOnly};

  static EmptyDirMountSpec fromJson(Map<String, dynamic> json) {
    return EmptyDirMountSpec(path: json['path'] as String, readOnly: (json['read_only'] as bool?) ?? false);
  }

  EmptyDirMountSpec copyWith({String? path, bool? readOnly}) {
    return EmptyDirMountSpec(path: path ?? this.path, readOnly: readOnly ?? this.readOnly);
  }
}

class ContainerMountSpec {
  final List<RoomStorageMountSpec>? room;
  final List<ProjectStorageMountSpec>? project;
  final List<ImageStorageMountSpec>? images;
  final List<FileStorageMountSpec>? files;
  final List<EmptyDirMountSpec>? emptyDirs;
  final List<ConfigMountSpec>? configs;

  const ContainerMountSpec({this.room, this.project, this.images, this.files, this.emptyDirs, this.configs});

  Map<String, dynamic> toJson() => {
    if (room != null && room!.isNotEmpty) 'room': room!.map((e) => e.toJson()).toList(),
    if (project != null && project!.isNotEmpty) 'project': project!.map((e) => e.toJson()).toList(),
    if (images != null && images!.isNotEmpty) 'images': images!.map((e) => e.toJson()).toList(),
    if (files != null && files!.isNotEmpty) 'files': files!.map((e) => e.toJson()).toList(),
    if (emptyDirs != null && emptyDirs!.isNotEmpty) 'empty_dirs': emptyDirs!.map((e) => e.toJson()).toList(),
    if (configs != null && configs!.isNotEmpty) 'configs': configs!.map((e) => e.toJson()).toList(),
  };

  static ContainerMountSpec? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return ContainerMountSpec(
      room: (json['room'] as List?)?.map((e) => RoomStorageMountSpec.fromJson(_jsonObject(e))).toList(),
      project: (json['project'] as List?)?.map((e) => ProjectStorageMountSpec.fromJson(_jsonObject(e))).toList(),
      images: (json['images'] as List?)?.map((e) => ImageStorageMountSpec.fromJson(_jsonObject(e))).toList(),
      files: (json['files'] as List?)?.map((e) => FileStorageMountSpec.fromJson(_jsonObject(e))).toList(),
      emptyDirs: (json['empty_dirs'] as List?)?.map((e) => EmptyDirMountSpec.fromJson(_jsonObject(e))).toList(),
      configs: (json['configs'] as List?)?.map((e) => ConfigMountSpec.fromJson(_jsonObject(e))).toList(),
    );
  }
}

class ServiceApiKeySpec {
  final ApiKeyRole role; // Literal["admin"]
  final String name;
  final bool? autoProvision; // default True in Python

  const ServiceApiKeySpec({this.role = ApiKeyRole.admin, required this.name, this.autoProvision = true});

  Map<String, dynamic> toJson() => {
    'role': _apiKeyRoleToString(role), // always "admin"
    'name': name,
    if (autoProvision != null) 'auto_provision': autoProvision,
  };

  static ServiceApiKeySpec fromJson(Map<String, dynamic> json) {
    return ServiceApiKeySpec(
      role: _apiKeyRoleFromString(json['role'] as String?),
      name: json['name'] as String,
      autoProvision: json['auto_provision'] as bool?,
    );
  }
}

class ServiceMetadata {
  final String name;
  final String? description;
  final String? repo;
  final String? icon;

  final Map<String, String> annotations;
  ServiceMetadata({required this.name, this.description, this.repo, this.icon, Map<String, String>? annotations})
    : annotations = annotations ?? {};

  Map<String, dynamic> toJson() => {
    'name': name,
    if (description != null) 'description': description,
    if (repo != null) 'repo': repo,
    if (icon != null) 'icon': icon,
    'annotations': annotations,
  };

  static ServiceMetadata fromJson(Map<String, dynamic> json) {
    return ServiceMetadata(
      name: json['name'] as String,
      description: json['description'] as String?,
      repo: json['repo'] as String?,
      icon: json['icon'] as String?,
      annotations: json['annotations'] != null ? {for (final entry in (json['annotations'] as Map).entries) entry.key: entry.value} : {},
    );
  }
}

String _versionToString(Version v) => switch (v) {
  Version.v1 => 'v1',
};
Version _versionFromString(String? s) {
  return switch (s) {
    'v1' => Version.v1,
    _ => Version.v1, // default
  };
}

String _kindToString(Kind k) => switch (k) {
  Kind.service => 'Service',
};
Kind _kindFromString(String? s) {
  return switch (s) {
    'Service' => Kind.service,
    _ => Kind.service,
  };
}

String _apiKeyRoleToString(ApiKeyRole r) => 'admin';
ApiKeyRole _apiKeyRoleFromString(String? s) => ApiKeyRole.admin;

class ContainerSpec {
  ContainerSpec({
    this.command,
    this.workingDir,
    required this.image,
    List<EnvironmentVariable>? environment,
    List<String>? secrets,
    this.pullSecret,
    this.storage,
    this.onDemand,
    this.writableRootFs,
    this.private,
  }) : environment = environment ?? [],
       secrets = secrets ?? [];

  final String? command;
  final String? workingDir;
  final String image;
  final List<EnvironmentVariable> environment;
  final List<String> secrets;
  final String? pullSecret;
  final ContainerMountSpec? storage;
  final bool? onDemand;
  final bool? writableRootFs;
  final bool? private;

  static ContainerSpec fromJson(Map<String, dynamic> json) {
    return ContainerSpec(
      command: json['command'] as String?,
      workingDir: json['working_dir'] as String?,
      image: json['image'] as String,
      environment: json['environment'] == null ? null : (json['environment'] as List).map((e) => EnvironmentVariable.fromJson(e)).toList(),
      secrets: (json['secrets'] as List?)?.whereType<String>().toList() ?? const <String>[],
      pullSecret: json['pull_secret'] as String?,
      storage: ContainerMountSpec.fromJson(json['storage'] as Map<String, dynamic>?),
      onDemand: json["on_demand"],
      writableRootFs: json["writable_root_fs"],
      private: json["private"],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (command != null) 'command': command,
      if (workingDir != null) 'working_dir': workingDir,
      'image': image,
      if (environment.isNotEmpty) 'environment': environment.map((x) => x.toJson()).toList(),
      if (secrets.isNotEmpty) 'secrets': secrets,
      if (pullSecret != null) 'pull_secret': pullSecret,
      if (storage != null) 'storage': storage!.toJson(),
      if (onDemand != null) 'on_demand': onDemand,
      if (writableRootFs != null) "writable_root_fs": writableRootFs,
      if (private != null) 'private': private,
    };
  }
}

class ScheduledTaskMetadata {
  ScheduledTaskMetadata({Map<String, String>? annotations}) : annotations = annotations ?? const <String, String>{};

  final Map<String, String> annotations;

  static ScheduledTaskMetadata fromJson(Map<String, dynamic>? json) {
    if (json == null) return ScheduledTaskMetadata();
    return ScheduledTaskMetadata(annotations: (json['annotations'] as Map?)?.cast<String, String>() ?? const <String, String>{});
  }

  Map<String, dynamic> toJson() => {'annotations': annotations};
}

class ScheduledTaskQueueSpec {
  ScheduledTaskQueueSpec({required this.name, Map<String, dynamic>? payload, this.storageWritePath})
    : payload = payload ?? const <String, dynamic>{};

  final String name;
  final Map<String, dynamic> payload;
  final String? storageWritePath;

  static ScheduledTaskQueueSpec fromJson(Map<String, dynamic> json) {
    return ScheduledTaskQueueSpec(
      name: json['name'] as String,
      payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{},
      storageWritePath: json['storage_write_path'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'payload': payload, if (storageWritePath != null) 'storage_write_path': storageWritePath};
}

class ScheduledTaskSpec {
  ScheduledTaskSpec({
    this.version = 'v1',
    this.kind = 'ScheduledTask',
    ScheduledTaskMetadata? metadata,
    required this.schedule,
    this.active = true,
    this.once = false,
    this.queue,
    this.container,
  }) : metadata = metadata ?? ScheduledTaskMetadata() {
    final hasQueue = queue != null;
    final hasContainer = container != null;
    if (hasQueue == hasContainer) {
      throw ArgumentError('ScheduledTaskSpec requires exactly one of queue or container');
    }
  }

  final String version;
  final String kind;
  final ScheduledTaskMetadata metadata;
  final String schedule;
  final bool active;
  final bool once;
  final ScheduledTaskQueueSpec? queue;
  final ContainerSpec? container;

  factory ScheduledTaskSpec.fromYaml(String yaml) {
    return ScheduledTaskSpec.fromJson(jsonDecode(jsonEncode(loadYaml(yaml))));
  }

  static ScheduledTaskSpec fromJson(Map<String, dynamic> json) {
    return ScheduledTaskSpec(
      version: json['version'] as String? ?? 'v1',
      kind: json['kind'] as String? ?? 'ScheduledTask',
      metadata: ScheduledTaskMetadata.fromJson((json['metadata'] as Map?)?.cast<String, dynamic>()),
      schedule: json['schedule'] as String,
      active: json['active'] as bool? ?? true,
      once: json['once'] as bool? ?? false,
      queue: json['queue'] == null ? null : ScheduledTaskQueueSpec.fromJson((json['queue'] as Map).cast<String, dynamic>()),
      container: json['container'] == null ? null : ContainerSpec.fromJson((json['container'] as Map).cast<String, dynamic>()),
    );
  }

  ScheduledTaskSpec copyWith({
    ScheduledTaskMetadata? metadata,
    String? schedule,
    bool? active,
    bool? once,
    ScheduledTaskQueueSpec? queue,
    ContainerSpec? container,
  }) {
    return ScheduledTaskSpec(
      version: version,
      kind: kind,
      metadata: metadata ?? this.metadata,
      schedule: schedule ?? this.schedule,
      active: active ?? this.active,
      once: once ?? this.once,
      queue: container != null ? null : queue ?? this.queue,
      container: queue != null ? null : container ?? this.container,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'kind': kind,
    'metadata': metadata.toJson(),
    'schedule': schedule,
    'active': active,
    'once': once,
    if (queue != null) 'queue': queue!.toJson(),
    if (container != null) 'container': container!.toJson(),
  };
}

class ExternalServiceSpec {
  ExternalServiceSpec({required this.url});

  final String? url;

  static ExternalServiceSpec fromJson(Map<String, dynamic> json) {
    return ExternalServiceSpec(url: json["url"]);
  }

  Map<String, dynamic> toJson() {
    return {"url": url};
  }
}

class ServiceSpec {
  final Version version; // Literal["v1"]
  final ServiceMetadata metadata;
  final Kind kind; // Literal["Service"]
  final String? id;
  final List<PortSpec> ports;

  final ContainerSpec? container;
  List<AgentSpec> agents;

  ServiceSpec({
    this.version = Version.v1,
    required this.metadata,
    this.kind = Kind.service,
    this.id,
    List<PortSpec>? ports,
    this.container,
    this.external,
    List<AgentSpec>? agents,
  }) : ports = ports ?? [],
       agents = agents ?? [];

  final ExternalServiceSpec? external;

  Map<String, dynamic> toJson() => {
    'version': _versionToString(version),
    'kind': _kindToString(kind),
    if (id != null) 'id': id,
    'metadata': metadata.toJson(),

    if (container != null) 'container': container?.toJson(),
    if (external != null) 'external': external?.toJson(),

    if (ports.isNotEmpty) 'ports': ports.map((e) => e.toJson()).toList(),
    if (agents.isNotEmpty) 'agents': agents.map((e) => e.toJson()).toList(),
  };

  factory ServiceSpec.fromYaml(String yaml) {
    return ServiceSpec.fromJson(jsonDecode(jsonEncode(loadYaml(yaml))));
  }

  static ServiceSpec fromJson(Map<String, dynamic> json) {
    return ServiceSpec(
      version: _versionFromString(json['version'] as String?),
      kind: _kindFromString(json['kind'] as String?),
      id: json['id'] as String?,
      metadata: ServiceMetadata.fromJson(json['metadata'] as Map<String, dynamic>),
      ports: (json['ports'] as List?)?.map((e) => PortSpec.fromJson(e as Map<String, dynamic>)).toList() ?? const <PortSpec>[],
      agents: (json['agents'] as List?)?.map((e) => AgentSpec.fromJson(e as Map<String, dynamic>)).toList() ?? const <AgentSpec>[],

      container: json['container'] != null ? ContainerSpec.fromJson(json['container']) : null,
      external: json['external'] != null ? ExternalServiceSpec.fromJson(json['external']) : null,
    );
  }

  ServiceSpec copyWith({
    Version? version,
    ServiceMetadata? metadata,
    Kind? kind,
    String? id,
    List<PortSpec>? ports,
    List<AgentSpec>? agents,
    ContainerSpec? container,
    ExternalServiceSpec? external,
  }) {
    return ServiceSpec(
      version: version ?? this.version,
      metadata: metadata ?? this.metadata,
      kind: kind ?? this.kind,
      id: id ?? this.id,
      ports: ports ?? List<PortSpec>.from(this.ports),
      agents: agents ?? List<AgentSpec>.from(this.agents),
      container: external != null ? null : container ?? this.container,
      external: container != null ? null : external ?? this.external,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SecretsClient  (mirrors the Python version you shared)
// ─────────────────────────────────────────────────────────────────────────────

class OAuthCredentials {
  OAuthCredentials({required this.accessToken, this.refreshToken, this.expiration, this.scopes});

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiration;
  final List<String>? scopes;

  factory OAuthCredentials.fromJson(Map<String, dynamic> json) {
    return OAuthCredentials(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String?,
      expiration: json['expiration'] == null ? null : DateTime.parse(json['expiration'] as String),
      scopes: (json['scopes'] as List?)?.whereType<String>().toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    if (refreshToken != null) 'refresh_token': refreshToken,
    if (expiration != null) 'expiration': expiration!.toUtc().toIso8601String(),
    if (scopes != null) 'scopes': scopes,
  };
}

class OAuthTokenRequest {
  OAuthTokenRequest({
    required this.clientId,
    required this.requestId,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    this.scopes,
    this.challenge,
  });

  final String? challenge;
  final String? clientId;
  final String requestId;
  final String authorizationEndpoint;
  final String tokenEndpoint;
  final List<String>? scopes;
}

/// Optional: if you want a typedef for clarity
typedef OAuthTokenRequestHandler = FutureOr<void> Function(OAuthTokenRequest request);

class SecretRequest {
  SecretRequest({required this.requestId, required this.url, required this.type, this.delegateTo});

  final String requestId;
  final String url;
  final String type;
  final String? delegateTo;
}

typedef SecretRequestHandler = FutureOr<void> Function(SecretRequest request);

class SecretInfo {
  const SecretInfo({required this.id, required this.type, required this.name, this.delegatedTo});

  final String id;
  final String type;
  final String name;
  final String? delegatedTo;

  factory SecretInfo.fromJson(Map<String, dynamic> json) {
    return SecretInfo(
      id: json['id'] as String,
      type: json['type'] as String,
      name: json['name'] as String,
      delegatedTo: json['delegated_to'] as String?,
    );
  }
}

class SecretsClient extends ChangeEmitter {
  SecretsClient({required this.room, this.oauthTokenRequestHandler, this.secretRequestHandler}) {
    // Server -> client: another participant (or the server) requests us to obtain an OAuth token.
    room.protocol.addHandler("secrets.request_oauth_token", _handleClientOAuthTokenRequest);

    // Server -> client: another participant (or the server) requests a secret.
    room.protocol.addHandler("secrets.request_secret", _handleClientSecretRequest);
  }

  final RoomClient room;

  final OAuthTokenRequestHandler? oauthTokenRequestHandler;
  final SecretRequestHandler? secretRequestHandler;

  RoomServerException _unexpectedResponseError(String operation) {
    return RoomServerException("unexpected return type from secrets.$operation");
  }

  Future<Content> _invoke(String operation, dynamic input) async {
    final ToolInput toolInput;
    if (input is Content) {
      toolInput = ToolContentInput(input);
    } else if (input is Map) {
      toolInput = ToolContentInput(JsonContent(json: Map<String, dynamic>.from(input)));
    } else {
      throw RoomServerException("secrets invoke input must be Content or JSON");
    }
    final output = await room.invoke(toolkit: "secrets", tool: operation, input: toolInput);
    if (output is! ToolContentOutput) {
      throw _unexpectedResponseError(operation);
    }
    return output.content;
  }

  // Server sent us a request asking the local user/client to authorize and supply a token.
  Future<void> _handleClientOAuthTokenRequest(Protocol protocol, int messageId, String type, Uint8List bytes) async {
    if (!identical(protocol, room._protocolInstance)) {
      return;
    }
    final header = unpackMessage(bytes).header;

    // Expected shape (matches Python):
    // {
    //   "request_id": "...",
    //   "request": {
    //      "authorization_endpoint": "...",
    //      "token_endpoint": "...",
    //      "participant_id": "...",
    //      "scopes": ["..."],
    //      "timeout": 300
    //   }
    // }
    final String requestId = header["request_id"] as String;
    final req = header["request"]["oauth"] as Map<String, dynamic>;
    final String? clientId = req["client_id"] as String?;

    if (oauthTokenRequestHandler == null) {
      // Mirror Python behavior (raise if no handler).
      throw RoomServerException("No oauth token handler registered");
    }

    final authReq = OAuthTokenRequest(
      clientId: clientId,
      requestId: requestId,
      authorizationEndpoint: req["authorization_endpoint"] as String,
      tokenEndpoint: req["token_endpoint"] as String,
      scopes: (req["scopes"] as List?)?.whereType<String>().toList(),
      challenge: header["challenge"] as String?,
    );

    // Fire and forget, just like the Python version creates a task.
    // Your handler should eventually call `provideOAuthToken(...)`.
    unawaited(
      Future.sync(() => oauthTokenRequestHandler!(authReq)).catchError((Object error, StackTrace stackTrace) {
        Logger.root.warning("OAuth token request handler threw", error, stackTrace);
      }),
    );
  }

  Future<void> _handleClientSecretRequest(Protocol protocol, int messageId, String type, Uint8List bytes) async {
    if (!identical(protocol, room._protocolInstance)) {
      return;
    }
    final header = unpackMessage(bytes).header;

    final String requestId = header["request_id"] as String;
    final req = header["request"] as Map<String, dynamic>;

    if (secretRequestHandler == null) {
      throw RoomServerException("No secret handler registered");
    }

    final secretReq = SecretRequest(
      requestId: requestId,
      url: req["url"] as String,
      type: req["type"] as String,
      delegateTo: req["delegate_to"] as String?,
    );

    unawaited(
      Future.sync(() => secretRequestHandler!(secretReq)).catchError((Object error, StackTrace stackTrace) {
        Logger.root.warning("Secret request handler threw", error, stackTrace);
      }),
    );
  }

  /// Client -> server: Provide the OAuth token in response to a prior inbound request.
  Future<void> provideOAuthAuthorization({required String requestId, required String code}) async {
    await _invoke("provide_oauth_authorization", {"request_id": requestId, "code": code, "error": null});
  }

  /// Client -> server: reject an OAuth token request in response to a prior inbound request.
  Future<void> rejectOAuthAuthorization({required String requestId, required String error}) async {
    await _invoke("provide_oauth_authorization", {"request_id": requestId, "code": null, "error": error});
  }

  Future<void> provideSecret({required String requestId, required Uint8List data}) async {
    await _invoke("provide_secret", BinaryContent(data: data, headers: {"request_id": requestId, "error": null}));
  }

  Future<void> rejectSecret({required String requestId, required String error}) async {
    await _invoke("provide_secret", BinaryContent(data: Uint8List(0), headers: {"request_id": requestId, "error": error}));
  }

  Future<Uint8List> requestSecret({
    required String fromParticipantId,
    required String url,
    required String type,
    int timeout = 60 * 5,
    String? delegateTo,
  }) async {
    final req = <String, dynamic>{
      "url": url,
      "type": type,
      "participant_id": fromParticipantId,
      "timeout": timeout,
      "delegate_to": delegateTo,
    };

    final res = await _invoke("request_secret", req);
    if (res is FileContent) {
      return res.data;
    }
    throw _unexpectedResponseError("request_secret");
  }

  Future<FileContent?> getSecret({String? secretId, String? type, String? name, String? delegatedTo}) async {
    final req = <String, dynamic>{"secret_id": secretId, "type": type, "name": name, "delegated_to": delegatedTo};

    final res = await _invoke("get_secret", req);
    if (res is EmptyContent) {
      return null;
    }
    if (res is FileContent) {
      return res;
    }
    throw _unexpectedResponseError("get_secret");
  }

  Future<void> setSecret({
    String? secretId,
    required Uint8List data,
    String? type,
    String? mimeType,
    String? name,
    String? delegatedTo,
    String? forIdentity,
  }) async {
    final res = await _invoke(
      "set_secret",
      BinaryContent(
        data: data,
        headers: <String, dynamic>{
          "secret_id": secretId,
          "type": type ?? mimeType,
          "name": name,
          "delegated_to": delegatedTo,
          "for_identity": forIdentity,
          "has_data": true,
        },
      ),
    );
    if (res is EmptyContent || res is JsonContent) {
      return;
    }
    throw _unexpectedResponseError("set_secret");
  }

  Future<List<SecretInfo>> listSecrets() async {
    final res = await _invoke("list_secrets", {});

    if (res is JsonContent) {
      final secrets = (res.json['secrets'] as List<dynamic>?)?.map((item) => SecretInfo.fromJson(item as Map<String, dynamic>)).toList();

      return secrets ?? [];
    }

    throw _unexpectedResponseError("list_secrets");
  }

  Future<bool> exists({required String secretId, String? delegatedTo, String? forIdentity}) async {
    final req = <String, dynamic>{"secret_id": secretId, "delegated_to": delegatedTo, "for_identity": forIdentity};

    final res = await _invoke("exists", req);
    if (res is JsonContent && res.json["exists"] is bool) {
      return res.json["exists"] as bool;
    }
    throw _unexpectedResponseError("exists");
  }

  Future<void> deleteSecret({required String secretId, String? delegatedTo}) async {
    final req = <String, dynamic>{"id": secretId, "delegated_to": delegatedTo};

    final res = await _invoke("delete_secret", req);
    if (res is EmptyContent || res is JsonContent) {
      return;
    }
    throw _unexpectedResponseError("delete_secret");
  }

  Future<void> deleteRequestedSecret({required String url, required String type, String? delegatedTo}) async {
    final req = <String, dynamic>{"url": url, "type": type, "delegated_to": delegatedTo};

    final res = await _invoke("delete_requested_secret", req);
    if (res is EmptyContent || res is JsonContent) {
      return;
    }
    throw _unexpectedResponseError("delete_requested_secret");
  }

  /// Client -> server: Ask another participant (or the server) to obtain an OAuth token for us.
  /// Returns the `access_token` string.
  ///
  /// This matches the Python signature:
  ///   request_oauth_token(authorization_endpoint, token_endpoint, scopes, timeout, from_participant_id)
  Future<String?> requestOAuthToken({
    required String fromParticipantId,
    required Uri redirectUri,
    String? delegateTo,
    ConnectorRef? connector,
    OAuthClientConfig? oauth,
    int timeout = 60 * 5,
  }) async {
    final req = {
      "connector": connector?.toJson(),
      "oauth": oauth?.toJson(),
      "redirect_uri": redirectUri.toString(),
      "timeout": timeout,
      "participant_id": fromParticipantId,
      "delegate_to": delegateTo,
    };

    final res = await _invoke("request_oauth_token", req);
    if (res is! JsonContent) {
      throw _unexpectedResponseError("request_oauth_token");
    }
    final accessToken = (res.json["access_token"] as String?) ?? '';
    if (accessToken.isEmpty) {
      return null;
    }
    return accessToken;
  }

  Future<String?> getOfflineOAuthToken({
    ConnectorRef? connector,
    OAuthClientConfig? oauth,
    String? delegatedTo,
    String? delegatedBy,
  }) async {
    final req = <String, dynamic>{
      'connector': connector?.toJson(),
      'oauth': oauth?.toJson(),
      'delegated_by': delegatedBy,
      'delegated_to': delegatedTo,
    };

    final res = await _invoke('get_offline_oauth_token', req);

    if (res is JsonContent) {
      final token = (res.json['access_token'] as String?) ?? '';
      if (token.isEmpty) {
        return null;
      }
      return token;
    }
    throw _unexpectedResponseError('get_offline_oauth_token');
  }
}
