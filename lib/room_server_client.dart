import "dart:async";
import "dart:convert";
import "dart:typed_data";

import "package:meshagent/schema.dart";
import "package:logging/logging.dart";

import 'package:path/path.dart' as path;
import "package:uuid/uuid.dart";

import "protocol.dart";
import "document.dart";
import "runtime.dart";

class RoomServerException implements Exception {
  RoomServerException(this.message);

  final String message;

  @override
  String toString() {
    return message;
  }
}

abstract class Participant {
  Participant({required this.client, required this.id});

  final RoomClient client;
  final String id;
  final Map<String, dynamic> _attributes = {};

  final List<String> _connections = [];

  Iterable<String> get connections {
    return _connections;
  }

  dynamic getAttribute(String name) {
    return _attributes[name];
  }
}

class RemoteParticipant extends Participant {
  RemoteParticipant({required super.client, required super.id, required this.role});

  final String role;
}

class LocalParticipant extends Participant {
  LocalParticipant({required super.client, required super.id});

  void setAttribute(String name, dynamic value) async {
    _attributes[name] = value;
    client.protocol.send("set_attributes", utf8.encode(jsonEncode({name: value}))).catchError((err) {
      Logger.root.log(Level.WARNING, "Unable to send attribute changes", err);
    });
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

  final _completer = Completer<Response>();

  Future<Response> get fut {
    return _completer.future;
  }
}

class _QueuedSync {
  _QueuedSync({required this.path, required this.base64});

  final String path;
  final String base64;
}

abstract class Requirement {
  Requirement({required this.name});

  final String name;

  Map<String, dynamic> toJson();

  static Requirement fromJson(Map<String, dynamic> json) {
    if (json["toolkit"] != null) {
      return RequiredToolkit.fromJson(json);
    } else if (json["schema"] != null) {
      return RequiredSchema.fromJson(json);
    }
    throw Exception("Unexpected requirement");
  }
}

class RequiredSchema extends Requirement {
  // Required toolkits, set tools to null to require all the tools in the toolkit
  RequiredSchema({required super.name});

  @override
  Map<String, dynamic> toJson() {
    return {"toolkit": name};
  }

  static RequiredSchema fromJson(Map<String, dynamic> json) {
    return RequiredSchema(name: "toolkit");
  }
}

class RequiredToolkit extends Requirement {
  // Required toolkits, set tools to null to require all the tools in the toolkit
  RequiredToolkit({required super.name, this.tools});

  final List<String>? tools;

  @override
  Map<String, dynamic> toJson() {
    return {"toolkit": name, "tools": tools};
  }

  static RequiredToolkit fromJson(Map<String, dynamic> from) {
    return RequiredToolkit(name: from["toolkit"], tools: (from["tools"] as List?)?.whereType<String>().toList());
  }
}

class AgentDescription {
  AgentDescription({
    required this.name,
    required this.inputSchema,
    required this.outputSchema,
    required this.description,
    required this.title,
    required this.requires,
    required this.supportsTools,
    required this.labels,
  });

  final String name;
  final String title;
  final String description;
  final Map<String, dynamic>? outputSchema;
  final Map<String, dynamic>? inputSchema;
  final List<Requirement> requires;
  final List<String> labels;
  final bool supportsTools;

  static AgentDescription fromJson(Map<String, dynamic> a) {
    final requires =
        a["requires"] == null
            ? <Requirement>[]
            : [...(a["requires"] as List).map((e) => e["toolkit"] != null ? RequiredToolkit.fromJson(e) : RequiredSchema.fromJson(e))];

    return AgentDescription(
      description: a["description"] ?? "",
      title: a["title"] ?? "",
      name: a["name"],
      inputSchema: a["input_schema"],
      outputSchema: a["output_schema"],
      requires: requires,
      supportsTools: a["supports_tools"] == true,
      labels: a["labels"]?.whereType<String>().toList() ?? [],
    );
  }
}

abstract class RoomEvent {
  RoomEvent();

