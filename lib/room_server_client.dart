import "dart:async";
import "dart:convert";
import "dart:typed_data";

import "package:meshagent/agents_client.dart";
import "package:meshagent/meshagent.dart";
import "package:meshagent/queues_client.dart";
import "package:logging/logging.dart";

import 'package:path/path.dart' as path;
import "package:uuid/uuid.dart";

import "runtime.dart";
import "database_client.dart";
import "livekit_client.dart";

import "package:http/http.dart";

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
    client.protocol.send("set_attributes", packMessage({name: value})).catchError((err) {
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
  RequiredSchema({required super.name});

  @override
  Map<String, dynamic> toJson() {
    return {"schema": name};
  }

  static RequiredSchema fromJson(Map<String, dynamic> json) {
    return RequiredSchema(name: "schema");
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
    this.outputSchema,
    required this.description,
    required this.title,
    List<Requirement>? requires,
    required this.supportsTools,
    List<String>? labels,
  }) : requires = List<Requirement>.of(requires ?? const <Requirement>[]),
       labels = List<String>.of(labels ?? const <String>[]);

  final String name;
  final String title;
  final String description;
  final Map<String, dynamic>? outputSchema;
  final Map<String, dynamic>? inputSchema;
  final List<Requirement>? requires;
  final List<String>? labels;
  final bool supportsTools;

  Map<String, dynamic> toJson() {
    return {
      "name": name,
      "title": title,
      "description": description,
      "input_schema": inputSchema,
      "output_schema": outputSchema,
      "labels": labels,
      "supports_tools": supportsTools,
      "requires": requires?.map((requirement) => requirement.toJson()).toList(),
    };
  }

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
      labels: a["labels"]?.whereType<String>().toList(),
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

class RoomClient extends ChangeEmitter {
  RoomClient({required this.protocol, OAuthTokenRequestHandler? oauthTokenRequestHandler}) {
    protocol.addHandler("__response__", _handleResponse);

    protocol.addHandler("connected", _handleParticipant);

    protocol.addHandler("room_ready", _handleRoomReady);

    protocol.addHandler("room.status", _handleRoomStatus);

    sync = SyncClient(room: this);
    storage = StorageClient(room: this);
    developer = DeveloperClient(room: this);
    messaging = MessagingClient(room: this);
    agents = AgentsClient(room: this);
    livekit = LivekitClient(room: this);
    queues = QueuesClient(room: this);
    database = DatabaseClient(room: this);
    containers = ContainersClient(room: this);
    secrets = SecretsClient(room: this, oauthTokenRequestHandler: oauthTokenRequestHandler);
  }

  late final LivekitClient livekit;

  late final QueuesClient queues;
  late final SyncClient sync;
  late final StorageClient storage;
  late final DeveloperClient developer;
  late final MessagingClient messaging;
  late final AgentsClient agents;
  late final DatabaseClient database;
  late final ContainersClient containers;
  late final SecretsClient secrets;

  final _ready = Completer();

  Future get ready {
    return _ready.future;
  }

  final _pendingRequests = <int, _PendingRequest>{};

  final Protocol protocol;

  Future<Map<String, dynamic>> exec({
    required String name,
    required String image,
    required String? command,
    required String? pullSecret,
    String? participantName,
    String? role,
    Map<String, String>? env,
    String? roomStoragePath,
  }) async {
    final ws = (protocol.channel as WebSocketProtocolChannel);
    final baseUrl = ws.url.toString();

    final uri = Uri.parse('$baseUrl/exec').replace(scheme: ws.url.scheme.replaceAll("ws", "http"));

    final response = await post(
      uri,
      headers: {"Authorization": "Bearer ${ws.jwt}"},
      body: jsonEncode({
        "image": image,
        "name": name,
        "command": command,
        "pull_secret": pullSecret,
        "env": env,
        "room_storage_path": roomStoragePath,
        "participant_name": participantName,
        "role": role,
      }),
    );

    if (response.statusCode >= 400) {
      throw Exception(
        'Failed to execute. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> start({void Function()? onDone, void Function(Object? error)? onError}) async {
    protocol.start(onDone: onDone, onError: onError);

    sync.start();

    await ready;
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
    final requestId = messageId;

    if (_pendingRequests.containsKey(requestId)) {
      final pr = _pendingRequests.remove(requestId)!;
      if (response is ErrorResponse) {
        pr._completer.completeError(RoomServerException(response.text));
      } else {
        pr._completer.complete(response);
      }
    } else {
      Logger.root.log(Level.WARNING, "received a response for a request that is not pending $requestId");
    }
    return;
  }

  Future<void> _handleRoomStatus(Protocol protocol, int messageId, String type, Uint8List bytes) async {
    final payload = unpackMessage(bytes).header;

    _eventsController.add(RoomStatusEvent.fromJson(payload));
  }

  Future<void> _handleRoomReady(Protocol protocol, int messageId, String type, Uint8List bytes) async {
    final init = unpackMessage(bytes).header;

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

  Stream<RoomEvent> get events {
    return _eventsController.stream;
  }

  StreamSubscription<RoomEvent> listen(void Function(RoomEvent event) handler) {
    return _eventsController.stream.listen(handler);
  }

  Future<void> _handleParticipant(Protocol protocol, int messageId, String type, Uint8List bytes) async {
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

class ImagePullResult {
  ImagePullResult({required this.logs});

  final List<String> logs;
}

enum ContextEncoding { gzip }

/// ------------------------------
/// BuildSourceGit
/// ------------------------------
///
class BuildSource {}

class BuildSourceGit extends BuildSource {
  final String url;
  final String? ref;
  final String? username;
  final String? password;
  final String? path;

  BuildSourceGit({required this.url, this.ref, this.username, this.password, this.path});

  Map<String, dynamic> toJson() => {'url': url, 'ref': ref, 'username': username, 'password': password, 'path': path};
}

/// ------------------------------
/// BuildSourceContext
/// ------------------------------
class BuildSourceContext extends BuildSource {
  final String encoding;
  final Uint8List context;

  BuildSourceContext({this.encoding = 'gzip', required this.context});

  Map<String, dynamic> toJson() => {'encoding': encoding};
}

/// ------------------------------
/// BuildSourceRoom
/// ------------------------------
class BuildSourceRoom extends BuildSource {
  final String path;

  BuildSourceRoom({required this.path});

  Map<String, dynamic> toJson() => {'path': path};
}

/// ------------------------------
/// BuildRequest
/// ------------------------------
class _BuildRequest {
  _BuildRequest({this.requestId, required this.tag, this.git, this.context, this.room, this.credentials = const []});

  final String? requestId;
  final String tag;
  final BuildSourceGit? git;
  final BuildSourceContext? context;
  final BuildSourceRoom? room;

  /// One or more registry secrets: passed straight to the server so the
  /// backend can authenticate before `docker pull` / `push`.
  final List<DockerSecret> credentials;

  Map<String, dynamic> toJson() => {
    if (requestId != null) 'request_id': requestId,
    'tag': tag,
    if (git != null) 'git': git!.toJson(),
    if (context != null) 'context': context!.toJson(),
    if (room != null) 'room': room!.toJson(),
    if (credentials.isNotEmpty) 'credentials': credentials.map((c) => c.toJson()).toList(),
  };
}

class _ImagePullRequest {
  _ImagePullRequest({required this.tag, this.credentials = const [], this.requestId});

  final String? requestId;
  final String tag;
  final List<DockerSecret> credentials;

  Map<String, dynamic> toJson() => {
    if (requestId != null) 'request_id': requestId,
    'tag': tag,
    if (credentials.isNotEmpty) 'credentials': credentials.map((c) => c.toJson()).toList(),
  };
}

class _RunRequest {
  _RunRequest({
    required this.image,
    required this.command,
    this.env = const {},
    this.mountPath,
    this.mountSubpath,
    this.role,
    this.participantName,
    this.ports = const {},
    this.credentials = const [],
    this.requestId,
    this.detach,
    this.variables,
    this.tty,
    this.name,
    this.gc,
  }) : assert(mountPath == null || mountPath.startsWith('/'), 'mountPath must start with "/"');

  final String? name;
  final String? requestId;
  final String image;
  final String? command;
  final Map<String, String> env;
  final String? mountPath;
  final String? mountSubpath;
  final String? role;
  final String? participantName;
  final Map<int, int> ports;
  final List<DockerSecret> credentials;
  final bool? detach;
  final bool? tty;
  final Map<String, String>? variables;
  final bool? gc;

  Map<String, dynamic> toJson() => {
    if (requestId != null) 'request_id': requestId,
    'name': name,
    'image': image,
    'command': command,
    'env': env,
    'mount_path': mountPath,
    'mount_subpath': mountSubpath,
    'role': role,
    'participant_name': participantName,
    'ports': {for (final e in ports.entries) e.key.toString(): e.value.toString()},
    'variables': variables,
    if (detach != null) 'detach': detach,
    if (tty != null) 'tty': tty,
    if (credentials.isNotEmpty) 'credentials': credentials.map((c) => c.toJson()).toList(),
    if (gc != null) 'gc': gc,
  };
}

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

/// Single build (as returned by `containers.list_builds`)
class BuildInfo {
  BuildInfo({required this.requestId, required this.tag, required this.status, this.error, this.result});

  final String requestId;
  final String tag;
  final String status; // "running" | "finished" | "errored"
  final String? error; // present when status == "errored"
  final dynamic result; // whatever `aux` object the backend returned

  factory BuildInfo.fromJson(Map<String, dynamic> json) => BuildInfo(
    requestId: json['request_id'] as String,
    tag: json['tag'] as String,
    status: json['status'] as String,
    error: json['error'] as String?,
    result: json['result'],
  );
}

/// Lightweight image description (from `containers.list_images`)
class DockerImage {
  DockerImage({required this.id, required this.tags, required this.size, required this.created, required this.labels, this.manifest});

  final String id;
  final List<String> tags;
  final int? size; // bytes
  final int? created; // seconds since epoch
  final Map<String, dynamic> labels;
  final ServiceTemplateSpec? manifest;

  factory DockerImage.fromJson(Map<String, dynamic> json) => DockerImage(
    id: json['id'] as String,
    tags: (json['tags'] as List?)?.cast<String>() ?? const [],
    size: json['size'] as int?,
    created: json['created'] as int?,
    manifest: json['manifest'] == null ? null : ServiceTemplateSpec.fromJson(json['manifest']),
    labels: Map<String, dynamic>.from(json['labels'] as Map? ?? {}),
  );
}

class ContainerRun {
  ContainerRun._(this._client, this._requestId);

  final RoomClient _client;
  final String _requestId;

  final _result = Completer<int>();

  Future<int> get result {
    return _result.future;
  }

  Future<void> write(Uint8List data) async {
    await _client.sendRequest("containers.container_input", {"request_id": _requestId, "channel": 1}, data: data);
  }

  Future<void> resize({required int width, required int height}) async {
    await _client.sendRequest("containers.container_input", {"request_id": _requestId, "channel": 4, "width": width, "height": height});
  }

  final _stdoutController = StreamController<Uint8List>();

  Stream<Uint8List> get output {
    return _stdoutController.stream;
  }

  void _close(int code) {
    _result.complete(code);
    _stdoutController.close();
  }

  void _closeError(Object error) {
    _result.completeError(error);
    _stdoutController.close();
  }
}

class ContainersClient extends ChangeEmitter {
  ContainersClient({required this.room}) {
    room.protocol.addHandler("containers.log.chunk", _handleLogChunk);
    room.protocol.addHandler("containers.run.output", _handleContainerOutput);
    room.protocol.addHandler("containers.progress", _handleProgress);
  }

  final Map<String, ContainerRun> _ttys = {};

  Future<void> _handleLogChunk(Protocol protocol, int messageId, String type, Uint8List bytes) async {
    final chunk = unpackMessage(bytes).header;
    _loggers[chunk["request_id"]]!.sink.add(chunk["log"]);
  }

  Future<void> _handleContainerOutput(Protocol protocol, int messageId, String type, Uint8List bytes) async {
    final message = unpackMessage(bytes);
    String requestId = message.header["request_id"];
    num channel = message.header["channel"];
    final tty = _ttys[requestId];
    if (tty == null) {
      // tty has been closed
      return;
    }

    if (channel == 0) {
      tty._stdoutController.add(message.payload);
    }
  }

  Future<void> _handleProgress(Protocol protocol, int messageId, String type, Uint8List bytes) async {
    final chunk = unpackMessage(bytes).header;
    final detail = chunk["detail"] as Map<String, dynamic>?;
    if (detail != null) {
      final total = detail["total"] as num?;
      final current = detail["current"] as num?;
      final message = chunk["message"] as String;
      final layer = chunk["layer"] as String;

      _progress[chunk["request_id"]]!.sink.add(
        LogProgress(layer: layer, message: message, current: current?.toInt(), total: total?.toInt()),
      );
    }
  }

  final Map<String, StreamController<String>> _loggers = {};
  final Map<String, StreamController<LogProgress>> _progress = {};
  RoomClient room;

  /// Fetch the *in‑memory* list of builds tracked by the server.
  ///
  /// Each [BuildInfo] entry reports current status (`running`, `finished`,
  /// `errored`) together with any error / result payload.
  Future<List<BuildInfo>> listBuilds() async {
    final res = await room.sendRequest('containers.list_builds', {}) as JsonResponse;

    return (res.json['builds'] as List).map((b) => BuildInfo.fromJson(b as Map<String, dynamic>)).toList();
  }

  /// Attempt to cancel a running build (`containers.stop_build`).
  Future<void> stopBuild({required String requestId}) async {
    await room.sendRequest('containers.stop_build', {'request_id': requestId});
  }

  /// ------------------------------------------------------------------------
  /// Images
  /// ------------------------------------------------------------------------

  /// Return *all* local images (similar to `docker images`).
  Future<List<DockerImage>> listImages() async {
    final res = await room.sendRequest('containers.list_images', {}) as JsonResponse;

    return (res.json['images'] as List).map((i) => DockerImage.fromJson(i as Map<String, dynamic>)).toList();
  }

  /// Delete an image by tag or ID (force = true on the server).
  Future<void> deleteImage({required String image}) async {
    await room.sendRequest('containers.delete_image', {'image': image});
  }

  LogStream<void> build({required String tag, required BuildSource source, List<DockerSecret> credentials = const []}) {
    final requestId = Uuid().v4().toString();
    final controller = StreamController<String>();
    final progress = StreamController<LogProgress>();
    final completer = Completer();
    final stream = LogStream._(completer, controller.stream, progress.stream, () async {
      await room.sendRequest('containers.stop_build', {'request_id': requestId});
    });
    _loggers[requestId] = controller;
    _progress[requestId] = progress;

    final req = _BuildRequest(
      tag: tag,
      requestId: requestId,
      git: source is BuildSourceGit ? source : null,
      room: source is BuildSourceRoom ? source : null,
      context: source is BuildSourceContext ? source : null,
      credentials: credentials,
    );

    room
        .sendRequest("containers.build", req.toJson(), data: source is BuildSourceContext ? source.context : null)
        .then(
          (result) {
            controller.close();
            completer.complete();
            _loggers.remove(requestId);
          },
          onError: (error) {
            completer.completeError(error);
            _loggers.remove(requestId);
          },
        );

    return stream;
  }

  LogStream<ImagePullResult> pullImage({required String tag, List<DockerSecret> credentials = const []}) {
    final requestId = Uuid().v4().toString();
    final controller = StreamController<String>();
    final completer = Completer<ImagePullResult>();
    final progress = StreamController<LogProgress>();

    final stream = LogStream<ImagePullResult>._(completer, controller.stream, progress.stream, () async {
      await room.sendRequest('containers.stop_logs', {'request_id': requestId});
    });
    _loggers[requestId] = controller;
    _progress[requestId] = progress;

    final req = _ImagePullRequest(requestId: requestId, tag: tag, credentials: credentials);

    room
        .sendRequest("containers.pull_image", req.toJson())
        .then(
          (result) {
            final json = result as JsonResponse;

            controller.close();
            completer.complete(ImagePullResult(logs: (json.json["logs"] as List).map((l) => l as String).toList()));
            _loggers.remove(requestId);
          },
          onError: (error) {
            controller.close();
            completer.completeError(error);
            _loggers.remove(requestId);
          },
        );

    return stream;
  }

  LogStream<ContainerRunResult> run({
    required String image,
    String? command,
    Map<String, String> env = const {},
    String? mountPath,
    String? mountSubpath,
    String? role,
    String? participantName,
    Map<int, int> ports = const {},
    Map<String, String>? variables,
    List<DockerSecret> credentials = const [],
    String? name,
    bool? gc,
  }) {
    final requestId = Uuid().v4().toString();
    final controller = StreamController<String>();
    final completer = Completer<ContainerRunResult>();
    final progress = StreamController<LogProgress>();

    final stream = LogStream<ContainerRunResult>._(completer, controller.stream, progress.stream, () async {
      await room.sendRequest('containers.stop_container', {'request_id': requestId});
    });
    _loggers[requestId] = controller;
    _progress[requestId] = progress;

    final req = _RunRequest(
      name: name,
      requestId: requestId,
      image: image,
      command: command,
      env: env,
      mountPath: mountPath,
      mountSubpath: mountSubpath,
      role: role,
      participantName: participantName,
      ports: ports,
      credentials: credentials,
      detach: true,
      variables: variables,
      gc: gc,
    );

    room
        .sendRequest("containers.run", req.toJson())
        .then(
          (result) {
            final json = result as JsonResponse;

            controller.close();
            completer.complete(
              ContainerRunResult(status: json.json["status"], logs: (result.json["logs"] as List).map((l) => l as String).toList()),
            );
            _loggers.remove(requestId);
          },
          onError: (error) {
            controller.close();
            completer.completeError(error);
            _loggers.remove(requestId);
          },
        );

    return stream;
  }

  ContainerRun runAttached({
    required String image,
    String? command,
    Map<String, String> env = const {},
    String? mountPath,
    String? mountSubpath,
    String? role,
    String? participantName,
    Map<int, int> ports = const {},
    Map<String, String>? variables,
    List<DockerSecret> credentials = const [],
    bool tty = false,
    String? name,
    bool? gc,
  }) {
    final requestId = Uuid().v4().toString();

    final req = _RunRequest(
      name: name,
      requestId: requestId,
      image: image,
      command: command,
      env: env,
      mountPath: mountPath,
      mountSubpath: mountSubpath,
      role: role,
      participantName: participantName,
      ports: ports,
      credentials: credentials,
      tty: tty,
      detach: false,
      variables: variables,
      gc: gc,
    );

    final container = ContainerRun._(room, requestId);
    _ttys[requestId] = container;

    room
        .sendRequest("containers.run", req.toJson())
        .then(
          (result) {
            _ttys.remove(requestId);
            final json = result as JsonResponse;
            container._close(json.json["status"]);
          },
          onError: (error) {
            _ttys.remove(requestId);
            container._closeError(error);
          },
        );

    return container;
  }

  Future<void> stop({required String containerId}) async {
    await room.sendRequest("containers.stop_container", {"id": containerId});
  }

  LogStream<void> logs({required String containerId, bool follow = false}) {
    final requestId = Uuid().v4().toString();
    final controller = StreamController<String>();
    final completer = Completer();
    final progress = StreamController<LogProgress>();

    final stream = LogStream._(completer, controller.stream, progress.stream, () async {
      await room.sendRequest('containers.stop_logs', {'request_id': requestId});
    });
    _loggers[requestId] = controller;
    _progress[requestId] = progress;

    room
        .sendRequest("containers.logs", {"request_id": requestId, "id": containerId, "follow": follow})
        .then(
          (_) {
            controller.close();
            completer.complete();
            _loggers.remove(requestId);
          },
          onError: (error) {
            controller.close();
            completer.completeError(error);
            _loggers.remove(requestId);
          },
        );

    return stream;
  }

  Future<List<RoomContainer>> list({bool? all}) async {
    final res = await room.sendRequest("containers.list_containers", {"all": all}) as JsonResponse;

    return (res.json["containers"] as List).map((i) => RoomContainer.fromJson(i as Map<String, dynamic>)).toList();
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
    required this.command,
    required this.entrypoint,
    required this.environment,
    required this.startedBy,
    this.manifest,
  });
  final String id;
  final String image;
  final List<String>? command;
  final List<String>? entrypoint;
  final Map<String, String> environment;
  final ParticipantInfo startedBy;
  final Map<String, dynamic>? manifest;

  static RoomContainer fromJson(Map<String, dynamic> json) {
    return RoomContainer(
      id: json["id"],
      image: json["image"],
      manifest: json["manifest"],
      command: (json["command"] as List?)?.map((e) => e as String).toList(),
      entrypoint: (json["entrypoint"] as List?)?.map((e) => e as String).toList(),
      environment: {for (final entry in (json["env"] as Map).entries) entry.key: entry.value},
      startedBy: ParticipantInfo(id: json["started_by"]["id"], name: json["started_by"]["name"]),
    );
  }
}

class SyncClient extends ChangeEmitter {
  SyncClient({required this.room}) {
    room.protocol.addHandler("room.sync", _handleSync);
  }

  void start() {
    () async {
      await for (final message in _changesToSync.stream) {
        room.sendRequest("room.sync", {"path": message.path}, data: utf8.encode(message.base64));
      }
    }();
  }

  void dispose() {
    _changesToSync.close();
  }

  final _connectingDocuments = <String, Future<_RefCount<MeshDocument>>>{};
  final _changesToSync = StreamController<_QueuedSync>();
  final _connectedDocuments = <String, _RefCount<MeshDocument>>{};

  Future<void> _handleSync(Protocol protocol, int messageId, String type, Uint8List bytes) async {
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
      DocumentRuntime.instance.applyBackendChanges(documentId: doc.ref.id, base64: base64);

      if (!doc.ref._synchronized.isCompleted) {
        doc.ref._synchronized.complete(true);
      }
    } else {
      throw RoomServerException("received change for a document that is not connected:$path");
    }
  }

  Future<void> create(String path, [Map<String, dynamic>? json]) async {
    await room.sendRequest("room.create", {"path": path, "json": json});
  }

  Future<MeshDocument> open(String path, {bool create = true}) async {
    final pending = _connectingDocuments[path];

    if (pending != null) {
      await pending;
    }

    if (_connectedDocuments[path] != null) {
      final connectedDoc = _connectedDocuments[path];
      connectedDoc!.count++;
      return connectedDoc.ref;
    }

    // todo: add support for state vector / partial updates
    // todo: initial bytes loading

    final c = Completer<_RefCount<MeshDocument>>();
    _connectingDocuments[path] = c.future;
    try {
      final result = (await room.sendRequest("room.connect", {"path": path, "create": create})) as JsonResponse;

      MeshSchema schema = MeshSchema.fromJson(result.json["schema"]);

      final doc = MeshDocument(
        schema: schema,
        sendChangesToBackend: (base64) => _changesToSync.sink.add(_QueuedSync(path: path, base64: base64)),
      );
      final rc = _RefCount(doc);
      _connectedDocuments[path] = rc;
      notifyListeners();

      c.complete(rc);
      return doc;
    } catch (err) {
      c.completeError(err);
      rethrow;
    } finally {
      _connectingDocuments.remove(path);
    }
  }

  Future<void> close(String path) async {
    if (!_connectedDocuments.containsKey(path)) {
      throw RoomServerException("Not connected to $path");
    }

    final doc = _connectedDocuments[path];
    doc!.count--;
    if (doc.count == 0) {
      _connectedDocuments.remove(path);
      await room.sendRequest("room.disconnect", {"path": path});
      DocumentRuntime.instance.unregisterDocument(doc.ref);
    }
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

  Map<String, dynamic> toJson() {
    return {
      "name": name,
      "description": description,
      "title": title,
      "thumbnail_url": thumbnailUrl,
      "tools":
          tools
              .map(
                (tool) => {
                  "name": tool.name,
                  "title": tool.title,
                  "description": tool.description,
                  "input_schema": tool.inputSchema,
                  "thumbnail_url": tool.thumbnailUrl,
                  "defs": tool.defs,
                  "pricing": tool.pricing,
                  "supports_context": tool.supportsContext,
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
              supportsContext: tool["supports_context"] ?? false,
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
              supportsContext: tool["supports_context"] ?? false,
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
    this.supportsContext = false,
    this.thumbnailUrl,
  });

  final String? pricing;
  final String title;
  final String name;
  final String description;
  final String? thumbnailUrl;
  final Map<String, dynamic> inputSchema;
  final Map<String, dynamic>? defs;
  final bool supportsContext;
}

class StorageClient extends ChangeEmitter {
  StorageClient({required this.room}) {
    room.protocol.addHandler("storage.file.deleted", _handleFileDeleted);
    room.protocol.addHandler("storage.file.updated", _handleFileUpdated);
  }

  RoomClient room;

  Future<void> _handleFileUpdated(Protocol protocol, int messageId, String type, Uint8List bytes) async {
    final data = unpackMessage(bytes).header;
    room._eventsController.add(FileUpdatedEvent(path: data["path"], participantId: data["participant_id"]));
  }

  Future<void> _handleFileDeleted(Protocol protocol, int messageId, String type, Uint8List bytes) async {
    final data = unpackMessage(bytes).header;
    room._eventsController.add(FileDeletedEvent(path: data["path"], participantId: data["participant_id"]));
  }

  Future<List<StorageEntry>> list(String path) async {
    final response = (await room.sendRequest("storage.list", {"path": path})) as JsonResponse;
    return (response.json["files"] as List).map((f) {
        return StorageEntry(
          name: f["name"],
          isFolder: f["is_folder"],
          createdAt: f["created_at"] == null ? null : DateTime.parse(f["created_at"]),
          updatedAt: f["updated_at"] == null ? null : DateTime.parse(f["updated_at"]),
        );
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
    final rawJson = unpackMessage(bytes).header;

    room._eventsController.add(RoomLogEvent.fromJson(rawJson));
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

class MessagingClient extends ChangeEmitter {
  MessagingClient({required this.room}) {
    room.protocol.addHandler("messaging.send", _handleMessageSend);
  }

  final RoomClient room;
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

  final _participants = <String, RemoteParticipant>{};
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
  StorageEntry({required this.name, required this.isFolder, required this.createdAt, required this.updatedAt});

  final String name;
  final bool isFolder;
  final DateTime? createdAt;
  final DateTime? updatedAt;

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

/// ---------------------------------------------------------------------------
///  Generated on 2025‑08‑01
///  Service Template models – updated to align with the latest Python schema
/// ---------------------------------------------------------------------------

/// Represents the `num` field of `ServicePortSpec`, which can be `'*'` or a
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
///  ServicePortEndpointSpec
/// ---------------------------------------------------------------------------

class ServicePortEndpointSpec {
  final String path;
  final String identity;
  final String? role; // "user" | "tool" | "agent"
  final String? type; // "mcp.sse" | "meshagent.callable" | "http" | "tcp"
  final ApiScope? api;

  ServicePortEndpointSpec({required this.path, required this.identity, this.role, this.type, this.api});

  factory ServicePortEndpointSpec.fromJson(Map<String, dynamic> json) {
    return ServicePortEndpointSpec(
      path: json['path'] as String,
      identity: json['identity'] as String,
      role: json['role'] as String?,
      type: json['type'] as String?,
      api: json["api"] == null ? null : ApiScope.fromJson(json["api"]),
    );
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'identity': identity,
    if (role != null) 'role': role,
    if (type != null) 'type': type,
    if (api != null) 'api': api,
  };
}

/// ---------------------------------------------------------------------------
///  ServicePortSpec
/// ---------------------------------------------------------------------------

class ServicePortSpec {
  final PortNum num;
  final String? type; // "mcp.sse" | "meshagent.callable" | "http" | "tcp"
  final List<ServicePortEndpointSpec> endpoints;
  final String? liveness;

  ServicePortSpec({required this.num, this.type, List<ServicePortEndpointSpec>? endpoints, this.liveness})
    : endpoints = endpoints ?? const [];

  factory ServicePortSpec.fromJson(Map<String, dynamic> json) {
    return ServicePortSpec(
      num: PortNum.fromJson(json['num']),
      type: json['type'] as String?,
      endpoints:
          (json['endpoints'] as List<dynamic>? ?? []).map((e) => ServicePortEndpointSpec.fromJson(e as Map<String, dynamic>)).toList(),
      liveness: json['liveness'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'num': num.toJson(),
    if (type != null) 'type': type,
    if (endpoints.isNotEmpty) 'endpoints': endpoints.map((e) => e.toJson()).toList(),
    if (liveness != null) 'liveness': liveness,
  };
}

/// ---------------------------------------------------------------------------
///  ServiceTemplateVariable
/// ---------------------------------------------------------------------------

class ServiceTemplateVariable {
  final String name;
  final String? description;
  final bool obscure;
  final bool optional;
  final List<String>? enumValues; // mapped to `enum` in JSON

  ServiceTemplateVariable({required this.name, this.description, this.obscure = false, this.optional = false, this.enumValues});

  factory ServiceTemplateVariable.fromJson(Map<String, dynamic> json) {
    return ServiceTemplateVariable(
      name: json['name'] as String,
      description: json['description'] as String?,
      obscure: json['obscure'] ?? false,
      optional: json['optional'] ?? false,
      enumValues: (json['enum'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (description != null) 'description': description,
    'obscure': obscure,
    'optional': optional,
    if (enumValues != null) 'enum': enumValues,
  };
}

class ServiceTemplateEnvironmentVariable {
  final String name;
  final String value;

  ServiceTemplateEnvironmentVariable({required this.name, required this.value});

  factory ServiceTemplateEnvironmentVariable.fromJson(Map<String, dynamic> json) {
    return ServiceTemplateEnvironmentVariable(name: json['name'] as String, value: json['value'] as String);
  }

  Map<String, dynamic> toJson() => {'name': name, 'value': value};
}

/// ---------------------------------------------------------------------------
///  Storage Mount Specs
/// ---------------------------------------------------------------------------

/// Represents a single room storage mount.
class RoomStorageMountSpec {
  final String path;
  final String? subpath;

  RoomStorageMountSpec({required this.path, this.subpath});

  factory RoomStorageMountSpec.fromJson(Map<String, dynamic> json) {
    return RoomStorageMountSpec(path: json['path'] as String, subpath: json['subpath'] as String?);
  }

  Map<String, dynamic> toJson() => {'path': path, if (subpath != null) 'subpath': subpath};
}

/// Wrapper for all storage mounts on a template (currently only `room`).
class ServiceTemplateMountSpec {
  final List<RoomStorageMountSpec>? room;

  ServiceTemplateMountSpec({this.room});

  factory ServiceTemplateMountSpec.fromJson(Map<String, dynamic> json) {
    return ServiceTemplateMountSpec(
      room: (json['room'] as List<dynamic>?)?.map((e) => RoomStorageMountSpec.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toJson() => {if (room != null) 'room': room!.map((e) => e.toJson()).toList()};
}

/// ---------------------------------------------------------------------------
///  ServiceTemplateSpec
/// ---------------------------------------------------------------------------

class ServiceTemplateMetadata {
  ServiceTemplateMetadata({required this.name, this.description, this.icon, this.repo});

  final String name;
  final String? description;
  final String? icon;
  final String? repo;

  Map<String, dynamic> toJson() => {'name': name, 'description': description, 'icon': icon, 'repo': repo};

  static ServiceTemplateMetadata fromJson(Map<String, dynamic> json) {
    return ServiceTemplateMetadata(name: json["name"], description: json["description"], icon: json["icon"], repo: json["repo"]);
  }
}

class ServiceTemplateSpec {
  final String version; // default "v1"
  final String kind; // default "ServiceTemplate"
  final List<ServiceTemplateVariable>? variables;
  final List<ServiceTemplateEnvironmentVariable>? environment;
  final ServiceTemplateMetadata metadata;
  final String? image;

  final List<ServicePortSpec> ports;
  final String? command;
  final String? role; // "user" | "tool" | "agent"
  final ServiceTemplateMountSpec? storage;

  ServiceTemplateSpec({
    this.version = 'v1',
    this.kind = 'ServiceTemplate',
    this.variables,
    this.environment,
    required this.metadata,
    this.image,
    List<ServicePortSpec>? ports,
    this.command,
    this.role,
    this.storage,
  }) : ports = ports ?? const [];

  factory ServiceTemplateSpec.fromJson(Map<String, dynamic> json) {
    return ServiceTemplateSpec(
      version: json['version'] as String? ?? 'v1',
      kind: json['kind'] as String? ?? 'ServiceTemplate',
      variables: (json['variables'] as List<dynamic>?)?.map((e) => ServiceTemplateVariable.fromJson(e as Map<String, dynamic>)).toList(),
      environment:
          (json['environment'] as List<dynamic>?)
              ?.map((e) => ServiceTemplateEnvironmentVariable.fromJson(e as Map<String, dynamic>))
              .toList(),
      metadata: ServiceTemplateMetadata.fromJson(json['metadata']),
      image: json['image'] as String?,
      ports: (json['ports'] as List<dynamic>? ?? []).map((e) => ServicePortSpec.fromJson(e as Map<String, dynamic>)).toList(),
      command: json['command'] as String?,
      role: json['role'] as String?,
      storage: json['storage'] == null ? null : ServiceTemplateMountSpec.fromJson(json['storage'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'kind': kind,
    if (variables != null) 'variables': variables!.map((e) => e.toJson()).toList(),
    if (environment != null) 'environment': environment!.map((e) => e.toJson()).toList(),
    if (image != null) 'image': image,
    "metadata": metadata.toJson(),
    if (ports.isNotEmpty) 'ports': ports.map((e) => e.toJson()).toList(),
    if (command != null) 'command': command,
    if (role != null) 'role': role,
    if (storage != null) 'storage': storage!.toJson(),
  };
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
  final String clientId;
  final String requestId;
  final String authorizationEndpoint;
  final String tokenEndpoint;
  final List<String>? scopes;
}

/// Optional: if you want a typedef for clarity
typedef OAuthTokenRequestHandler = void Function(OAuthTokenRequest request);

class SecretsClient extends ChangeEmitter {
  SecretsClient({required this.room, this.oauthTokenRequestHandler}) {
    // Server -> client: another participant (or the server) requests us to obtain an OAuth token.
    room.protocol.addHandler("secrets.request_oauth_token", _handleClientOAuthTokenRequest);
  }

  final RoomClient room;

  final OAuthTokenRequestHandler? oauthTokenRequestHandler;

  // Server sent us a request asking the local user/client to authorize and supply a token.
  Future<void> _handleClientOAuthTokenRequest(Protocol protocol, int messageId, String type, Uint8List bytes) async {
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
    final req = header["request"] as Map<String, dynamic>;
    final String clientId = req["client_id"] as String;

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
    () async {
      try {
        oauthTokenRequestHandler!(authReq);
      } catch (e, st) {
        Logger.root.warning("OAuth token request handler threw", e, st);
      }
    }();
  }

  /// Client -> server: Provide the OAuth token in response to a prior inbound request.
  Future<void> provideOAuthAuthorization({required String requestId, required String code}) async {
    final payload = {"request_id": requestId, "code": code};
    await room.sendRequest("secrets.provide_oauth_authorization", payload);
  }

  /// Client -> server: reject an OAuth token request in response to a prior inbound request.
  Future<void> rejectOAuthAuthorization({required String requestId, required String error}) async {
    final payload = {"request_id": requestId, "error": error};
    await room.sendRequest("secrets.provide_oauth_authorization", payload);
  }

  /// Client -> server: Ask another participant (or the server) to obtain an OAuth token for us.
  /// Returns the `access_token` string.
  ///
  /// This matches the Python signature:
  ///   request_oauth_token(authorization_endpoint, token_endpoint, scopes, timeout, from_participant_id)
  Future<String> requestOAuthToken({
    required String authorizationEndpoint,
    required String tokenEndpoint,
    required String fromParticipantId,
    required String clientId,
    required String clientSecret,
    required Uri redirectUri,
    List<String>? scopes,
    int timeout = 60 * 5,
  }) async {
    final req = {
      "authorization_endpoint": authorizationEndpoint,
      "token_endpoint": tokenEndpoint,
      "scopes": scopes,
      "timeout": timeout,
      "participant_id": fromParticipantId,
      "client_id": clientId,
      "client_secret": clientSecret,
      "redirect_uri": redirectUri.toString(),
    };

    final res = await room.sendRequest("secrets.request_oauth_token", req) as JsonResponse;
    final accessToken = (res.json["access_token"] as String?) ?? "";
    if (accessToken.isEmpty) {
      throw RoomServerException("Invalid response: missing access_token");
    }
    return accessToken;
  }
}