  String get name;
  String get description;
}

class RoomMessage {
  RoomMessage({required this.fromParticipantId, required this.type, required this.message, this.local = false, this.attachment});

  final bool local;
  final String fromParticipantId;
  final String type;
  final Map<String, dynamic> message;
  final Uint8List? attachment;
}

class RoomMessageEvent extends RoomEvent {
  RoomMessageEvent({required this.message});

  final RoomMessage message;

  String get name {
    return message.type;
  }

  String get description {
    return "a message was received ${jsonEncode(message.message)}";
  }
}

class FileCreatedEvent extends RoomEvent {
  FileCreatedEvent({required this.path});

  final String path;

  String get name => "file created";
  String get description => "a file was created at the path $path";
}

class FileDeletedEvent extends RoomEvent {
  FileDeletedEvent({required this.path});

  final String path;

  String get name => "file deleted";
  String get description => "a file was deleted at the path $path";
}

class FileUpdatedEvent extends RoomEvent {
  FileUpdatedEvent({required this.path});

  final String path;

  String get name => "file updated";
  String get description => "a file was updated at the path $path";
}

class RoomLogEvent extends RoomEvent {
  RoomLogEvent({required this.type, required this.data});

  final String type;
  final Map<String, dynamic> data;

  String get name => type;
  String get description => jsonEncode(data);
}

class RoomClient extends ChangeEmitter {
  RoomClient({required this.protocol}) {
    protocol.addHandler("__response__", _handleResponse);

    protocol.addHandler("connected", _handleParticipant);

    protocol.addHandler("room_ready", _handleRoomReady);

    sync = SyncClient(room: this);
    storage = StorageClient(room: this);
    developer = DeveloperClient(room: this);
    messaging = MessagingClient(room: this);
    agents = AgentsClient(room: this);
    livekit = LivekitClient(room: this);
    queues = QueuesClient(room: this);
  }

  late final LivekitClient livekit;

  late final QueuesClient queues;
  late final SyncClient sync;
  late final StorageClient storage;
  late final DeveloperClient developer;
  late final MessagingClient messaging;
  late final AgentsClient agents;

  final _ready = Completer();

  Future get ready {
    return _ready.future;
  }

  final _pendingRequests = Map<int, _PendingRequest>();

  final Protocol protocol;

  void start() {
    sync.start();
  }

  void dispose() {
    sync.dispose();
    protocol.dispose();
    _localParticipant = null;
  }

  // send a request, optionally with a binary trailer
  Future<Response> sendRequest(String type, Map<String, dynamic> request, {Uint8List? data}) async {
    final requestId = protocol.getNextMessageId();

    final pr = _PendingRequest();
    _pendingRequests[requestId] = pr;

    final message = packMessage(request, data);

    await protocol.send(type, message, id: requestId);
    final response = await pr.fut;
    if (response is ErrorResponse) {
      throw RoomServerException(response.text);
    }
    return response;
  }

  Future<void> _handleResponse(Protocol protocol, int messageId, String type, Uint8List data) async {
    final response = unpackResponse(data);
    print("GOT RESPONSE: $response");
    final requestId = messageId;

    if (_pendingRequests.containsKey(requestId)) {
      final pr = _pendingRequests.remove(requestId)!;
      if (response is ErrorResponse) {
        pr._completer.completeError(RoomServerException(response.text));
      } else {
        pr._completer.complete(response);
      }
    } else {
      // warning
      print("received a response for a request that is not pending $requestId");
    }
    return;
  }

  Future<void> _handleRoomReady(Protocol protocol, int messageId, String type, Uint8List bytes) async {
    final init = json.decode(utf8.decode(bytes));

    _roomName = init["room_name"];
    _roomUrl = init["room_url"];
    _sessionId = init["session_id"];
    _ready.complete(init["room_name"]);
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
    _localParticipant = LocalParticipant(client: this, id: participantId);
    for (final k in attributes.keys) {
      _localParticipant!._attributes[k] = attributes[k];
    }
    notifyListeners();
  }

  final _eventsController = StreamController<RoomEvent>.broadcast();

  StreamSubscription<RoomEvent> listen(void Function(RoomEvent event) handler) {
    return _eventsController.stream.listen(handler);
  }

  Future<void> _handleParticipant(Protocol protocol, int messageId, String type, Uint8List bytes) async {
    final message = jsonDecode(utf8.decode(bytes));
    final type = message["type"];

    switch (type) {
      case "init":
        final participantId = message["participantId"];
        final attributes = message["attributes"];
        _onParticipantInit(participantId, attributes);
    }
  }
}

class SyncClient extends ChangeEmitter {
  SyncClient({required this.room}) {
    room.protocol.addHandler("room.sync", _handleSync);
  }

  void start() {
    room.protocol.start();

    () async {
      await for (final message in _changesToSync.stream) {
        print("sending changes to backend ${message.base64}");
        room.sendRequest("room.sync", {"path": message.path}, data: utf8.encode(message.base64));
      }
    }();
  }

  void dispose() {
    _changesToSync.close();
  }

  final _connectingDocuments = Map<String, Future>();

  final _changesToSync = StreamController<_QueuedSync>();
  final _connectedDocuments = Map<String, MeshDocument>();

  Future<void> _handleSync(Protocol protocol, int messageId, String type, Uint8List bytes) async {
    print("GOT SYNC");
    final headerStr = splitMessageHeader(bytes);
    final payload = splitMessagePayload(bytes);

    final header = jsonDecode(headerStr);
    final path = header["path"];

    final isConnecting = _connectingDocuments[path];
    if (isConnecting != null) {
      await isConnecting;
    }

    if (_connectedDocuments.containsKey(path)) {
      final doc = _connectedDocuments[path]!;
      final base64 = utf8.decode(payload);
      print("GOT SYNC $base64");
      DocumentRuntime.instance.applyBackendChanges(documentId: doc.id, base64: base64);

      if (!doc._synchronized.isCompleted) {
        doc._synchronized.complete(true);
      }
    } else {
      throw RoomServerException("received change for a document that is not connected:$path");
    }
  }

  Future<void> createMeshDocumentWithMeshSchema(String path, MeshSchema schema, [Map<String, dynamic>? json]) async {
    await room.sendRequest("room.create", {"path": path, "schema": schema.toJson(), "json": json});
  }

  Future<void> createMeshDocumentWithFormat(String path, String format, [Map<String, dynamic>? json]) async {
    await room.sendRequest("room.create", {"path": path, "format": format, "json": json});
  }

  Future<MeshDocument> open(String path, {bool create = true}) async {
    if (_connectingDocuments.containsKey(path) || _connectedDocuments.containsKey(path)) {
      throw RoomServerException("Already connected to $path");
    }

    // todo: add support for state vector / partial updates
    // todo: initial bytes loading

    final c = Completer();
    _connectingDocuments[path] = c.future;
    try {
      final result = (await room.sendRequest("room.connect", {"path": path, "create": create})) as JsonResponse;

      MeshSchema schema = MeshSchema.fromJson(result.json["schema"]);
      print(jsonEncode(schema.toJson()));

      final doc = MeshDocument(
        schema: schema,
        sendChangesToBackend: (base64) => _changesToSync.sink.add(_QueuedSync(path: path, base64: base64)),
      );
      _connectedDocuments[path] = doc;
      notifyListeners();

      c.complete();
      return doc;
    } catch (err) {
      c.completeError(err);
      rethrow;
    } finally {
      _connectingDocuments.remove(path);
    }
  }

  Future<void> close(String path) async {
    await room.sendRequest("room.disconnect", {"path": path});

    if (!_connectedDocuments.containsKey(path)) {
      throw RoomServerException("Not connected to $path");
    }

    final doc = _connectedDocuments.remove(path);
    DocumentRuntime.instance.unregisterDocument(doc!);
  }

  Future<void> sync(String path, Uint8List data) async {
    await room.sendRequest("room.sync", {"path": path}, data: data);
  }

  RoomClient room;
}

class MeshDocument extends RuntimeDocument {
  MeshDocument({super.sendChangesToBackend, required super.schema})
    : super(id: const Uuid().v4(), sendChanges: DocumentRuntime.instance.sendChanges) {
    DocumentRuntime.instance.registerDocument(this);
  }

  final _synchronized = Completer();
  Future get synchronized {
    return _synchronized.future;
  }

  void dispose() {
    DocumentRuntime.instance.unregisterDocument(this);
  }
}

class ToolkitDescription {
  ToolkitDescription({required this.title, required this.name, required this.description, required this.tools, this.thumbnailUrl});

  final String title;
  final String name;
  final String description;
  final String? thumbnailUrl;

  late final Map<String, ToolDescription> _byName = Map<String, ToolDescription>.fromEntries(tools.map((e) => MapEntry(e.name, e)));

  final List<ToolDescription> tools;

  ToolDescription? operator [](String name) {
    return _byName[name];
  }

  static ToolkitDescription fromJson(Map<String, dynamic> json, {String? name}) {
    return ToolkitDescription(
      title: json["title"],
      name: name ?? json["name"],
      description: json["description"],
      thumbnailUrl: json["thumbnail_url"],
      tools: [
        if (json["tools"] is List)
          ...(json["tools"] as List).map((tool) {
            return ToolDescription(
              title: tool["title"],
              name: tool["name"],
              description: tool["description"],
              inputSchema: tool["input_schema"],
              thumbnailUrl: tool["thumbnail_url"],
              pricing: tool["pricing"],
              defs: tool["defs"],
            );
          }),
        if (json["tools"] is Map)
          ...(json["tools"] as Map).keys.map((toolName) {
            final tool = json["tools"][toolName];
            return ToolDescription(
              title: tool["title"],
              name: toolName,
              pricing: tool["pricing"],
              description: tool["description"],
              inputSchema: tool["input_schema"],
              thumbnailUrl: tool["thumbnail_url"],
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
    required this.inputSchema,
    required this.defs,
    required this.pricing,
    this.thumbnailUrl,
  });

  final String? pricing;
  final String title;
  final String name;
  final String description;
  final String? thumbnailUrl;
  final Map<String, dynamic> inputSchema;
  final Map<String, dynamic>? defs;
}

class ToolkitConfiguration {
  const ToolkitConfiguration.all({required this.name}) : use = null;

  const ToolkitConfiguration.partial({required this.name, required this.use});

  final String name;
  final List<String>? use;

  Map<String, dynamic> toJson() {
    if (use == null) {
      return {name: {}};
    } else {
      return {
        name: {
          "use": {for (final tool in use!) tool: {}},
        },
      };
    }
  }
}

class LivekitConnectionInfo {
  const LivekitConnectionInfo({required this.url, required this.token});

  final String url;
  final String token;
}

class LivekitClient {
  LivekitClient({required this.room});

  RoomClient room;

  Future<LivekitConnectionInfo> getConnectionInfo() async {
    final response = (await room.sendRequest("livekit.connect", {}) as JsonResponse).json;

    return LivekitConnectionInfo(token: response["token"], url: response["url"]);
  }
}

class AgentsClient extends ChangeEmitter {
  AgentsClient({required this.room});

  RoomClient room;

  Future<void> call({required String name, required String url, required Map<String, dynamic> arguments}) async {
    await room.sendRequest("agent.call", {"name": name, "url": url, "arguments": arguments});
  }

  Future<Map<String, dynamic>> ask({
    required String agentName,
    List<ToolkitConfiguration> toolkits = const [],
    required Map<String, dynamic> arguments,
  }) async {
    try {
      final usedToolkits = {for (final t in toolkits) ...t.toJson()};

      final result =
          (await room.sendRequest("agent.ask", {"arguments": arguments, "agent": agentName, "toolkits": usedToolkits})) as JsonResponse;

      return result.json["answer"];
    } catch (err) {
      rethrow;
    }
  }

  Future<List<ToolkitDescription>> listToolkits() async {
    final result = (await room.sendRequest("agent.list_toolkits", {})) as JsonResponse;

    final toolkits = <ToolkitDescription>[];
    final tools = result.json["tools"];

    for (final name in tools.keys) {
      final json = tools[name];

      toolkits.add(ToolkitDescription.fromJson(json, name: name));
    }

    return toolkits;
  }

  Future<List<AgentDescription>> listAgents() async {
    final result = (await room.sendRequest("agent.list_agents", {}) as JsonResponse);

    final agents = <AgentDescription>[];

    for (final a in result.json["agents"]) {
      agents.add(AgentDescription.fromJson(a));
    }

    return agents;
  }

  Future<Response> invokeTool({required String toolkit, required String tool, required Map<String, dynamic> arguments}) async {
    return await room.sendRequest("agent.invoke_tool", {"toolkit": toolkit, "tool": tool, "arguments": arguments});
  }
}

class StorageClient extends ChangeEmitter {
  StorageClient({required this.room}) {
    room.protocol.addHandler("storage.file.deleted", _handleFileDeleted);
    room.protocol.addHandler("storage.file.updated", _handleFileUpdated);
  }

  RoomClient room;

  Future<void> _handleFileUpdated(Protocol protocol, int messageId, String type, Uint8List bytes) async {
    final data = jsonDecode(utf8.decode(bytes));
    room._eventsController.add(FileUpdatedEvent(path: data["path"]));
  }

  Future<void> _handleFileDeleted(Protocol protocol, int messageId, String type, Uint8List bytes) async {
    final data = jsonDecode(utf8.decode(bytes));
    room._eventsController.add(FileDeletedEvent(path: data["path"]));
  }

  Future<List<StorageEntry>> list(String path) async {
    final response = (await room.sendRequest("storage.list", {"path": path})) as JsonResponse;
    return (response.json["files"] as List).map((f) {
        return StorageEntry(name: f["name"], isFolder: f["is_folder"]);
      }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<void> delete(String path) async {
    (await room.sendRequest("storage.delete", {"path": path}) as JsonResponse);
  }

  Future<FileHandle> open(String path, {bool overwrite = false}) async {
    final response = (await room.sendRequest("storage.open", {"path": path, "overwrite": overwrite}) as JsonResponse);

    return FileHandle(id: response.json["handle"]);
  }

  Future<bool> exists(String path) async {
    final result = await room.sendRequest("storage.exists", {"path": path});

    return (result as JsonResponse).json["exists"];
  }

  Future<void> write(FileHandle handle, Uint8List bytes) async {
    await room.sendRequest("storage.write", {"handle": handle.id}, data: bytes);
  }

  Future<void> close(FileHandle handle) async {
    await room.sendRequest("storage.close", {"handle": handle.id});
  }

  Future<FileResponse> download(String path) async {
    final response = (await room.sendRequest("storage.download", {"path": path}) as FileResponse);

    return response;
  }

  Future<String> downloadUrl(String path) async {
    final response = (await room.sendRequest("storage.download_url", {"path": path}) as JsonResponse).json;

    return response["url"];
  }
}

class DeveloperClient extends ChangeEmitter {
  DeveloperClient({required this.room}) {
    room.protocol.addHandler("developer.log", _handleDeveloperLog);
  }

  RoomClient room;
  Future<void> _handleDeveloperLog(Protocol protocol, int messageId, String type, Uint8List bytes) async {
    final rawJson = jsonDecode(utf8.decode(bytes));
    final type = rawJson["type"];
    final data = rawJson["data"];

    room._eventsController.add(RoomLogEvent(type: type, data: data));
  }

  Future<void> log(String type, Map<String, dynamic> data) async {
    room.protocol.send("developer.log", packMessage({"type": type, "data": data}, null));
  }

  Future<void> enable() async {
    room.protocol.send("developer.watch", packMessage({}, null));
  }

  Future<void> disable() async {
    room.protocol.send("developer.unwatch", packMessage({}, null));
  }
}

class MessageStreamWriter {
  const MessageStreamWriter._({required String streamId, required Participant to, required MessagingClient client})
    : _streamId = streamId,
      _to = to,
      _client = client;

  final String _streamId;
  final Participant _to;
  final MessagingClient _client;

  void write(MessageStreamChunk chunk) async {
    await _client.sendMessage(
      to: _to,
      type: "stream.chunk",
      message: {"stream_id": _streamId, "header": chunk.header},
      attachment: chunk.data,
    );
  }

  void close() async {
    await _client.sendMessage(to: _to, type: "stream.close", message: {"stream_id": _streamId});
  }
}

class MessageStreamReader {
  const MessageStreamReader._({
    required String streamId,
    required Participant to,
    required MessagingClient client,
    required StreamController controller,
  }) : _streamId = streamId,
       _to = to,
       _client = client,
       _controller = controller;

  // ignore: unused_field
  final String _streamId;
  // ignore: unused_field
  final Participant _to;
  // ignore: unused_field
  final MessagingClient _client;
  final StreamController _controller;
}

class MessageStreamChunk {
  MessageStreamChunk({required this.header, required this.data});

  final Map<String, dynamic> header;
  final Uint8List? data;
}

class Queue {
  Queue({required this.name, required this.size});

  final String name;
  final int size;
}

class QueuesClient {
  QueuesClient({required this.room});

  RoomClient room;

  Future<List<Queue>> list() async {
    final response = (await room.sendRequest("queues.list", {})) as JsonResponse;
    return (response.json["queues"] as List).map((i) {
      return Queue(name: i["name"], size: i["size"]);
    }).toList();
  }

  Future<void> open(String name) async {
    (await room.sendRequest("queues.open", {"name": name}));
  }

  Future<void> drain(String name) async {
    (await room.sendRequest("queues.drain", {"name": name}));
  }

  Future<void> close(String name) async {
    (await room.sendRequest("queues.close", {"name": name}));
  }

  Future<void> send(String name, Map<String, dynamic> message, {bool create = true}) async {
    (await room.sendRequest("queues.send", {"name": name, "create": create, "message": message}));
  }

  Future<Map<String, dynamic>?> receive(String name, {bool create = true, bool wait = true}) async {
    final response = (await room.sendRequest("queues.receive", {"name": name, "create": create, "wait": wait}));
    if (response is EmptyResponse) {
      return null;
    } else {
      return (response as JsonResponse).json;
    }
  }
}

class MessagingClient extends ChangeEmitter {
  MessagingClient({required this.room}) {
    room.protocol.addHandler("messaging.send", _handleMessageSend);
  }

  final Map<String, Completer<MessageStreamWriter>> _streamWriters = {};
  final Map<String, MessageStreamReader> _streamReaders = {};

  Future<MessageStreamWriter> createStream({required Participant to, required Map<String, dynamic> header}) async {
    final streamId = Uuid().v4();

    final completer = Completer<MessageStreamWriter>();
    _streamWriters[streamId] = completer;

    await sendMessage(to: to, type: "stream.open", message: {"stream_id": streamId, "header": header});

    return await completer.future;
  }

  Future<void> sendMessage({
    required Participant to,
    required String type,
    required Map<String, dynamic> message,
    Uint8List? attachment,
  }) async {
    await room.sendRequest("messaging.send", {"to_participant_id": to.id, "type": type, "message": message}, data: attachment);
  }

  void Function(MessageStreamReader reader)? _onStreamAcceptCallback;

  Future<void> enable({void Function(MessageStreamReader reader)? onStreamAccept}) async {
    await room.sendRequest("messaging.enable", {});
    _onStreamAcceptCallback = onStreamAccept;
  }

  Future<void> disable() async {
    await room.sendRequest("messaging.disable", {});
  }

  Future<void> broadcastMessage({required String type, required Map<String, dynamic> message, Uint8List? attachment}) async {
    await room.sendRequest("messaging.broadcast", {"type": type, "message": message}, data: attachment);
  }

  final RoomClient room;

  final _participants = Map<String, RemoteParticipant>();
  Iterable<RemoteParticipant> get remoteParticipants {
    return _participants.values;
  }

  Future<void> _handleMessageSend(Protocol protocol, int messageId, String type, Uint8List bytes) async {
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
    } else if (message.type == "stream.open") {
      _onStreamOpen(message);
    } else if (message.type == "stream.accept") {
      _onStreamAccept(message);
    } else if (message.type == "stream.reject") {
      _onStreamReject(message);
    } else if (message.type == "stream.chunk") {
      _onStreamChunk(message);
    } else if (message.type == "stream.close") {
      _onStreamClose(message);
    }

    room._eventsController.add(RoomMessageEvent(message: message));
  }

  void _onParticipantEnabled(RoomMessage message) {
    final data = message.message;
    final participant = RemoteParticipant(client: room, id: data["id"], role: data["role"]);

    for (final k in (data["attributes"] as Map<String, dynamic>).keys) {
      participant._attributes[k] = data["attributes"][k];
    }
    _participants[data["id"]] = participant;

    notifyListeners();
  }

  void _onParticipantAttributes(RoomMessage message) {
    final part = _participants[message.fromParticipantId]!;
    for (final entry in message.message["attributes"].entries) {
      part._attributes[entry.key] = entry.value;
    }
    notifyListeners();
  }

  void _onParticipantDisabled(RoomMessage message) {
    _participants.remove(message.message["id"]);
    notifyListeners();
  }

  void _onMessagingEnabled(RoomMessage message) {
    for (var data in message.message["participants"]) {
      final participant = RemoteParticipant(client: room, id: data["id"], role: data["role"]);

      for (final k in (data["attributes"] as Map<String, dynamic>).keys) {
        participant._attributes[k] = data["attributes"][k];
      }
      _participants[data["id"]] = participant;
    }
    notifyListeners();
  }

  void _onStreamOpen(RoomMessage message) {
    final from = remoteParticipants.where((x) => x.id == message.fromParticipantId).first;
    final streamId = message.message["stream_id"];
    final controller = StreamController<MessageStreamChunk>();
    final reader = MessageStreamReader._(streamId: streamId, to: from, client: this, controller: controller);
    try {
      if (_onStreamAcceptCallback == null) {
        throw Exception("streams are not allowed by this client");
      }
      _onStreamAcceptCallback!(reader);
      sendMessage(to: from, type: "stream.accept", message: {"stream_id": streamId});
    } catch (e) {
      sendMessage(to: from, type: "stream.reject", message: {"stream_id": streamId, "error": e.toString()});
    }

    _streamReaders[streamId] = reader;
    notifyListeners();
  }

  void _onStreamAccept(RoomMessage message) {
    final streamId = message.message["stream_id"];
    // TODO: add hook for accept / reject from client
    _streamWriters[streamId]!.complete(
      MessageStreamWriter._(streamId: streamId, to: remoteParticipants.where((x) => x.id == message.fromParticipantId).first, client: this),
    );
  }

  void _onStreamReject(RoomMessage message) {
    final streamId = message.message["stream_id"];
    _streamWriters[streamId]!.completeError(Exception("The stream was rejected by the remote client"));
  }

  void _onStreamChunk(RoomMessage message) {
    final streamId = message.message["stream_id"];
    _streamReaders[streamId]!._controller.add(MessageStreamChunk(header: message.message, data: message.attachment));
  }

  void _onStreamClose(RoomMessage message) {
    final streamId = message.message["stream_id"];
    _streamReaders[streamId]!._controller.close();
    _streamReaders.remove(streamId);
  }
}

class FileHandle {
  FileHandle({required this.id});

  final String id;
}

class StorageEntry {
  StorageEntry({required this.name, required this.isFolder});

  final String name;
  final bool isFolder;

  String get nameWithoutExtension {
    return path.basenameWithoutExtension(name);
  }
}

/// Abstract Response class
abstract class Response {
  Response();

  /// Abstract pack method to be implemented by subclasses
  Uint8List pack();
}

/// A dictionary-like structure to map a 'type' string to an 'unpack' function.
final Map<String, Response Function(Map<String, dynamic> header, Uint8List payload)> _responseTypes = {
  'link': LinkResponse.unpack,
  'file': FileResponse.unpack,
  'text': TextResponse.unpack,
  'error': ErrorResponse.unpack,
  'json': JsonResponse.unpack,
  'empty': EmptyResponse.unpack,
};

//
// LinkResponse
//
class LinkResponse extends Response {
  final String url;
  final String name;

  LinkResponse({required this.url, required this.name});

  static LinkResponse unpack(Map<String, dynamic> header, Uint8List payload) {
    return LinkResponse(url: header['url'] as String, name: header['name'] as String);
  }

  @override
  Uint8List pack() {
    return packMessage({'type': 'link', 'name': name, 'url': url});
  }

  @override
  String toString() {
    return "LinkResponse ($name): $url";
  }
}

//
// FileResponse
//
class FileResponse extends Response {
  final Uint8List data;
  final String name;
  final String mimeType;

  FileResponse({required this.data, required this.name, required this.mimeType});

  static FileResponse unpack(Map<String, dynamic> header, Uint8List payload) {
    return FileResponse(data: payload, name: header['name'] as String, mimeType: header['mime_type'] as String);
  }

  @override
  Uint8List pack() {
    return packMessage({'type': 'file', 'name': name, 'mime_type': mimeType}, data);
  }

  @override
  String toString() {
    return "FileResponse ($mimeType): $name ";
  }
}

//
// TextResponse
//
class TextResponse extends Response {
  final String text;

  TextResponse({required this.text});

  static TextResponse unpack(Map<String, dynamic> header, Uint8List payload) {
    return TextResponse(text: header['text'] as String);
  }

  @override
  Uint8List pack() {
    return packMessage({'type': 'text', 'text': text});
  }

  @override
  String toString() {
    return "TextResponse: $text";
  }
}

//
// ErrorResponse
//
class ErrorResponse extends Response {
  final String text;

  ErrorResponse({required this.text});

  static ErrorResponse unpack(Map<String, dynamic> header, Uint8List payload) {
    return ErrorResponse(text: header['text'] as String);
  }

  @override
  Uint8List pack() {
    return packMessage({'type': 'error', 'text': text});
  }

  @override
  String toString() {
    return "ErrorResponse: $text";
  }
}

//
// JsonResponse
//
class JsonResponse extends Response {
  final Map<String, dynamic> json;

  JsonResponse({required this.json});

  static JsonResponse unpack(Map<String, dynamic> header, Uint8List payload) {
    return JsonResponse(json: header['json'] as Map<String, dynamic>);
  }

  @override
  Uint8List pack() {
    return packMessage({'type': 'json', 'json': json});
  }
}

//
// EmptyResponse
//
class EmptyResponse extends Response {
  EmptyResponse();

  static EmptyResponse unpack(Map<String, dynamic> header, Uint8List payload) {
    return EmptyResponse();
  }

  @override
  Uint8List pack() {
    return packMessage({'type': 'empty'});
  }

  @override
  String toString() {
    return "EmptyResponse";
  }
}

Response unpackResponse(Uint8List data) {
  final header = jsonDecode(splitMessageHeader(data));
  final payload = splitMessagePayload(data);

  final typeKey = header['type'] as String;

  if (!_responseTypes.containsKey(typeKey)) {
    throw StateError('Unknown response type: $typeKey');
  }

  // Delegate to the correct `unpack` function
  return _responseTypes[typeKey]!(header, payload);
}
