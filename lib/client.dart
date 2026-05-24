import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:meshagent/meshagent.dart';

abstract class AccessTokenProvider {
  Future<String> getToken();
}

class SimpleAccessTokenProvider implements AccessTokenProvider {
  SimpleAccessTokenProvider(this.token);

  final String token;

  @override
  Future<String> getToken() async => token;
}

class _TokenProviderClient extends http.BaseClient {
  _TokenProviderClient(this._inner, this.tokenProvider);

  final http.Client _inner;
  final AccessTokenProvider tokenProvider;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final token = await tokenProvider.getToken();

    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Accept'] = 'application/json';

    if (!request.headers.containsKey('Content-Type')) {
      request.headers['Content-Type'] = 'application/json';
    }

    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
  }
}

Map<String, dynamic> _createServiceSpecJson(ServiceSpec service) {
  final payload = service.toJson();
  payload.remove('id');
  return payload;
}

Object? _jsonWithoutNulls(Object? value) {
  if (value == null) {
    return null;
  }

  if (value is Map) {
    final output = <String, dynamic>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        continue;
      }
      final normalized = _jsonWithoutNulls(entry.value);
      if (normalized != null) {
        output[key] = normalized;
      }
    }
    return output;
  }

  if (value is Iterable) {
    return value.map(_jsonWithoutNulls).where((item) => item != null).toList();
  }

  return value;
}

Map<String, dynamic> _jsonMapWithoutNulls(Map<String, dynamic> value) {
  return (_jsonWithoutNulls(value) as Map).cast<String, dynamic>();
}

enum ProjectRole { member, developer, admin, none }

class ProjectRoleInfo {
  ProjectRoleInfo({
    required this.role,
    required this.canCreateRooms,
    required this.canCreateAgents,
    required this.canUseLlmProxy,
    required this.isAdmin,
    required this.isDeveloper,
  });

  final ProjectRole role;
  final bool canCreateRooms;
  final bool canCreateAgents;
  final bool canUseLlmProxy;
  final bool isAdmin;
  final bool isDeveloper;

  factory ProjectRoleInfo.fromJson(Map<String, dynamic> json) {
    final role = switch (json['role']) {
      'admin' => ProjectRole.admin,
      'developer' => ProjectRole.developer,
      'member' => ProjectRole.member,
      _ => ProjectRole.none,
    };

    return ProjectRoleInfo(
      role: role,
      canCreateRooms: json['can_create_rooms'] == true,
      canCreateAgents: json['can_create_agents'] == true,
      canUseLlmProxy: json['can_use_llm_proxy'] == true,
      isAdmin: json['is_admin'] == true,
      isDeveloper: json['is_developer'] == true,
    );
  }
}

class AuthProvider {
  AuthProvider({required this.id, required this.svgLogo, required this.alt, required this.label});

  final String id;
  final String svgLogo;
  final String alt;
  final String label;

  factory AuthProvider.fromJson(Map<String, dynamic> json) => AuthProvider(
    id: json['id'] as String,
    svgLogo: json['svgLogo'] as String,
    alt: json['alt'] as String,
    label: json['label'] as String,
  );
}

class RoomConnectionInfo {
  RoomConnectionInfo({required this.jwt, required this.roomName, required this.projectId, required this.roomUrl});
  String jwt;
  String roomName;
  String projectId;
  Uri roomUrl;

  static RoomConnectionInfo fromJson(Map<String, dynamic> json) {
    return RoomConnectionInfo(
      jwt: json["jwt"],
      roomName: json["room_name"],
      projectId: json["project_id"],
      roomUrl: Uri.parse(json["room_url"]),
    );
  }
}

class AgentConnectionInfo {
  AgentConnectionInfo({required this.jwt, required this.agentName, required this.projectId, required this.agentUrl});
  String jwt;
  String agentName;
  String projectId;
  Uri agentUrl;

  static AgentConnectionInfo fromJson(Map<String, dynamic> json) {
    return AgentConnectionInfo(
      jwt: json["jwt"],
      agentName: json["agent_name"],
      projectId: json["project_id"],
      agentUrl: Uri.parse(json["agent_url"]),
    );
  }
}

class RoomSession {
  final String id;
  final String? roomId;
  final String roomName;
  final DateTime createdAt;
  final bool isActive;
  final Map<String, num>? participants;
  final String kind;
  final String? agentId;
  final String? agentName;

  RoomSession({
    required this.id,
    required this.roomId,
    required this.roomName,
    required this.createdAt,
    required this.isActive,
    required this.participants,
    this.kind = 'room',
    this.agentId,
    this.agentName,
  });

  factory RoomSession.fromJson(Map<String, dynamic> json) => RoomSession(
    id: json["id"],
    roomId: json['room_id'] as String?,
    roomName: json['room_name'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    isActive: json['is_active'] as bool? ?? false,
    participants: json["participants"] == null ? null : {for (final k in (json["participants"] as Map).keys) k: json["participants"][k]},
    kind: json['kind'] as String? ?? 'room',
    agentId: json['agent_id'] as String?,
    agentName: json['agent_name'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'room_id': roomId,
    'room_name': roomName,
    'started_at': createdAt.toIso8601String(),
    'is_active': isActive,
    'kind': kind,
    if (agentId != null) 'agent_id': agentId,
    if (agentName != null) 'agent_name': agentName,
  };
}

class Balance {
  Balance({
    required this.balance,
    required this.autoRechargeAmount,
    required this.autoRechargeThreshhold,
    required this.lastRecharge,
    required this.monthlyBudget,
    required this.autoRechargePaused,
    required this.autoRechargedThisMonth,
  });

  final double balance;
  final double? autoRechargeThreshhold;
  final double? autoRechargeAmount;
  final DateTime? lastRecharge;
  final double? monthlyBudget;
  final bool autoRechargePaused;
  final double? autoRechargedThisMonth;
}

class Transaction {
  Transaction({
    required this.id,
    required this.amount,
    required this.reference,
    required this.referenceType,
    required this.description,
    required this.createdAt,
  });

  final String id;
  final double amount;
  final String? reference;
  final String? referenceType;
  final String description;
  final DateTime createdAt;
}

class Mailbox {
  final String address;
  final String room;
  final String? roomId;
  final String queue;
  final bool public;
  final Map<String, String> annotations;

  Mailbox({required this.address, required this.room, this.roomId, required this.queue, required this.public, required this.annotations});

  factory Mailbox.fromJson(Map<String, dynamic> json) => Mailbox(
    address: json['address'] as String,
    room: json['room'] as String,
    roomId: json['room_id'] as String?,
    queue: json['queue'] as String,
    public: json['public'],
    annotations: (json['annotations'] as Map?)?.map((key, value) => MapEntry(key as String, value as String)) ?? {},
  );

  Map<String, dynamic> toJson() => {
    'address': address,
    'room': room,
    if (roomId != null) 'room_id': roomId,
    'queue': queue,
    'public': public,
    'annotations': annotations,
  };
}

class MailboxesPage {
  final List<Mailbox> mailboxes;
  final int total;

  MailboxesPage({required this.mailboxes, required this.total});

  factory MailboxesPage.fromJson(Map<String, dynamic> json) {
    final list = json['mailboxes'] as List<dynamic>? ?? [];
    return MailboxesPage(mailboxes: list.whereType<Map<String, dynamic>>().map(Mailbox.fromJson).toList(), total: _parseInt(json['total']));
  }
}

class Route {
  final String domain;
  final RouteSpec spec;

  Route({required this.domain, required this.spec});

  factory Route.fromJson(Map<String, dynamic> json) {
    final specJson = (json['spec'] as Map?)?.cast<String, dynamic>() ?? json;
    final spec = RouteSpec.fromJson(specJson);
    return Route(domain: json['domain'] as String? ?? spec.domain, spec: spec);
  }

  String get roomName => spec.backend.room?.name ?? '';
  String get agentName => spec.backend.agent?.name ?? '';
  String get port => spec.paths.isEmpty ? '' : spec.paths.first.targetPort.toString();
  Map<String, String> get annotations => spec.metadata.annotations;

  Map<String, dynamic> toJson() => {'domain': domain, 'spec': spec.toJson()};
}

class RouteMetadata {
  final String name;
  final Map<String, String> annotations;

  RouteMetadata({required this.name, this.annotations = const {}});

  factory RouteMetadata.fromJson(Map<String, dynamic> json) =>
      RouteMetadata(name: json['name'] as String, annotations: ((json['annotations'] as Map?) ?? {}).cast<String, String>());

  Map<String, dynamic> toJson() => {'name': name, 'annotations': annotations};
}

class RouteBackendTarget {
  final String name;

  RouteBackendTarget({required this.name});

  factory RouteBackendTarget.fromJson(Map<String, dynamic> json) => RouteBackendTarget(name: json['name'] as String);

  Map<String, dynamic> toJson() => {'name': name};
}

class RouteBackend {
  final RouteBackendTarget? room;
  final RouteBackendTarget? agent;

  RouteBackend({this.room, this.agent});

  factory RouteBackend.fromJson(Map<String, dynamic> json) => RouteBackend(
    room: json['room'] is Map ? RouteBackendTarget.fromJson((json['room'] as Map).cast<String, dynamic>()) : null,
    agent: json['agent'] is Map ? RouteBackendTarget.fromJson((json['agent'] as Map).cast<String, dynamic>()) : null,
  );

  Map<String, dynamic> toJson() => {if (room != null) 'room': room!.toJson(), if (agent != null) 'agent': agent!.toJson()};
}

class RoutePath {
  final String path;
  final String pathType;
  final bool stripPrefix;
  final Object targetPort;

  RoutePath({this.path = '/', this.pathType = 'prefix', this.stripPrefix = false, required this.targetPort});

  factory RoutePath.fromJson(Map<String, dynamic> json) => RoutePath(
    path: json['path'] as String? ?? '/',
    pathType: json['pathType'] as String? ?? 'prefix',
    stripPrefix: json['stripPrefix'] as bool? ?? false,
    targetPort: json['targetPort'] as Object,
  );

  Map<String, dynamic> toJson() => {'path': path, 'pathType': pathType, 'stripPrefix': stripPrefix, 'targetPort': targetPort};
}

class RouteSpec {
  final String version;
  final String kind;
  final RouteMetadata metadata;
  final String domain;
  final RouteBackend backend;
  final List<RoutePath> paths;

  RouteSpec({
    this.version = 'v1',
    this.kind = 'Route',
    required this.metadata,
    required this.domain,
    required this.backend,
    this.paths = const [],
  });

  factory RouteSpec.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('backend') && json.containsKey('room_name')) {
      return RouteSpec(
        metadata: RouteMetadata(name: json['domain'] as String, annotations: ((json['annotations'] as Map?) ?? {}).cast<String, String>()),
        domain: json['domain'] as String,
        backend: RouteBackend(room: RouteBackendTarget(name: json['room_name'] as String)),
        paths: [RoutePath(targetPort: json['port'] as Object)],
      );
    }
    final pathList = json['paths'] as List<dynamic>? ?? [];
    return RouteSpec(
      version: json['version'] as String? ?? 'v1',
      kind: json['kind'] as String? ?? 'Route',
      metadata: RouteMetadata.fromJson((json['metadata'] as Map).cast<String, dynamic>()),
      domain: json['domain'] as String,
      backend: RouteBackend.fromJson((json['backend'] as Map).cast<String, dynamic>()),
      paths: pathList.whereType<Map>().map((item) => RoutePath.fromJson(item.cast<String, dynamic>())).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'kind': kind,
    'metadata': metadata.toJson(),
    'domain': domain,
    'backend': backend.toJson(),
    'paths': paths.map((path) => path.toJson()).toList(),
  };
}

class RoutesPage {
  final List<Route> routes;
  final int total;

  RoutesPage({required this.routes, required this.total});

  factory RoutesPage.fromJson(Map<String, dynamic> json) {
    final list = json['routes'] as List<dynamic>? ?? [];
    return RoutesPage(routes: list.whereType<Map<String, dynamic>>().map(Route.fromJson).toList(), total: _parseInt(json['total']));
  }
}

class Feed {
  final String id;
  final String projectId;
  final DateTime createdAt;
  final String name;
  final String description;
  final String visibility;
  final bool paused;
  final Map<String, String> annotations;
  final Object? messageSchema;

  Feed({
    required this.id,
    required this.projectId,
    required this.createdAt,
    required this.name,
    required this.description,
    required this.visibility,
    required this.paused,
    required this.annotations,
    required this.messageSchema,
  });

  factory Feed.fromJson(Map<String, dynamic> json) => Feed(
    id: json['id'] as String,
    projectId: json['project_id'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    visibility: json['visibility'] as String? ?? 'private',
    paused: json['paused'] as bool? ?? false,
    annotations: ((json['annotations'] as Map?) ?? {}).cast<String, String>(),
    messageSchema: json['message_schema'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'project_id': projectId,
    'created_at': createdAt.toIso8601String(),
    'name': name,
    'description': description,
    'visibility': visibility,
    'paused': paused,
    'annotations': annotations,
    'message_schema': messageSchema,
  };
}

class FeedsPage {
  final List<Feed> feeds;
  final int total;

  FeedsPage({required this.feeds, required this.total});

  factory FeedsPage.fromJson(Map<String, dynamic> json) {
    final list = json['feeds'] as List<dynamic>? ?? [];
    return FeedsPage(feeds: list.whereType<Map<String, dynamic>>().map(Feed.fromJson).toList(), total: _parseInt(json['total']));
  }
}

class FeedSubscription {
  final String id;
  final String feedId;
  final String projectId;
  final String room;
  final String? roomId;
  final String path;
  final String? filenameDatetimeFormat;
  final DateTime createdAt;
  final Map<String, String> annotations;

  FeedSubscription({
    required this.id,
    required this.feedId,
    required this.projectId,
    required this.room,
    required this.roomId,
    required this.path,
    required this.filenameDatetimeFormat,
    required this.createdAt,
    required this.annotations,
  });

  factory FeedSubscription.fromJson(Map<String, dynamic> json) => FeedSubscription(
    id: json['id'] as String,
    feedId: json['feed_id'] as String,
    projectId: json['project_id'] as String,
    room: json['room'] as String,
    roomId: json['room_id'] as String?,
    path: json['path'] as String,
    filenameDatetimeFormat: json['filename_datetime_format'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
    annotations: ((json['annotations'] as Map?) ?? {}).cast<String, String>(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'feed_id': feedId,
    'project_id': projectId,
    'room': room,
    if (roomId != null) 'room_id': roomId,
    'path': path,
    if (filenameDatetimeFormat != null) 'filename_datetime_format': filenameDatetimeFormat,
    'created_at': createdAt.toIso8601String(),
    'annotations': annotations,
  };
}

class LlmLogger {
  final String id;
  final String projectId;
  final String destinationFeedId;
  final String filterExpression;
  final bool paused;
  final DateTime createdAt;
  final Map<String, String> annotations;

  LlmLogger({
    required this.id,
    required this.projectId,
    required this.destinationFeedId,
    required this.filterExpression,
    required this.paused,
    required this.createdAt,
    required this.annotations,
  });

  factory LlmLogger.fromJson(Map<String, dynamic> json) => LlmLogger(
    id: json['id'] as String,
    projectId: json['project_id'] as String,
    destinationFeedId: json['destination_feed_id'] as String,
    filterExpression: json['filter_expression'] as String,
    paused: json['paused'] as bool? ?? false,
    createdAt: DateTime.parse(json['created_at'] as String),
    annotations: ((json['annotations'] as Map?) ?? {}).cast<String, String>(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'project_id': projectId,
    'destination_feed_id': destinationFeedId,
    'filter_expression': filterExpression,
    'paused': paused,
    'created_at': createdAt.toIso8601String(),
    'annotations': annotations,
  };
}

class ProjectRepository {
  final String id;
  final String projectId;
  final String name;
  final String description;
  final Map<String, String> annotations;
  final DateTime createdAt;

  ProjectRepository({
    required this.id,
    required this.projectId,
    required this.name,
    required this.description,
    required this.annotations,
    required this.createdAt,
  });

  factory ProjectRepository.fromJson(Map<String, dynamic> json) => ProjectRepository(
    id: json['id'] as String,
    projectId: json['project_id'] as String,
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    annotations: ((json['annotations'] as Map?) ?? {}).cast<String, String>(),
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'project_id': projectId,
    'name': name,
    'description': description,
    'annotations': annotations,
    'created_at': createdAt.toIso8601String(),
  };
}

class ProjectRepositoryTag {
  final String tag;
  final String? digest;
  final String? mediaType;
  final int? manifestSize;

  ProjectRepositoryTag({required this.tag, this.digest, this.mediaType, this.manifestSize});

  factory ProjectRepositoryTag.fromJson(Map<String, dynamic> json) => ProjectRepositoryTag(
    tag: json['tag'] as String,
    digest: json['digest'] as String?,
    mediaType: json['media_type'] as String?,
    manifestSize: json['manifest_size'] as int?,
  );

  Map<String, dynamic> toJson() => {
    'tag': tag,
    if (digest != null) 'digest': digest,
    if (mediaType != null) 'media_type': mediaType,
    if (manifestSize != null) 'manifest_size': manifestSize,
  };
}

class ProjectRepositoryImage {
  final String digest;
  final List<String> tags;
  final String? mediaType;
  final int? manifestSize;
  final int? imageSize;
  final DateTime? updatedAt;

  ProjectRepositoryImage({required this.digest, required this.tags, this.mediaType, this.manifestSize, this.imageSize, this.updatedAt});

  factory ProjectRepositoryImage.fromJson(Map<String, dynamic> json) => ProjectRepositoryImage(
    digest: json['digest'] as String,
    tags: (json['tags'] as List<dynamic>? ?? const []).whereType<String>().toList(),
    mediaType: json['media_type'] as String?,
    manifestSize: json['manifest_size'] as int?,
    imageSize: json['image_size'] as int?,
    updatedAt: json['updated_at'] is String ? DateTime.tryParse(json['updated_at'] as String) : null,
  );

  Map<String, dynamic> toJson() => {
    'digest': digest,
    'tags': tags,
    if (mediaType != null) 'media_type': mediaType,
    if (manifestSize != null) 'manifest_size': manifestSize,
    if (imageSize != null) 'image_size': imageSize,
    if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
  };
}

class ManagedSecretInfo {
  final String id;
  final String type;
  final String name;
  final String? delegatedTo;
  final String? agentId;

  ManagedSecretInfo({required this.id, required this.type, required this.name, this.delegatedTo, this.agentId});

  factory ManagedSecretInfo.fromJson(Map<String, dynamic> json) => ManagedSecretInfo(
    id: json['id'] as String,
    type: json['type'] as String,
    name: json['name'] as String,
    delegatedTo: json['delegated_to'] as String? ?? json['delegatedTo'] as String?,
    agentId: json['agent_id'] as String? ?? json['agentId'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'name': name,
    if (delegatedTo != null) 'delegated_to': delegatedTo,
    if (agentId != null) 'agent_id': agentId,
  };
}

class ManagedSecret extends ManagedSecretInfo {
  final String dataBase64;

  ManagedSecret({required super.id, required super.type, required super.name, super.delegatedTo, super.agentId, required this.dataBase64});

  Uint8List get data => base64Decode(dataBase64);

  factory ManagedSecret.fromJson(Map<String, dynamic> json) => ManagedSecret(
    id: json['id'] as String,
    type: json['type'] as String,
    name: json['name'] as String,
    delegatedTo: json['delegated_to'] as String? ?? json['delegatedTo'] as String?,
    agentId: json['agent_id'] as String? ?? json['agentId'] as String?,
    dataBase64: json['data_base64'] as String? ?? json['dataBase64'] as String,
  );

  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'data_base64': dataBase64};
}

class MeshagentRepositoriesPage {
  final List<ProjectRepository> repositories;
  final int total;

  MeshagentRepositoriesPage({required this.repositories, required this.total});

  factory MeshagentRepositoriesPage.fromJson(Map<String, dynamic> json) {
    final list = json['repositories'] as List<dynamic>? ?? [];
    return MeshagentRepositoriesPage(
      repositories: list.whereType<Map>().map((m) => ProjectRepository.fromJson(m.cast<String, dynamic>())).toList(),
      total: _parseInt(json['total']),
    );
  }
}

class MeshagentSecretsPage {
  final List<ManagedSecretInfo> secrets;
  final int total;

  MeshagentSecretsPage({required this.secrets, required this.total});

  factory MeshagentSecretsPage.fromJson(Map<String, dynamic> json) {
    final list = json['secrets'] as List<dynamic>? ?? [];
    return MeshagentSecretsPage(
      secrets: list.whereType<Map>().map((m) => ManagedSecretInfo.fromJson(m.cast<String, dynamic>())).toList(),
      total: _parseInt(json['total']),
    );
  }
}

class MeshagentLegacySecretsPage {
  final List<Map<String, dynamic>> secrets;
  final int total;

  MeshagentLegacySecretsPage({required this.secrets, required this.total});
}

class MeshagentServicesPage {
  final List<ServiceSpec> services;
  final int total;

  MeshagentServicesPage({required this.services, required this.total});

  factory MeshagentServicesPage.fromJson(Map<String, dynamic> json) {
    final list = json['services'] as List<dynamic>? ?? [];
    return MeshagentServicesPage(
      services: list.whereType<Map>().map((m) => ServiceSpec.fromJson(m.cast<String, dynamic>())).toList(),
      total: _parseInt(json['total']),
    );
  }
}

class MeshagentApiKeysPage {
  final List<Map<String, dynamic>> keys;
  final int total;

  MeshagentApiKeysPage({required this.keys, required this.total});

  factory MeshagentApiKeysPage.fromJson(Map<String, dynamic> json) {
    final list = json['keys'] as List<dynamic>? ?? [];
    return MeshagentApiKeysPage(
      keys: list.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList(),
      total: _parseInt(json['total']),
    );
  }
}

class MeshagentWebhooksPage {
  final List<Map<String, dynamic>> webhooks;
  final int total;

  MeshagentWebhooksPage({required this.webhooks, required this.total});

  factory MeshagentWebhooksPage.fromJson(Map<String, dynamic> json) {
    final list = json['webhooks'] as List<dynamic>? ?? [];
    return MeshagentWebhooksPage(
      webhooks: list.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList(),
      total: _parseInt(json['total']),
    );
  }
}

class ExternalOAuthClientRegistration {
  final String id;
  final String delegatedTo;
  final ConnectorRef? connector;
  final OAuthClientConfig? oauth;
  final String clientId;
  final String? clientSecret;

  ExternalOAuthClientRegistration({
    required this.id,
    required this.delegatedTo,
    this.connector,
    this.oauth,
    required this.clientId,
    this.clientSecret,
  });

  factory ExternalOAuthClientRegistration.fromJson(Map<String, dynamic> json) => ExternalOAuthClientRegistration(
    id: json['id'] as String,
    delegatedTo: json['delegated_to'] as String? ?? json['delegatedTo'] as String,
    connector: json['connector'] == null ? null : ConnectorRef.fromJson((json['connector'] as Map).cast<String, dynamic>()),
    oauth: json['oauth'] == null ? null : OAuthClientConfig.fromJson((json['oauth'] as Map).cast<String, dynamic>()),
    clientId: json['client_id'] as String? ?? json['clientId'] as String,
    clientSecret: json['client_secret'] as String? ?? json['clientSecret'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'delegated_to': delegatedTo,
    if (connector != null) 'connector': connector!.toJson(),
    if (oauth != null) 'oauth': oauth!.toJson(),
    'client_id': clientId,
    if (clientSecret != null) 'client_secret': clientSecret,
  };
}

Uint8List _normalizeSecretBytes(List<int> data) {
  if (data is Uint8List) {
    return data;
  }
  return Uint8List.fromList(data);
}

Map<String, dynamic> _parseLegacySecretPayload({required ManagedSecretInfo secret, required Uint8List rawData}) {
  dynamic payload;
  try {
    payload = jsonDecode(utf8.decode(rawData));
  } catch (_) {
    throw MeshagentException('Invalid secret payload for ${secret.id}');
  }

  if (payload is! Map<String, dynamic>) {
    throw MeshagentException('Invalid secret payload for ${secret.id}');
  }

  return {'id': secret.id, 'name': secret.name, 'type': secret.type, 'data': payload};
}

// ---------------------------
// Scheduled Tasks models
// ---------------------------

class ScheduledTask {
  ScheduledTask({
    required this.id,
    required this.projectId,
    required this.roomId,
    required this.roomName,
    required this.spec,
    this.queueName,
    Map<String, dynamic>? payload,
    this.container,
    required this.schedule,
    required this.active,
    required this.once,
    required this.annotations,
    this.storageWritePath,
    this.lastRunId,
    this.lastStartTime,
    this.lastEndTime,
    this.lastStatus,
    this.lastReturnMessage,
  }) : payload = payload ?? const <String, dynamic>{};

  final String id;
  final String projectId;
  final String roomId;
  final String roomName;
  final ScheduledTaskSpec spec;
  final String? queueName;
  final ContainerSpec? container;

  /// Server-side payload is commonly a JSON-string or opaque string.
  /// Keep it as dynamic if you want to allow either Map or String.
  final Map<String, dynamic> payload;

  final String schedule;
  final bool active;
  final bool once;
  final String? storageWritePath;

  final int? lastRunId;
  final DateTime? lastStartTime;
  final DateTime? lastEndTime;
  final String? lastStatus;
  final String? lastReturnMessage;
  final Map<String, String> annotations;

  factory ScheduledTask.fromJson(Map<String, dynamic> json) => ScheduledTask(
    id: json['id'] as String,
    projectId: json['project_id'] as String,
    roomId: json['room_id'] as String,
    roomName: json['room_name'] as String,
    spec: ScheduledTaskSpec.fromJson((json['spec'] as Map).cast<String, dynamic>()),
    queueName: json['queue_name'] as String?,
    payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{},
    container: json['container'] == null ? null : ContainerSpec.fromJson((json['container'] as Map).cast<String, dynamic>()),
    schedule: json['schedule'] as String,
    active: (json['active'] as bool?) ?? true,
    once: (json['once'] as bool?) ?? false,
    annotations: (json['annotations'] as Map).cast<String, String>(),
    storageWritePath: json['storage_write_path'] as String?,
    lastRunId: (json['last_run_id'] as num?)?.toInt(),
    lastStartTime: json['last_start_time'] == null ? null : DateTime.parse(json['last_start_time'] as String),
    lastEndTime: json['last_end_time'] == null ? null : DateTime.parse(json['last_end_time'] as String),
    lastStatus: json['last_status'] as String?,
    lastReturnMessage: json['last_return_message'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'project_id': projectId,
    'room_name': roomName,
    'spec': spec.toJson(),
    'room_id': roomId,
    if (queueName != null) 'queue_name': queueName,
    'payload': payload,
    if (container != null) 'container': container!.toJson(),
    'schedule': schedule,
    'active': active,
    'once': once,
    'annotations': annotations,
    if (storageWritePath != null) 'storage_write_path': storageWritePath,
    if (lastRunId != null) 'last_run_id': lastRunId,
    if (lastStartTime != null) 'last_start_time': lastStartTime!.toIso8601String(),
    if (lastEndTime != null) 'last_end_time': lastEndTime!.toIso8601String(),
    if (lastStatus != null) 'last_status': lastStatus,
    if (lastReturnMessage != null) 'last_return_message': lastReturnMessage,
  };
}

class ScheduledTasksPage {
  final List<ScheduledTask> tasks;
  final int total;

  ScheduledTasksPage({required this.tasks, required this.total});

  factory ScheduledTasksPage.fromJson(Map<String, dynamic> json) {
    final list = json['tasks'] as List<dynamic>? ?? [];
    return ScheduledTasksPage(
      tasks: list.whereType<Map>().map((m) => ScheduledTask.fromJson(m.cast<String, dynamic>())).toList(),
      total: _parseInt(json['total']),
    );
  }
}

class _CreateScheduledTaskRequest {
  _CreateScheduledTaskRequest({required this.spec});

  final ScheduledTaskSpec spec;

  Map<String, dynamic> toJson() => {'spec': spec.toJson()};
}

class _UpdateScheduledTaskRequest {
  _UpdateScheduledTaskRequest({required this.spec});

  final ScheduledTaskSpec spec;

  Map<String, dynamic> toJson() => {'spec': spec.toJson()};
}

class ScheduledTaskRun {
  ScheduledTaskRun({
    required this.id,
    required this.taskId,
    required this.projectId,
    required this.roomId,
    required this.roomName,
    this.queuedMessageId,
    required this.target,
    required this.status,
    this.error,
    this.containerId,
    required this.scheduledTime,
    this.timeoutAt,
    this.startedAt,
    this.leaseExpiresAt,
    this.attemptCount = 0,
    this.completedAt,
  });

  final String id;
  final String taskId;
  final String projectId;
  final String roomId;
  final String roomName;
  final String? queuedMessageId;
  final String target;
  final String status;
  final int attemptCount;
  final String? error;
  final String? containerId;
  final DateTime scheduledTime;
  final DateTime? timeoutAt;
  final DateTime? startedAt;
  final DateTime? leaseExpiresAt;
  final DateTime? completedAt;

  factory ScheduledTaskRun.fromJson(Map<String, dynamic> json) => ScheduledTaskRun(
    id: json['id'] as String,
    taskId: json['task_id'] as String,
    projectId: json['project_id'] as String,
    roomId: json['room_id'] as String,
    roomName: json['room_name'] as String,
    queuedMessageId: json['queued_message_id'] as String?,
    target: json['target'] as String,
    status: json['status'] as String,
    attemptCount: _parseInt(json['attempt_count']),
    error: json['error'] as String?,
    containerId: json['container_id'] as String?,
    scheduledTime: DateTime.parse(json['scheduled_time'] as String),
    timeoutAt: json['timeout_at'] == null ? null : DateTime.parse(json['timeout_at'] as String),
    startedAt: json['started_at'] == null ? null : DateTime.parse(json['started_at'] as String),
    leaseExpiresAt: json['lease_expires_at'] == null ? null : DateTime.parse(json['lease_expires_at'] as String),
    completedAt: json['completed_at'] == null ? null : DateTime.parse(json['completed_at'] as String),
  );
}

class ScheduledTaskRunsPage {
  final List<ScheduledTaskRun> runs;
  final int total;

  ScheduledTaskRunsPage({required this.runs, required this.total});

  factory ScheduledTaskRunsPage.fromJson(Map<String, dynamic> json) {
    final list = json['runs'] as List<dynamic>? ?? [];
    return ScheduledTaskRunsPage(
      runs: list.whereType<Map>().map((m) => ScheduledTaskRun.fromJson(m.cast<String, dynamic>())).toList(),
      total: _parseInt(json['total']),
    );
  }
}

/// A client to interact with the accounts routes.
class Meshagent {
  /// Creates an instance of [Meshagent].
  ///
  /// [baseUrl] is the root URL of your server, e.g. 'http://localhost:8080'.
  /// [token] is your Bearer token for authorization.
  Meshagent({required this.baseUrl, required this.token, AccessTokenProvider? tokenProvider, http.Client? client})
    : httpClient = client ?? _TokenProviderClient(http.Client(), tokenProvider ?? SimpleAccessTokenProvider(token));

  factory Meshagent.withTokenProvider({
    required String baseUrl,
    required String token,
    required AccessTokenProvider tokenProvider,
    http.Client? client,
  }) {
    return Meshagent(baseUrl: baseUrl, token: token, tokenProvider: tokenProvider, client: client);
  }

  final String baseUrl;
  final String token;
  final http.Client httpClient;

  /// POST /accounts/projects/{project_id}/mailboxes
  /// Body: { "address", "room", "queue" }
  /// Returns {} on success.
  Future<void> createMailbox({
    required String projectId,
    required String address,
    required String room,
    required String queue,
    bool public = false,
    Map<String, String> annotations = const {},
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/mailboxes');
    final body = {'address': address, 'room': room, 'queue': queue, 'public': public, 'annotations': annotations};

    final response = await httpClient.post(uri, body: jsonEncode(body));

    if (response.statusCode == 409) {
      throw MeshagentException(
        'Failed to create mailbox. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to create mailbox. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  /// PUT /accounts/projects/{project_id}/mailboxes/{address}
  /// Body: { "room", "queue" }
  /// Returns {} on success.
  Future<void> updateMailbox({
    required String projectId,
    required String address,
    required String room,
    required String queue,
    bool public = false,
    Map<String, String> annotations = const {},
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedAddress = Uri.encodeComponent(address);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/mailboxes/$encodedAddress');
    final body = {'room': room, 'queue': queue, 'public': public, 'annotations': annotations};

    final response = await httpClient.put(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to update mailbox. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  /// GET /accounts/projects/{project_id}/mailboxes/{address}
  Future<Mailbox> getMailbox({required String projectId, required String address}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedAddress = Uri.encodeComponent(address);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/mailboxes/$encodedAddress');
    final response = await httpClient.get(uri);

    if (response.statusCode == 404) {
      throw NotFoundException('Mailbox not found: $address');
    }

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to get mailbox.'
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return Mailbox.fromJson(data["mailbox"]);
  }

  /// GET /accounts/projects/{project_id}/mailboxes
  /// Returns { "mailboxes": [ { "address","room","queue" }, ... ] }
  Future<MailboxesPage> listMailboxesPage(String projectId, {int count = 100, int offset = 0, String? filter}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final query = <String, String>{'count': '$count', 'offset': '$offset'};
    if (filter != null && filter.trim().isNotEmpty) query['filter'] = filter;
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/mailboxes').replace(queryParameters: query);
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list mailboxes. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return MailboxesPage.fromJson(data);
  }

  Future<List<Mailbox>> listMailboxes(String projectId, {int count = 100, int offset = 0, String? filter}) async {
    final page = await listMailboxesPage(projectId, count: count, offset: offset, filter: filter);
    return page.mailboxes;
  }

  /// GET /accounts/projects/{project_id}/rooms/{room_name}/mailboxes
  /// Returns { "mailboxes": [ { "address","room","queue" }, ... ] }
  Future<MailboxesPage> listRoomMailboxesPage({
    required String projectId,
    required String roomName,
    int count = 100,
    int offset = 0,
    String? filter,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRoomName = Uri.encodeComponent(roomName);

    final query = <String, String>{'count': '$count', 'offset': '$offset'};
    if (filter != null && filter.trim().isNotEmpty) query['filter'] = filter;
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/rooms/$encodedRoomName/mailboxes').replace(queryParameters: query);
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list room mailboxes. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return MailboxesPage.fromJson(data);
  }

  Future<List<Mailbox>> listRoomMailboxes({
    required String projectId,
    required String roomName,
    int count = 100,
    int offset = 0,
    String? filter,
  }) async {
    final page = await listRoomMailboxesPage(projectId: projectId, roomName: roomName, count: count, offset: offset, filter: filter);
    return page.mailboxes;
  }

  /// DELETE /accounts/projects/{project_id}/mailboxes/{address}
  /// Returns {} on success.
  Future<void> deleteMailbox({required String projectId, required String address}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedAddress = Uri.encodeComponent(address);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/mailboxes/$encodedAddress');

    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to delete mailbox. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  /// POST /accounts/projects/{project_id}/routes
  /// Body: { "domain", "room_name" }
  /// Returns {} on success.
  Future<void> createRoute({
    required String projectId,
    RouteSpec? spec,
    String? domain,
    String? roomName,
    String? port,
    Map<String, String> annotations = const {},
  }) async {
    spec ??= RouteSpec(
      metadata: RouteMetadata(name: domain!, annotations: annotations),
      domain: domain,
      backend: RouteBackend(room: RouteBackendTarget(name: roomName!)),
      paths: [RoutePath(targetPort: port!)],
    );
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/routes');
    final body = {'spec': spec.toJson()};

    final response = await httpClient.post(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to create domain. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  /// PUT /accounts/projects/{project_id}/routes/{domain}
  /// Body: { "room_name" }
  /// Returns {} on success.
  Future<void> updateRoute({
    required String projectId,
    required String domain,
    RouteSpec? spec,
    String? roomName,
    String? port,
    Map<String, String> annotations = const {},
  }) async {
    spec ??= RouteSpec(
      metadata: RouteMetadata(name: domain, annotations: annotations),
      domain: domain,
      backend: RouteBackend(room: RouteBackendTarget(name: roomName!)),
      paths: [RoutePath(targetPort: port!)],
    );
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedDomain = Uri.encodeComponent(domain);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/routes/$encodedDomain');
    final body = {'spec': spec.toJson()};

    final response = await httpClient.put(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to update domain. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  /// GET /accounts/projects/{project_id}/routes/{domain}
  Future<Route> getRoute({required String projectId, required String domain}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedDomain = Uri.encodeComponent(domain);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/routes/$encodedDomain');
    final response = await httpClient.get(uri);

    if (response.statusCode == 404) {
      throw NotFoundException('Route not found: $domain');
    }

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to get domain.'
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return Route.fromJson(data["route"] as Map<String, dynamic>);
  }

  /// GET /accounts/projects/{project_id}/routes
  /// Returns { "routes": [ { "domain","room_name" }, ... ] }
  Future<RoutesPage> listRoutesPage(String projectId, {int count = 100, int offset = 0, String? filter}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final query = <String, String>{'count': '$count', 'offset': '$offset'};
    if (filter != null && filter.trim().isNotEmpty) query['filter'] = filter;
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/routes').replace(queryParameters: query);
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list domains. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return RoutesPage.fromJson(data);
  }

  Future<List<Route>> listRoutes(String projectId, {int count = 100, int offset = 0, String? filter}) async {
    final page = await listRoutesPage(projectId, count: count, offset: offset, filter: filter);
    return page.routes;
  }

  /// GET /accounts/projects/{project_id}/rooms/{room_name}/routes
  /// Returns { "routes": [ { "domain","room_name" }, ... ] }
  Future<RoutesPage> listRoomRoutesPage({
    required String projectId,
    required String roomName,
    int count = 100,
    int offset = 0,
    String? filter,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRoomName = Uri.encodeComponent(roomName);

    final query = <String, String>{'count': '$count', 'offset': '$offset'};
    if (filter != null && filter.trim().isNotEmpty) query['filter'] = filter;
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/rooms/$encodedRoomName/routes').replace(queryParameters: query);
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list room domains. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return RoutesPage.fromJson(data);
  }

  Future<List<Route>> listRoomRoutes({
    required String projectId,
    required String roomName,
    int count = 100,
    int offset = 0,
    String? filter,
  }) async {
    final page = await listRoomRoutesPage(projectId: projectId, roomName: roomName, count: count, offset: offset, filter: filter);
    return page.routes;
  }

  /// GET /accounts/projects/{project_id}/agents/{agent_name}/routes
  Future<RoutesPage> listAgentRoutesPage({
    required String projectId,
    required String agentName,
    int count = 100,
    int offset = 0,
    String? filter,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedAgentName = Uri.encodeComponent(agentName);

    final query = <String, String>{'count': '$count', 'offset': '$offset'};
    if (filter != null && filter.trim().isNotEmpty) query['filter'] = filter;
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/agents/$encodedAgentName/routes').replace(queryParameters: query);
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list agent domains. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return RoutesPage.fromJson(data);
  }

  Future<List<Route>> listAgentRoutes({
    required String projectId,
    required String agentName,
    int count = 100,
    int offset = 0,
    String? filter,
  }) async {
    final page = await listAgentRoutesPage(projectId: projectId, agentName: agentName, count: count, offset: offset, filter: filter);
    return page.routes;
  }

  /// DELETE /accounts/projects/{project_id}/routes/{domain}
  /// Returns {} on success.
  Future<void> deleteRoute({required String projectId, required String domain}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedDomain = Uri.encodeComponent(domain);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/routes/$encodedDomain');

    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to delete domain. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<Feed> createFeed({
    required String projectId,
    required String name,
    String description = '',
    String visibility = 'private',
    bool paused = false,
    Map<String, String> annotations = const {},
    Object? messageSchema,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/feeds');
    final body = {
      'name': name,
      'description': description,
      'visibility': visibility,
      'paused': paused,
      'annotations': annotations,
      'message_schema': messageSchema,
    };

    final response = await httpClient.post(uri, body: jsonEncode(body));
    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to create feed. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return Feed.fromJson(data['feed'] as Map<String, dynamic>);
  }

  Future<void> updateFeed({
    required String projectId,
    required String feedId,
    required String name,
    String description = '',
    bool paused = false,
    Map<String, String> annotations = const {},
    Object? messageSchema,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedFeedId = Uri.encodeComponent(feedId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/feeds/$encodedFeedId');
    final body = {'name': name, 'description': description, 'paused': paused, 'annotations': annotations, 'message_schema': messageSchema};

    final response = await httpClient.put(uri, body: jsonEncode(body));
    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to update feed. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<Feed> getFeed({required String projectId, required String feedId}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedFeedId = Uri.encodeComponent(feedId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/feeds/$encodedFeedId');
    final response = await httpClient.get(uri);

    if (response.statusCode == 404) {
      throw NotFoundException('Feed not found: $feedId');
    }

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to get feed. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return Feed.fromJson(data['feed'] as Map<String, dynamic>);
  }

  Future<FeedsPage> listFeedsPage(String projectId, {int count = 100, int offset = 0, String? filter}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final query = <String, String>{'count': '$count', 'offset': '$offset'};
    if (filter != null && filter.trim().isNotEmpty) query['filter'] = filter;
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/feeds').replace(queryParameters: query);
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list feeds. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return FeedsPage.fromJson(data);
  }

  Future<List<Feed>> listFeeds(String projectId, {int count = 100, int offset = 0, String? filter}) async {
    final page = await listFeedsPage(projectId, count: count, offset: offset, filter: filter);
    return page.feeds;
  }

  Future<FeedsPage> listRoomFeedsPage({
    required String projectId,
    required String roomName,
    int count = 100,
    int offset = 0,
    String? filter,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRoomName = Uri.encodeComponent(roomName);
    final query = <String, String>{'count': '$count', 'offset': '$offset'};
    if (filter != null && filter.trim().isNotEmpty) query['filter'] = filter;
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/rooms/$encodedRoomName/feeds').replace(queryParameters: query);
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list room feeds. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return FeedsPage.fromJson(data);
  }

  Future<List<Feed>> listRoomFeeds({
    required String projectId,
    required String roomName,
    int count = 100,
    int offset = 0,
    String? filter,
  }) async {
    final page = await listRoomFeedsPage(projectId: projectId, roomName: roomName, count: count, offset: offset, filter: filter);
    return page.feeds;
  }

  Future<void> deleteFeed({required String projectId, required String feedId}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedFeedId = Uri.encodeComponent(feedId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/feeds/$encodedFeedId');
    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to delete feed. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<void> publishFeedMessage({required String projectId, required String feedId, required Object? message}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedFeedId = Uri.encodeComponent(feedId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/feeds/$encodedFeedId/messages');
    final response = await httpClient.post(uri, body: jsonEncode(message));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to publish feed message. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<void> publishFeedBatch({required String projectId, required String feedId, required List<Object?> messages}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedFeedId = Uri.encodeComponent(feedId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/feeds/$encodedFeedId/messages/batch');
    final response = await httpClient.post(uri, body: jsonEncode(messages));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to publish feed messages. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<FeedSubscription> createFeedSubscription({
    required String projectId,
    required String feedId,
    required String room,
    required String path,
    String? filenameDatetimeFormat,
    Map<String, String> annotations = const {},
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedFeedId = Uri.encodeComponent(feedId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/feeds/$encodedFeedId/subscriptions');
    final body = <String, Object>{'room': room, 'path': path, 'annotations': annotations};
    if (filenameDatetimeFormat != null) {
      body['filename_datetime_format'] = filenameDatetimeFormat;
    }

    final response = await httpClient.post(uri, body: jsonEncode(body));
    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to create feed subscription. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return FeedSubscription.fromJson(data['subscription'] as Map<String, dynamic>);
  }

  Future<void> updateFeedSubscription({
    required String projectId,
    required String feedId,
    required String subscriptionId,
    String? filenameDatetimeFormat,
    Map<String, String> annotations = const {},
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedFeedId = Uri.encodeComponent(feedId);
    final encodedSubscriptionId = Uri.encodeComponent(subscriptionId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/feeds/$encodedFeedId/subscriptions/$encodedSubscriptionId');
    final body = <String, Object>{'annotations': annotations};
    if (filenameDatetimeFormat != null) {
      body['filename_datetime_format'] = filenameDatetimeFormat;
    }

    final response = await httpClient.put(uri, body: jsonEncode(body));
    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to update feed subscription. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<FeedSubscription> getFeedSubscription({required String projectId, required String feedId, required String subscriptionId}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedFeedId = Uri.encodeComponent(feedId);
    final encodedSubscriptionId = Uri.encodeComponent(subscriptionId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/feeds/$encodedFeedId/subscriptions/$encodedSubscriptionId');
    final response = await httpClient.get(uri);

    if (response.statusCode == 404) {
      throw NotFoundException('Feed subscription not found: $subscriptionId');
    }

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to get feed subscription. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return FeedSubscription.fromJson(data['subscription'] as Map<String, dynamic>);
  }

  Future<List<FeedSubscription>> listFeedSubscriptions({required String projectId, required String feedId}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedFeedId = Uri.encodeComponent(feedId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/feeds/$encodedFeedId/subscriptions');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list feed subscriptions. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['subscriptions'] as List<dynamic>? ?? [];
    return list.whereType<Map<String, dynamic>>().map(FeedSubscription.fromJson).toList();
  }

  Future<void> deleteFeedSubscription({required String projectId, required String feedId, required String subscriptionId}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedFeedId = Uri.encodeComponent(feedId);
    final encodedSubscriptionId = Uri.encodeComponent(subscriptionId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/feeds/$encodedFeedId/subscriptions/$encodedSubscriptionId');
    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to delete feed subscription. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<LlmLogger> createLlmLogger({
    required String projectId,
    required String destinationFeedId,
    required String filterExpression,
    bool paused = false,
    Map<String, String> annotations = const {},
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/llm-loggers');
    final body = {
      'destination_feed_id': destinationFeedId,
      'filter_expression': filterExpression,
      'paused': paused,
      'annotations': annotations,
    };

    final response = await httpClient.post(uri, body: jsonEncode(body));
    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to create LLM logger. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return LlmLogger.fromJson(data['logger'] as Map<String, dynamic>);
  }

  Future<void> updateLlmLogger({
    required String projectId,
    required String loggerId,
    required String destinationFeedId,
    required String filterExpression,
    bool paused = false,
    Map<String, String> annotations = const {},
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedLoggerId = Uri.encodeComponent(loggerId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/llm-loggers/$encodedLoggerId');
    final body = {
      'destination_feed_id': destinationFeedId,
      'filter_expression': filterExpression,
      'paused': paused,
      'annotations': annotations,
    };

    final response = await httpClient.put(uri, body: jsonEncode(body));
    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to update LLM logger. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<LlmLogger> getLlmLogger({required String projectId, required String loggerId}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedLoggerId = Uri.encodeComponent(loggerId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/llm-loggers/$encodedLoggerId');
    final response = await httpClient.get(uri);

    if (response.statusCode == 404) {
      throw NotFoundException('LLM logger not found: $loggerId');
    }

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to get LLM logger. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return LlmLogger.fromJson(data['logger'] as Map<String, dynamic>);
  }

  Future<List<LlmLogger>> listLlmLoggers(String projectId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/llm-loggers');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list LLM loggers. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['loggers'] as List<dynamic>? ?? [];
    return list.whereType<Map<String, dynamic>>().map(LlmLogger.fromJson).toList();
  }

  Future<void> deleteLlmLogger({required String projectId, required String loggerId}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedLoggerId = Uri.encodeComponent(loggerId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/llm-loggers/$encodedLoggerId');
    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to delete LLM logger. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<ProjectRepository> createRepository({
    required String projectId,
    required String name,
    String description = '',
    Map<String, String> annotations = const {},
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/repositories');
    final body = {'name': name, 'description': description, 'annotations': annotations};

    final response = await httpClient.post(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to create repository. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return ProjectRepository.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<ProjectRepository> updateRepository({
    required String projectId,
    required String repositoryId,
    required String name,
    String description = '',
    Map<String, String> annotations = const {},
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRepositoryId = Uri.encodeComponent(repositoryId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/repositories/$encodedRepositoryId');
    final body = {'name': name, 'description': description, 'annotations': annotations};

    final response = await httpClient.put(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to update repository. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return ProjectRepository.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<ProjectRepository> getRepository({required String projectId, required String repositoryId}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRepositoryId = Uri.encodeComponent(repositoryId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/repositories/$encodedRepositoryId');
    final response = await httpClient.get(uri);

    if (response.statusCode == 404) {
      throw NotFoundException('Repository not found: $repositoryId');
    }

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to get repository. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return ProjectRepository.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<MeshagentRepositoriesPage> listRepositoriesPage({required String projectId, int count = 100, int offset = 0}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/repositories',
    ).replace(queryParameters: {'count': '$count', 'offset': '$offset'});
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list repositories. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return MeshagentRepositoriesPage.fromJson(data);
  }

  Future<List<ProjectRepository>> listRepositories({required String projectId}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/repositories');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list repositories. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['repositories'] as List<dynamic>? ?? [];
    return list.whereType<Map>().map((m) => ProjectRepository.fromJson(m.cast<String, dynamic>())).toList();
  }

  Future<List<ProjectRepositoryTag>> listRepositoryTags({required String projectId, required String repositoryId}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRepositoryId = Uri.encodeComponent(repositoryId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/repositories/$encodedRepositoryId/tags');
    final response = await httpClient.get(uri);

    if (response.statusCode == 404) {
      throw NotFoundException('Repository not found: $repositoryId');
    }

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list repository tags. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['tags'] as List<dynamic>? ?? [];
    return list.whereType<Map<String, dynamic>>().map(ProjectRepositoryTag.fromJson).toList();
  }

  Future<List<ProjectRepositoryImage>> listRepositoryImages({required String projectId, required String repositoryId}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRepositoryId = Uri.encodeComponent(repositoryId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/repositories/$encodedRepositoryId/images');
    final response = await httpClient.get(uri);

    if (response.statusCode == 404) {
      throw NotFoundException('Repository not found: $repositoryId');
    }

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list repository images. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['images'] as List<dynamic>? ?? [];
    return list.whereType<Map<String, dynamic>>().map(ProjectRepositoryImage.fromJson).toList();
  }

  Future<void> deleteRepositoryTag({required String projectId, required String repositoryId, required String tag}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRepositoryId = Uri.encodeComponent(repositoryId);
    final encodedTag = Uri.encodeComponent(tag);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/repositories/$encodedRepositoryId/tags/$encodedTag');

    final response = await httpClient.delete(uri);

    if (response.statusCode == 404) {
      throw NotFoundException('Repository tag not found: $tag');
    }

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to delete repository tag. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<void> updateRepositoryImageTags({
    required String projectId,
    required String repositoryId,
    required String digest,
    required List<String> tags,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRepositoryId = Uri.encodeComponent(repositoryId);
    final encodedDigest = Uri.encodeComponent(digest);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/repositories/$encodedRepositoryId/manifests/$encodedDigest/tags');

    final response = await httpClient.put(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode({'tags': tags}));

    if (response.statusCode == 404) {
      throw NotFoundException('Repository manifest not found: $digest');
    }

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to update repository image tags. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<void> deleteRepositoryManifest({required String projectId, required String repositoryId, required String digest}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRepositoryId = Uri.encodeComponent(repositoryId);
    final encodedDigest = Uri.encodeComponent(digest);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/repositories/$encodedRepositoryId/manifests/$encodedDigest');

    final response = await httpClient.delete(uri);

    if (response.statusCode == 404) {
      throw NotFoundException('Repository manifest not found: $digest');
    }

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to delete repository manifest. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<void> deleteRepository({required String projectId, required String repositoryId}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRepositoryId = Uri.encodeComponent(repositoryId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/repositories/$encodedRepositoryId');

    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to delete repository. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<String> createProjectSecret({
    required String projectId,
    required String name,
    required String type,
    required Uint8List data,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/secrets');
    final body = {'name': name, 'type': type, 'data_base64': base64Encode(_normalizeSecretBytes(data))};

    final response = await httpClient.post(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to create project secret. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return (jsonDecode(response.body) as Map<String, dynamic>)['id'] as String;
  }

  // Corresponds to: GET /pricing
  Future<Map<String, dynamic>> getPricing() async {
    final uri = Uri.parse('$baseUrl/pricing');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to get pricing data. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<ManagedSecret> getProjectSecret({required String projectId, required String secretId}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedSecretId = Uri.encodeComponent(secretId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/secrets/$encodedSecretId');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to get project secret. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return ManagedSecret.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<MeshagentSecretsPage> listProjectSecretsPage(String projectId, {int count = 100, int offset = 0}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/secrets',
    ).replace(queryParameters: {'count': '$count', 'offset': '$offset'});
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list project secrets. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return MeshagentSecretsPage.fromJson(data);
  }

  Future<List<ManagedSecretInfo>> listProjectSecrets(String projectId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/secrets');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list project secrets. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final secretsList = data['secrets'] as List<dynamic>? ?? [];
    return secretsList.whereType<Map>().map((m) => ManagedSecretInfo.fromJson(m.cast<String, dynamic>())).toList();
  }

  Future<void> updateProjectSettings({required String projectId, required Map<String, dynamic> settings}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/settings');
    final response = await httpClient.put(uri, body: jsonEncode(settings));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to update secret. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<void> updateProjectSecret({
    required String projectId,
    required String secretId,
    required String name,
    required String type,
    required Uint8List data,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedSecretId = Uri.encodeComponent(secretId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/secrets/$encodedSecretId');
    final body = {'name': name, 'type': type, 'data_base64': base64Encode(_normalizeSecretBytes(data))};

    final response = await httpClient.put(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to update project secret. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<void> deleteProjectSecret({required String projectId, required String secretId}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedSecretId = Uri.encodeComponent(secretId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/secrets/$encodedSecretId');
    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to delete project secret. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<String> createRoomSecret({
    required String projectId,
    required String roomName,
    required Uint8List data,
    String? secretId,
    String? name,
    String? type,
    String? delegatedTo,
    String? forIdentity,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRoomName = Uri.encodeComponent(roomName);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/rooms/$encodedRoomName/secrets');
    final body = <String, dynamic>{
      'data_base64': base64Encode(_normalizeSecretBytes(data)),
      'secret_id': ?secretId,
      'name': ?name,
      'type': ?type,
      'delegated_to': ?delegatedTo,
      'for_identity': ?forIdentity,
    };

    final response = await httpClient.post(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to create room secret. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return (jsonDecode(response.body) as Map<String, dynamic>)['id'] as String;
  }

  Future<void> updateRoomSecret({
    required String projectId,
    required String roomName,
    required String secretId,
    required Uint8List data,
    String? name,
    String? type,
    String? delegatedTo,
    String? forIdentity,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRoomName = Uri.encodeComponent(roomName);
    final encodedSecretId = Uri.encodeComponent(secretId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/rooms/$encodedRoomName/secrets/$encodedSecretId');
    final body = <String, dynamic>{
      'data_base64': base64Encode(_normalizeSecretBytes(data)),
      'name': ?name,
      'type': ?type,
      'delegated_to': ?delegatedTo,
      'for_identity': ?forIdentity,
    };

    final response = await httpClient.put(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to update room secret. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<ManagedSecret> getRoomSecret({
    required String projectId,
    required String roomName,
    required String secretId,
    String? delegatedTo,
    String? forIdentity,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRoomName = Uri.encodeComponent(roomName);
    final encodedSecretId = Uri.encodeComponent(secretId);
    final query = <String, String>{};
    if (delegatedTo != null) query['delegated_to'] = delegatedTo;
    if (forIdentity != null) query['for_identity'] = forIdentity;
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/rooms/$encodedRoomName/secrets/$encodedSecretId',
    ).replace(queryParameters: query.isEmpty ? null : query);
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to get room secret. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return ManagedSecret.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<ManagedSecretInfo>> listRoomSecrets({required String projectId, required String roomName, String? forIdentity}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRoomName = Uri.encodeComponent(roomName);
    final query = <String, String>{};
    if (forIdentity != null) query['for_identity'] = forIdentity;
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/rooms/$encodedRoomName/secrets',
    ).replace(queryParameters: query.isEmpty ? null : query);
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list room secrets. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final secretsList = data['secrets'] as List<dynamic>? ?? [];
    return secretsList.whereType<Map<String, dynamic>>().map(ManagedSecretInfo.fromJson).toList();
  }

  Future<void> deleteRoomSecret({
    required String projectId,
    required String roomName,
    required String secretId,
    String? delegatedTo,
    String? forIdentity,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRoomName = Uri.encodeComponent(roomName);
    final encodedSecretId = Uri.encodeComponent(secretId);
    final query = <String, String>{};
    if (delegatedTo != null) query['delegated_to'] = delegatedTo;
    if (forIdentity != null) query['for_identity'] = forIdentity;
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/rooms/$encodedRoomName/secrets/$encodedSecretId',
    ).replace(queryParameters: query.isEmpty ? null : query);
    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to delete room secret. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<String> createAgentSecret({
    required String projectId,
    required String agentId,
    required Uint8List data,
    String? secretId,
    String? name,
    String? type,
    String? delegatedTo,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedAgentId = Uri.encodeComponent(agentId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/agents/$encodedAgentId/secrets');
    final body = <String, dynamic>{
      'data_base64': base64Encode(_normalizeSecretBytes(data)),
      'secret_id': ?secretId,
      'name': ?name,
      'type': ?type,
      'delegated_to': ?delegatedTo,
    };

    final response = await httpClient.post(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to create agent secret. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return (jsonDecode(response.body) as Map<String, dynamic>)['id'] as String;
  }

  Future<void> updateAgentSecret({
    required String projectId,
    required String agentId,
    required String secretId,
    required Uint8List data,
    String? name,
    String? type,
    String? delegatedTo,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedAgentId = Uri.encodeComponent(agentId);
    final encodedSecretId = Uri.encodeComponent(secretId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/agents/$encodedAgentId/secrets/$encodedSecretId');
    final body = <String, dynamic>{
      'data_base64': base64Encode(_normalizeSecretBytes(data)),
      'name': ?name,
      'type': ?type,
      'delegated_to': ?delegatedTo,
    };

    final response = await httpClient.put(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to update agent secret. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<ManagedSecret> getAgentSecret({
    required String projectId,
    required String agentId,
    required String secretId,
    String? delegatedTo,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedAgentId = Uri.encodeComponent(agentId);
    final encodedSecretId = Uri.encodeComponent(secretId);
    final query = <String, String>{};
    if (delegatedTo != null) query['delegated_to'] = delegatedTo;
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/agents/$encodedAgentId/secrets/$encodedSecretId',
    ).replace(queryParameters: query.isEmpty ? null : query);
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to get agent secret. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return ManagedSecret.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<ManagedSecretInfo>> listAgentSecrets({required String projectId, required String agentId}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedAgentId = Uri.encodeComponent(agentId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/agents/$encodedAgentId/secrets');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list agent secrets. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final secretsList = data['secrets'] as List<dynamic>? ?? [];
    return secretsList.whereType<Map<String, dynamic>>().map(ManagedSecretInfo.fromJson).toList();
  }

  Future<void> deleteAgentSecret({
    required String projectId,
    required String agentId,
    required String secretId,
    String? delegatedTo,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedAgentId = Uri.encodeComponent(agentId);
    final encodedSecretId = Uri.encodeComponent(secretId);
    final query = <String, String>{};
    if (delegatedTo != null) query['delegated_to'] = delegatedTo;
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/agents/$encodedAgentId/secrets/$encodedSecretId',
    ).replace(queryParameters: query.isEmpty ? null : query);
    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to delete agent secret. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<Map<String, dynamic>> createSecret({
    required String projectId,
    required String name,
    required String type,
    required Map<String, dynamic> data,
  }) async {
    final secretId = await createProjectSecret(
      projectId: projectId,
      name: name,
      type: type,
      data: Uint8List.fromList(utf8.encode(jsonEncode(data))),
    );
    return {'id': secretId};
  }

  Future<MeshagentLegacySecretsPage> listSecretsPage(String projectId, {int count = 100, int offset = 0}) async {
    final page = await listProjectSecretsPage(projectId, count: count, offset: offset);
    final secrets = <Map<String, dynamic>>[];
    for (final secretInfo in page.secrets) {
      final secret = await getProjectSecret(projectId: projectId, secretId: secretInfo.id);
      secrets.add(_parseLegacySecretPayload(secret: secret, rawData: secret.data));
    }
    return MeshagentLegacySecretsPage(secrets: secrets, total: page.total);
  }

  Future<List<Map<String, dynamic>>> listSecrets(String projectId) async {
    final secretInfos = await listProjectSecrets(projectId);
    final secrets = <Map<String, dynamic>>[];
    for (final secretInfo in secretInfos) {
      final secret = await getProjectSecret(projectId: projectId, secretId: secretInfo.id);
      secrets.add(_parseLegacySecretPayload(secret: secret, rawData: secret.data));
    }
    return secrets;
  }

  Future<void> updateSecret({
    required String projectId,
    required String secretId,
    required String name,
    required String type,
    required Map<String, dynamic> data,
  }) async {
    await updateProjectSecret(
      projectId: projectId,
      secretId: secretId,
      name: name,
      type: type,
      data: Uint8List.fromList(utf8.encode(jsonEncode(data))),
    );
  }

  Future<void> deleteSecret({required String projectId, required String secretId}) async {
    await deleteProjectSecret(projectId: projectId, secretId: secretId);
  }

  /// Corresponds to: POST /projects/:project_id/storage/upload
  Future<void> upload({required String projectId, required String path, required Uint8List data}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/projects/$encodedProjectId/storage/upload').replace(queryParameters: {"path": path});
    final response = await httpClient.post(uri, body: data);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Request failed.'
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  /// Corresponds to: DELETE /projects/:project_id/storage/delete
  Future<void> delete({required String projectId, required String path}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/projects/$encodedProjectId/storage/delete').replace(queryParameters: {"path": path});
    final response = await httpClient.delete(uri);

    if (response.statusCode == 404) {
      throw NotFoundException("file was not found");
    }
    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Request failed.'
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  /// Corresponds to: POST /projects/:project_id/storage/download
  Future<Uint8List> download({required String projectId, required String path}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/projects/$encodedProjectId/storage/download').replace(queryParameters: {"path": path});

    final response = await httpClient.get(uri);

    if (response.statusCode == 404) {
      throw NotFoundException("file was not found");
    }
    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Request failed.'
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return response.bodyBytes;
  }

  /// Corresponds to: POST /templates/render
  Future<ServiceTemplateSpec> renderTemplate({required String template, required Map<String, String> values}) async {
    final uri = Uri.parse('$baseUrl/templates/render');

    final response = await httpClient.post(uri, body: jsonEncode({"template": template, "values": values}));

    if (response.statusCode > 400) {
      throw MeshagentException(
        'Failed to render template. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    if (response.statusCode == 400) {
      throw MeshagentException(jsonDecode(response.body)["error"]);
    }

    return ServiceTemplateSpec.fromJson(jsonDecode(response.body));
  }

  /// Corresponds to: POST /mcp/discover
  Future<ServiceSpec> discoverMcpService({required String url}) async {
    final uri = Uri.parse('$baseUrl/mcp/discover');

    final response = await httpClient.post(uri, body: jsonEncode({"url": url, "format": "service"}));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to discover MCP service. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return ServiceSpec.fromJson(jsonDecode(response.body));
  }

  /// Corresponds to: POST /mcp/discover
  Future<ServiceTemplateSpec> discoverMcpServiceTemplate({required String url}) async {
    final uri = Uri.parse('$baseUrl/mcp/discover');

    final response = await httpClient.post(uri, body: jsonEncode({"url": url, "format": "template"}));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to discover MCP service template. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return ServiceTemplateSpec.fromJson(jsonDecode(response.body));
  }

  /// Corresponds to: POST /accounts/projects/:project_id/services
  /// Body: { "name", "image", "pull_secret", "runtime_secrets", "environment_secrets", "environment" : \<settings\> }
  /// Returns JSON like { "id" } on success.
  Future<ServiceSpec> createService({required String projectId, required ServiceSpec service}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/services');

    final response = await httpClient.post(uri, body: jsonEncode(_createServiceSpecJson(service)));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Request failed.'
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return ServiceSpec.fromJson(jsonDecode(response.body));
  }

  /// Corresponds to: POST /accounts/projects/:project_id/
  /// Body: { "environment" : \<settings\> }
  /// Returns JSON like { "id" } on success.
  Future<ServiceSpec> updateService({required String projectId, required String serviceId, required ServiceSpec service}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedServiceId = Uri.encodeComponent(serviceId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/services/$encodedServiceId');
    final response = await httpClient.put(uri, body: jsonEncode(service.toJson()));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Request failed.'
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return ServiceSpec.fromJson(jsonDecode(response.body));
  }

  /// Corresponds to: PUT /accounts/projects/:project_id/rooms/:room_name/services/:service_id
  /// Body: { "template": {}, "values": { ... } }
  Future<ServiceSpec> updateServiceFromTemplate({
    required String projectId,
    required String serviceId,
    required String template,
    required Map<String, String> values,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedServiceId = Uri.encodeComponent(serviceId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/services/$encodedServiceId');
    final response = await httpClient.put(uri, body: jsonEncode({'template': template, 'values': values}));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to update room service from template. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return ServiceSpec.fromJson(jsonDecode(response.body));
  }

  /// Corresponds to: POST /accounts/projects/:project_id/rooms/:room_name/services
  /// Body: { "template": {}, "values": { ... } }
  /// Returns JSON like { "id" } on success.
  Future<ServiceSpec> createServiceFromTemplate({
    required String projectId,
    required String template,
    required Map<String, String> values,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/services');
    final response = await httpClient.post(uri, body: jsonEncode({'template': template, 'values': values}));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to create room service from template. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return ServiceSpec.fromJson(jsonDecode(response.body));
  }

  /// --------------------------------
  /// Services (single fetch)
  /// --------------------------------

  /// GET /accounts/projects/{project_id}/services/{service_id}
  /// Returns a single Service.
  ///
  /// Note: Some servers may return the JSON as a string payload.
  /// This method handles both a Map response and a stringified JSON.
  Future<ServiceSpec> getService({required String projectId, required String serviceId}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedServiceId = Uri.encodeComponent(serviceId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/services/$encodedServiceId');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to get service. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    final Map<String, dynamic> json = decoded is String ? jsonDecode(decoded) as Map<String, dynamic> : decoded as Map<String, dynamic>;

    return ServiceSpec.fromJson(json);
  }

  /// Corresponds to: GET /accounts/projects/{project_id}/services
  /// Returns a JSON dict like: { "tokens": [ { ... }, ... ] }.
  Future<MeshagentServicesPage> listServicesPage(String projectId, {int count = 100, int offset = 0}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/services',
    ).replace(queryParameters: {'count': '$count', 'offset': '$offset'});
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list project services keys. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    return MeshagentServicesPage.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<ServiceSpec>> listServices(String projectId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/services');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list project services keys. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['services'] as List<dynamic>? ?? [];
    return list.whereType<Map>().map((m) => ServiceSpec.fromJson(m.cast<String, dynamic>())).toList();
  }

  /// Corresponds to: DELETE /accounts/projects/{project_id}/services/{token_id}
  /// Returns 204 No Content on success (no JSON body).
  Future<void> deleteService({required String projectId, required String serviceId}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedServiceId = Uri.encodeComponent(serviceId);

    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/services/$encodedServiceId');
    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to delete project service'
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    // 204 No Content -> no need to parse response body.
    return;
  }

  /// Corresponds to: POST /accounts/projects/:project_id/services
  /// Body: { "name", "image", "pull_secret", "runtime_secrets", "environment_secrets", "environment" : \<settings\> }
  /// Returns JSON like { "id" } on success.
  Future<String> createRoomService({required String projectId, required ServiceSpec service, required String roomName}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRoomName = Uri.encodeComponent(roomName);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/rooms/$encodedRoomName/services');
    final response = await httpClient.post(uri, body: jsonEncode(_createServiceSpecJson(service)));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Request failed.'
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return jsonDecode(response.body)["id"];
  }

  /// Corresponds to: POST /accounts/projects/:project_id/rooms/:room_name/services
  /// Body: { "template": {}, "values": { ... } }
  /// Returns JSON like { "id" } on success.
  Future<ServiceSpec> createRoomServiceFromTemplate({
    required String projectId,
    required String roomName,
    required String template,
    required Map<String, String> values,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRoomName = Uri.encodeComponent(roomName);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/rooms/$encodedRoomName/services');
    final response = await httpClient.post(uri, body: jsonEncode({'template': template, 'values': values}));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to create room service from template. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return ServiceSpec.fromJson(jsonDecode(response.body));
  }

  /// Corresponds to: POST /accounts/projects/:project_id/
  /// Body: { "environment" : \<settings\> }
  /// Returns JSON like { "id" } on success.
  Future<void> updateRoomService({
    required String projectId,
    required String serviceId,
    required ServiceSpec service,
    required String roomName,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRoomName = Uri.encodeComponent(roomName);
    final encodedServiceId = Uri.encodeComponent(serviceId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/rooms/$encodedRoomName/services/$encodedServiceId');
    final response = await httpClient.put(uri, body: jsonEncode(service.toJson()));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Request failed.'
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  /// Corresponds to: PUT /accounts/projects/:project_id/rooms/:room_name/services/:service_id
  /// Body: { "template": {}, "values": { ... } }
  Future<ServiceSpec> updateRoomServiceFromTemplate({
    required String projectId,
    required String roomName,
    required String serviceId,
    required String template,
    required Map<String, String> values,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRoomName = Uri.encodeComponent(roomName);
    final encodedServiceId = Uri.encodeComponent(serviceId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/rooms/$encodedRoomName/services/$encodedServiceId');
    final response = await httpClient.put(uri, body: jsonEncode({'template': template, 'values': values}));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to update room service from template. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return ServiceSpec.fromJson(jsonDecode(response.body));
  }

  /// --------------------------------
  /// Services (single fetch)
  /// --------------------------------

  /// GET /accounts/projects/{project_id}/services/{service_id}
  /// Returns a single Service.
  ///
  /// Note: Some servers may return the JSON as a string payload.
  /// This method handles both a Map response and a stringified JSON.
  Future<ServiceSpec> getRoomService({required String projectId, required String serviceId, required String roomName}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedServiceId = Uri.encodeComponent(serviceId);
    final encodedRoomName = Uri.encodeComponent(roomName);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/rooms/$encodedRoomName/services/$encodedServiceId');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to get service. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    final Map<String, dynamic> json = decoded is String ? jsonDecode(decoded) as Map<String, dynamic> : decoded as Map<String, dynamic>;

    return ServiceSpec.fromJson(json);
  }

  /// Corresponds to: GET /accounts/projects/{project_id}/services
  /// Returns a JSON dict like: { "tokens": [ { ... }, ... ] }.
  Future<MeshagentServicesPage> listRoomServicesPage({
    required String projectId,
    required String roomName,
    int count = 100,
    int offset = 0,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRoomName = Uri.encodeComponent(roomName);
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/rooms/$encodedRoomName/services',
    ).replace(queryParameters: {'count': '$count', 'offset': '$offset'});
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list room services keys. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    return MeshagentServicesPage.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<ServiceSpec>> listRoomServices({required String projectId, required String roomName}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRoomName = Uri.encodeComponent(roomName);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/rooms/$encodedRoomName/services');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list room services keys. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['services'] as List<dynamic>? ?? [];
    return list.whereType<Map>().map((m) => ServiceSpec.fromJson(m.cast<String, dynamic>())).toList();
  }

  /// Corresponds to: DELETE /accounts/projects/{project_id}/services/{token_id}
  /// Returns 204 No Content on success (no JSON body).
  Future<void> deleteRoomService({required String projectId, required String serviceId, required String roomName}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedServiceId = Uri.encodeComponent(serviceId);
    final encodedRoomName = Uri.encodeComponent(roomName);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/rooms/$encodedRoomName/services/$encodedServiceId');
    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to delete room service'
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    // 204 No Content -> no need to parse response body.
    return;
  }

  /// Corresponds to: POST /accounts/projects/:project_id/shares
  /// Body: { "settings" : \<settings\> }
  /// Returns JSON like { "id" } on success.
  Future<Map<String, dynamic>> createShare(String projectId, {Map<String, dynamic>? settings}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/shares');
    final response = await httpClient.post(uri, body: jsonEncode({'settings': settings ?? {}}));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Request failed.'
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Corresponds to: DELETE /accounts/projects/:project_id/shares/:share_id
  /// No JSON response on success.
  Future<void> deleteShare(String projectId, String shareId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedShareId = Uri.encodeComponent(shareId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/shares/$encodedShareId');

    final response = await httpClient.delete(uri);
    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to delete share. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    // 204 or 200 on success, no body to parse
  }

  /// Corresponds to: PUT /accounts/projects/:project_id/shares/:share_id
  /// Body: { "settings": \<settings\> }
  /// No JSON response on success.
  Future<void> updateShare(String projectId, String shareId, {Map<String, dynamic>? settings}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedShareId = Uri.encodeComponent(shareId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/shares/$encodedShareId');
    final response = await httpClient.put(uri, body: jsonEncode({'settings': settings ?? {}}));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to update share. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    // 200 or 204 on success, no body to parse
  }

  /// Corresponds to: GET /accounts/projects/:project_id/shares
  /// Returns JSON like { "shares": [ { "id", "settings" } ] } on success.
  Future<List<Map<String, dynamic>>> listShares(String projectId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/shares');

    final response = await httpClient.get(uri);
    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list shares. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final sharesList = data['shares'] as List<dynamic>? ?? [];
    // Convert each item to Map<String, dynamic>
    return sharesList.whereType<Map<String, dynamic>>().toList();
  }

  /// Corresponds to: POST /accounts/projects
  /// Body: { "name": "\<name\>" }
  /// Returns JSON like { "id", "owner_user_id", "name" } on success.
  Future<Map<String, dynamic>> createProject(String name) async {
    final uri = Uri.parse('$baseUrl/accounts/projects');
    final response = await httpClient.post(uri, body: jsonEncode({'name': name}));

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to create project. Status code: ${response.statusCode}, body: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Corresponds to: DELETE /accounts/projects/:project_id
  Future<void> deleteProject(String projectId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId');
    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to remove user from project. Status code: ${response.statusCode}, body: ${response.body}');
    }
  }

  /// Corresponds to: POST /accounts/projects/:project_id/users
  /// Body: { "project_id", "user_id" }
  /// Returns JSON like { "ok": true } on success.
  Future<Map<String, dynamic>> addUserToProject(
    String projectId,
    String userId, {
    bool? isAdmin,
    bool? isDeveloper,
    bool? canCreateRooms,
    bool? canCreateAgents,
    bool? canUseLlmProxy,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/users');

    final body = {
      'project_id': projectId,
      'user_id': userId,
      "is_admin": ?isAdmin,
      "is_developer": ?isDeveloper,
      "can_create_rooms": ?canCreateRooms,
      "can_create_agents": ?canCreateAgents,
      "can_use_llm_proxy": ?canUseLlmProxy,
    };

    final response = await httpClient.post(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to add user to project. Status code: ${response.statusCode}, body: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<bool> getStatus(String projectId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/status');
    final response = await httpClient.get(uri);

    final data = (jsonDecode(response.body) as Map<String, dynamic>);
    return data["enabled"] == true;
  }

  Future<Balance> getBalance(String projectId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/balance');
    final response = await httpClient.get(uri);

    final data = (jsonDecode(response.body) as Map<String, dynamic>);

    final lastRechargeStr = (data["last_recharge"] as String?);
    return Balance(
      balance: (data["balance"] as num).toDouble(),
      autoRechargeAmount: (data["auto_recharge_amount"] as num?)?.toDouble(),
      autoRechargeThreshhold: (data["auto_recharge_threshold"] as num?)?.toDouble(),
      lastRecharge: lastRechargeStr == null ? null : DateTime.parse(lastRechargeStr),
      monthlyBudget: (data["monthly_budget"] as num?)?.toDouble(),
      autoRechargePaused: data["auto_recharge_paused"] == true,
      autoRechargedThisMonth: (data["auto_recharged_this_month"] as num?)?.toDouble(),
    );
  }

  Future<List<Transaction>> getRecentTransactions(String projectId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/transactions');
    final response = await httpClient.get(uri);

    final data = (jsonDecode(response.body) as Map<String, dynamic>);

    List<Transaction> transactions = [];

    for (final transaction in data["transactions"]) {
      transactions.add(
        Transaction(
          id: transaction["id"],
          amount: (transaction["amount"] as num).toDouble(),
          description: transaction["description"],
          reference: transaction["reference"],
          referenceType: transaction["referenceType"],
          createdAt: DateTime.parse(transaction["created_at"]),
        ),
      );
    }

    return transactions;
  }

  Future<void> setAutoRecharge({
    required String projectId,
    required bool enabled,
    required double amount,
    required double threshold,
    double? monthlyBudget,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/recharge');
    final resp = await httpClient.post(
      uri,
      body: jsonEncode({"enabled": enabled, "amount": amount, "threshold": threshold, "monthly_budget": monthlyBudget}),
    );

    if (resp.statusCode != 200) {
      throw Exception("Unable to update autorecharge");
    }
  }

  Future<List<Map<String, dynamic>>> getUsage(
    String projectId, {
    DateTime? start,
    DateTime? end,
    String? interval,
    String? report,
    List<String>? users,
    String? room,
    String? provider,
    String? model,
    String? usageType,
    String? client,
    Map<String, String>? annotations,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/usage');
    final queryParams = <String, String>{
      if (start != null) "start": start.toIso8601String(),
      if (end != null) "end": end.toIso8601String(),
      "interval": ?interval,
      "report": ?report,
      if (users != null && users.isNotEmpty) "users": users.join(","),
      if (room != null && room.trim().isNotEmpty) "room": room.trim(),
      if (provider != null && provider.trim().isNotEmpty) "provider": provider.trim(),
      if (model != null && model.trim().isNotEmpty) "model": model.trim(),
      if (usageType != null && usageType.trim().isNotEmpty) "usage_type": usageType.trim(),
      if (client != null && client.trim().isNotEmpty) "client": client.trim(),
      if (annotations != null && annotations.isNotEmpty) "annotations": jsonEncode(annotations),
    };
    final response = await httpClient.get(uri.replace(queryParameters: queryParams));

    List<Map<String, dynamic>> results = [];
    for (final map in (jsonDecode(response.body) as Map<String, dynamic>)["usage"]) {
      results.add(map);
    }

    return results;
  }

  /// Corresponds to: POST /accounts/projects/:project_id/users/:user_id
  /// Body: { "is_admin" }
  /// Returns JSON like { "ok": true } on success.
  Future<void> updateUser({
    required String projectId,
    required String userId,
    required bool isAdmin,
    required bool isDeveloper,
    required bool canCreateRooms,
    required bool canCreateAgents,
    required bool canUseLlmProxy,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedUserId = Uri.encodeComponent(userId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/users/$encodedUserId');
    final body = {
      'is_admin': isAdmin,
      "is_developer": isDeveloper,
      "can_create_rooms": canCreateRooms,
      "can_create_agents": canCreateAgents,
      "can_use_llm_proxy": canUseLlmProxy,
    };

    final response = await httpClient.put(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to add user to project. Status code: ${response.statusCode}, body: ${response.body}');
    }
  }

  /// Corresponds to: POST /accounts/projects/:project_id/users
  /// Body: { "project_id", "user_id" }
  /// Returns JSON like { "ok": true } on success.
  Future<Map<String, dynamic>> addUserToProjectByEmail(
    String projectId,
    String email, {
    bool? isAdmin,
    bool? isDeveloper,
    bool? canCreateRooms,
    bool? canCreateAgents,
    bool? canUseLlmProxy,
    Uri? inviteRedirectUrl,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/users');
    final body = {
      'project_id': projectId,
      'email': email,
      "is_admin": ?isAdmin,
      "is_developer": ?isDeveloper,
      "can_create_rooms": ?canCreateRooms,
      "can_create_agents": ?canCreateAgents,
      "can_use_llm_proxy": ?canUseLlmProxy,
      "invite_redirect_url": ?inviteRedirectUrl?.toString(),
    };

    final response = await httpClient.post(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to add user to project. Status code: ${response.statusCode}, body: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Corresponds to: DELETE /accounts/projects/:project_id/users
  /// Body: { "project_id", "user_id" }
  /// Returns JSON like { "ok": true } on success.
  Future<Map<String, dynamic>> removeUserFromProject(String projectId, String userId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedUserId = Uri.encodeComponent(userId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/users/$encodedUserId');
    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to remove user from project. Status code: ${response.statusCode}, body: ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Corresponds to: GET /accounts/projects/:project_id/users
  /// Returns JSON like { "users": [...] } on success.
  Future<ProjectMembersPage> getUsersInProjectPage(
    String projectId, {
    String? email,
    int count = 100,
    int offset = 0,
    String? filter,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    Uri uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/users');

    if (email != null) {
      uri = uri.replace(queryParameters: {"email": email});
    } else {
      final query = <String, String>{'count': '$count', 'offset': '$offset'};
      if (filter != null && filter.trim().isNotEmpty) query['filter'] = filter;
      uri = uri.replace(queryParameters: query);
    }

    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to get users in project. Status code: ${response.statusCode}, body: ${response.body}');
    }
    return ProjectMembersPage.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<Map<String, dynamic>>> getUsersInProject(
    String projectId, {
    String? email,
    int count = 100,
    int offset = 0,
    String? filter,
  }) async {
    final page = await getUsersInProjectPage(projectId, email: email, count: count, offset: offset, filter: filter);
    return page.users;
  }

  /// Corresponds to: GET /accounts/profiles/:user_id
  /// Returns user profile JSON, e.g. { "id", "first_name", "last_name", "email" } on success
  /// or throws an error if not found.
  Future<Map<String, dynamic>> getUserProfile(String userId) async {
    final encodedUserId = Uri.encodeComponent(userId);
    final uri = Uri.parse('$baseUrl/accounts/profiles/$encodedUserId');
    final response = await httpClient.get(uri);

    if (response.statusCode == 403) {
      throw ForbiddenException('Failed to get user profile. Status code: ${response.statusCode}, body: ${response.body}');
    }

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to get user profile. Status code: ${response.statusCode}, body: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Corresponds to: PUT /accounts/profiles/:user_id
  /// Body: { "first_name", "last_name" }
  /// Returns JSON like { "ok": true } on success.
  Future<Map<String, dynamic>> updateUserProfile(String userId, String firstName, String lastName) async {
    final encodedUserId = Uri.encodeComponent(userId);
    final uri = Uri.parse('$baseUrl/accounts/profiles/$encodedUserId');
    final body = {'first_name': firstName, 'last_name': lastName};

    final response = await httpClient.put(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to update user profile. Status code: ${response.statusCode}, body: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Corresponds to: GET /accounts/projects
  /// Returns JSON like { "projects": [...] } on success.
  Future<List<Map<String, dynamic>>> listProjects() async {
    final uri = Uri.parse('$baseUrl/accounts/projects');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to list projects. Status code: ${response.statusCode}, body: ${response.body}');
    }
    return (jsonDecode(response.body)["projects"] as List).whereType<Map<String, dynamic>>().toList();
  }

  /// Corresponds to: GET /accounts/projects/{project_id}
  /// Returns a role
  Future<ProjectRoleInfo> getProjectRole(String projectId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/role');
    final response = await httpClient.get(uri);

    if (response.statusCode == 403) {
      throw ForbiddenException('User does not have access to this project. Status code: ${response.statusCode}, body: ${response.body}');
    }

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to get project role. Status code: ${response.statusCode}, body: ${response.body}');
    }

    return ProjectRoleInfo.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<bool> canCreateRooms(String projectId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/role');
    final response = await httpClient.get(uri);

    if (response.statusCode == 403) {
      throw ForbiddenException('User does not have access to this project. Status code: ${response.statusCode}, body: ${response.body}');
    }

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to create room. Status code: ${response.statusCode}, body: ${response.body}');
    }
    final canCreateRooms = (jsonDecode(response.body) as Map<String, dynamic>)["can_create_rooms"] ?? false;

    return canCreateRooms;
  }

  Future<bool> canCreateAgents(String projectId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/role');
    final response = await httpClient.get(uri);

    if (response.statusCode == 403) {
      throw ForbiddenException('User does not have access to this project. Status code: ${response.statusCode}, body: ${response.body}');
    }

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to check agent creation permission. Status code: ${response.statusCode}, body: ${response.body}');
    }
    final canCreateAgents = (jsonDecode(response.body) as Map<String, dynamic>)["can_create_agents"] ?? false;

    return canCreateAgents;
  }

  Future<bool> canUseLlmProxy(String projectId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/role');
    final response = await httpClient.get(uri);

    if (response.statusCode == 403) {
      throw ForbiddenException('User does not have access to this project. Status code: ${response.statusCode}, body: ${response.body}');
    }

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to check llm proxy access. Status code: ${response.statusCode}, body: ${response.body}');
    }
    final canUseLlmProxy = (jsonDecode(response.body) as Map<String, dynamic>)["can_use_llm_proxy"] ?? false;

    return canUseLlmProxy;
  }

  Future<List<Map<String, dynamic>>> getCurrentUserLlmProxyUsage(
    String projectId, {
    DateTime? start,
    DateTime? end,
    String? interval,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/llm-proxy/usage');

    final queryParameters = <String, String>{
      if (start != null) "start": start.toIso8601String(),
      if (end != null) "end": end.toIso8601String(),
      "interval": ?interval,
    };

    final response = await httpClient.get(uri.replace(queryParameters: queryParameters.isEmpty ? null : queryParameters));

    if (response.statusCode == 403) {
      throw ForbiddenException(
        'User does not have LLM proxy access to this project. Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to retrieve current user LLM proxy usage. Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data["usage"] as List<dynamic>? ?? [];
    return list.whereType<Map<String, dynamic>>().toList();
  }

  /// Corresponds to: GET /accounts/projects
  /// Returns JSON like { "projects": [...] } on success.
  Future<Map<String, dynamic>> getProject(String projectId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to get project. Status code: ${response.statusCode}, body: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Corresponds to: GET /accounts/projects/by-key/{project_key}
  /// Returns the project JSON on success.
  Future<Map<String, dynamic>> getProjectByKey(String projectKey) async {
    final encodedProjectKey = Uri.encodeComponent(projectKey);
    final uri = Uri.parse('$baseUrl/accounts/projects/by-key/$encodedProjectKey');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to get project by key. Status code: ${response.statusCode}, body: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Corresponds to: POST /accounts/projects/{project_id}/api-keys
  /// Body: { "name": "", "description": "" }
  /// Returns an Api Key.
  Future<ApiKeyInfo> createApiKey(String projectId, String name, String description) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/api-keys');
    final body = {'name': name, 'description': description};

    final response = await httpClient.post(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to create project API key. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return ApiKeyInfo.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Corresponds to: DELETE /accounts/projects/{project_id}/api-keys/{token_id}
  /// Returns 204 No Content on success (no JSON body).
  Future<void> deleteApiKey(String projectId, String tokenId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedTokenId = Uri.encodeComponent(tokenId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/api-keys/$encodedTokenId');
    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to delete project API key. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    // 204 No Content -> no need to parse response body.
    return;
  }

  /// Corresponds to: GET /accounts/projects/{project_id}/api-keys
  /// Returns a JSON dict like: { "tokens": [ { ... }, ... ] }.
  Future<MeshagentApiKeysPage> listApiKeysPage(String projectId, {int count = 100, int offset = 0}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/api-keys',
    ).replace(queryParameters: {'count': '$count', 'offset': '$offset'});
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list project API keys. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return MeshagentApiKeysPage.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<Map<String, dynamic>>> listApiKeys(String projectId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/api-keys');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list project API keys. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['keys'] as List<dynamic>? ?? [];
    return list.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
  }

  // In Meshagent
  /// GET /accounts/projects/{project_id}/sessions
  /// Returns JSON: { "sessions": [ { "room_name", "started_at", "is_active" }, ... ] }
  Future<List<RoomSession>> listActiveSessions(String projectId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/sessions/active');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list active sessions. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['sessions'] as List<dynamic>? ?? [];

    return list.whereType<Map<String, dynamic>>().map(RoomSession.fromJson).toList();
  }

  /// Corresponds to: GET /accounts/projects/{project_id}/sessions
  /// Returns a JSON dict: { "sessions": [...] }
  Future<List<RoomSession>> listRecentSessions(String projectId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/sessions');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list recent sessions. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['sessions'] as List<dynamic>? ?? [];
    return list.whereType<Map<String, dynamic>>().map(RoomSession.fromJson).toList();
  }

  Future<List<RoomSession>> listActiveAgentSessions(String projectId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/agents/sessions/active');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list active agent sessions. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['sessions'] as List<dynamic>? ?? [];

    return list.whereType<Map<String, dynamic>>().map(RoomSession.fromJson).toList();
  }

  Future<List<RoomSession>> listRecentAgentSessions(String projectId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/agents/sessions');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list recent agent sessions. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['sessions'] as List<dynamic>? ?? [];
    return list.whereType<Map<String, dynamic>>().map(RoomSession.fromJson).toList();
  }

  Future<String> getCreditsCheckoutUrl(String projectId, String successUrl, String cancelUrl, double quantity) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/credits');
    final body = {"quantity": quantity, "success_url": successUrl, "cancel_url": cancelUrl};
    final response = await httpClient.post(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to get session. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    return jsonDecode(response.body)["checkout_url"];
  }

  Future<String> getCheckoutUrl(String projectId, String successUrl, String cancelUrl) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/subscription');
    final body = {"success_url": successUrl, "cancel_url": cancelUrl};
    final response = await httpClient.post(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to get session. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    return jsonDecode(response.body)["checkout_url"];
  }

  /// Corresponds to: GET /accounts/projects/{project_id}/sessions/{session_id}
  /// Returns a JSON dict: {"id","room_name","created_at"}
  Future<Map<String, dynamic>> getSession(String projectId, String sessionId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedSessionId = Uri.encodeComponent(sessionId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/sessions/$encodedSessionId');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to get session. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    return jsonDecode(response.body);
  }

  Future<Map<String, num>> getSessionParticipantCounts(String projectId, String sessionId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedSessionId = Uri.encodeComponent(sessionId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/sessions/$encodedSessionId/participants');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to get session participant counts. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final participants = data['participants'] as Map<String, dynamic>? ?? {};
    return {
      for (final entry in participants.entries)
        if (entry.value is num) entry.key: entry.value as num,
    };
  }

  /// Corresponds to: POST /accounts/projects/{project_id}/sessions/{session_id}/terminate
  Future<void> terminate({required String projectId, required String sessionId}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedSessionId = Uri.encodeComponent(sessionId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/sessions/$encodedSessionId/terminate');
    final response = await httpClient.post(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to terminate session. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  /// Corresponds to: GET /accounts/projects/{project_id}/sessions/{session_id}
  /// Returns a JSON dict: {"id","room_name","created_at"}
  Future<Map<String, dynamic>> getSubscription(String projectId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/subscription');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to get session. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return jsonDecode(response.body);
  }

  /// Corresponds to: GET /accounts/projects/{project_id}/sessions/{session_id}/events
  /// Returns a JSON dict: { "events": [...] }
  Future<List<Map<String, dynamic>>> listSessionEvents(String projectId, String sessionId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedSessionId = Uri.encodeComponent(sessionId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/sessions/$encodedSessionId/events');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list session events. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return (jsonDecode(response.body)["events"] as List).whereType<Map<String, dynamic>>().toList();
  }

  /// Corresponds to: GET /accounts/projects/{project_id}/sessions/{session_id}/spans
  /// Returns a JSON dict: { "spans": [...] }
  Future<List<Map<String, dynamic>>> listSessionSpans(String projectId, String sessionId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedSessionId = Uri.encodeComponent(sessionId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/sessions/$encodedSessionId/spans');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list session spans. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return (jsonDecode(response.body)["spans"] as List).whereType<Map<String, dynamic>>().toList();
  }

  /// Corresponds to: GET /accounts/projects/{project_id}/sessions/{session_id}/spans
  /// Returns a JSON dict: { "spans": [...] }
  Future<List<Map<String, dynamic>>> listSessionMetrics(String projectId, String sessionId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedSessionId = Uri.encodeComponent(sessionId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/sessions/$encodedSessionId/metrics');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list session metrics. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return (jsonDecode(response.body)["metrics"] as List).whereType<Map<String, dynamic>>().toList();
  }

  /// Corresponds to: POST /accounts/projects/{project_id}/webhooks
  /// Body: { "name", "description", "url", "events" }
  /// Returns the JSON object the server responds with (could be empty or the new resource data).
  Future<Map<String, dynamic>> createWebhook(
    String projectId, {
    required String name,
    required String url,
    required List<String> events,
    String description = '',
    String? action,
    String? payload,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/webhooks');
    final body = {'name': name, 'description': description, 'url': url, 'events': events, 'payload': payload, 'action': action};
    final response = await httpClient.post(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to create project webhook. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Corresponds to: PUT /accounts/projects/{project_id}/webhooks/{webhook_id}
  /// Body: { "name", "description", "url", "events" }
  /// Returns the updated resource JSON or an empty object (depends on your server).
  Future<Map<String, dynamic>> updateWebhook(
    String projectId,
    String webhookId, {
    required String name,
    required String url,
    required List<String> events,
    String description = '',
    String? action,
    String? payload,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedWebhookId = Uri.encodeComponent(webhookId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/webhooks/$encodedWebhookId');
    final body = {'name': name, 'description': description, 'url': url, 'events': events, 'payload': payload, 'action': action};

    final response = await httpClient.put(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to update project webhook. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Corresponds to: GET /accounts/projects/{project_id}/webhooks
  /// Returns a JSON dict like { "webhooks": [ { ... }, ... ] }.
  Future<MeshagentWebhooksPage> listWebhooksPage(String projectId, {int count = 100, int offset = 0}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/webhooks',
    ).replace(queryParameters: {'count': '$count', 'offset': '$offset'});
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list project webhooks. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    return MeshagentWebhooksPage.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<Map<String, dynamic>>> listWebhooks(String projectId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/webhooks');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list project webhooks. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['webhooks'] as List<dynamic>? ?? [];
    return list.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
  }

  /// Corresponds to: DELETE /accounts/projects/{project_id}/webhooks/{webhook_id}
  /// Typically returns 200 or 204 on success (no JSON body).
  Future<void> deleteWebhook(String projectId, String webhookId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedWebhookId = Uri.encodeComponent(webhookId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/webhooks/$encodedWebhookId');
    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to delete project webhook. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    // 200 or 204 on success, no body to parse
  }

  // -------------------------------
  // Room Grant methods
  // -------------------------------

  /// POST /accounts/projects/{project_id}/room-grants
  /// Body: { "room_name", "user_id", "permissions" }
  /// Returns {} on success.
  Future<void> createRoomGrant({
    required String projectId,
    required String roomId,
    required String userId,
    required ApiScope permissions,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/room-grants');
    final body = {'room_id': roomId, 'user_id': userId, 'permissions': permissions.toJson()};
    final response = await httpClient.post(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to create room grant. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  /// POST /accounts/projects/{project_id}/room-grants
  /// Body: { "room_name", "user_id", "permissions" }
  /// Returns {} on success.
  Future<void> createRoomGrantByEmail({
    required String projectId,
    required String roomId,
    required String email,
    required ApiScope permissions,
    Uri? inviteRedirectUrl,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/room-grants');
    final body = {
      'room_id': roomId,
      'email': email,
      'permissions': permissions.toJson(),
      'invite_redirect_url': ?inviteRedirectUrl?.toString(),
    };
    final response = await httpClient.post(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to create room grant. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  /// PUT /accounts/projects/{project_id}/room-grants/{grant_id}
  /// Body: { "room_name", "user_id", "permissions" }
  /// Note: Many servers ignore {grant_id} and update by (project_id, room_name, user_id).
  Future<void> updateRoomGrant({
    required String projectId,
    required String roomId,
    required String userId,
    required ApiScope permissions,
    String? grantId,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final gid = Uri.encodeComponent(grantId ?? 'unused');
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/room-grants/$gid');
    final body = {'room_id': roomId, 'user_id': userId, 'permissions': permissions.toJson()};
    final response = await httpClient.put(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to update room grant. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  /// DELETE /accounts/projects/{project_id}/room-grants/{room_name}/{user_id}
  /// Returns {} on success.
  Future<void> deleteRoomGrant({required String projectId, required String roomId, required String userId}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRoomId = Uri.encodeComponent(roomId);
    final encodedUserId = Uri.encodeComponent(userId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/room-grants/$encodedRoomId/$encodedUserId');
    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to delete room grant. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  /// GET /accounts/projects/{project_id}/room-grants/{room_name}/{user_id}
  /// Returns a ProjectRoomGrant.
  Future<ProjectRoomGrant> getRoomGrant({required String projectId, required String roomId, required String userId}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRoomId = Uri.encodeComponent(roomId);
    final encodedUserId = Uri.encodeComponent(userId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/room-grants/$encodedRoomId/$encodedUserId');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to get room grant. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return ProjectRoomGrant.fromJson(data);
  }

  /// GET /accounts/projects/{project_id}/rooms?limit=&offset=&order_by=&filter=
  Future<List<Room>> listRooms({
    required String projectId,
    int limit = 100,
    int offset = 0,
    String orderBy = 'room_name',
    String? filter,
  }) async {
    final page = await listRoomsPage(projectId: projectId, limit: limit, offset: offset, orderBy: orderBy, filter: filter);
    return page.rooms;
  }

  /// GET /accounts/projects/{project_id}/rooms?limit=&offset=&order_by=&filter=
  Future<RoomsPage> listRoomsPage({
    required String projectId,
    int limit = 100,
    int offset = 0,
    String orderBy = 'room_name',
    String? filter,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final queryParameters = {'limit': '$limit', 'offset': '$offset', 'order_by': orderBy};
    if (filter != null) {
      queryParameters['filter'] = filter;
    }
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/rooms').replace(queryParameters: queryParameters);
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list rooms. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return RoomsPage.fromJson(data);
  }

  /// GET /accounts/projects/{project_id}/room-grants?limit=&offset=&order_by=
  Future<List<ProjectRoomGrant>> listRoomGrants({
    required String projectId,
    int limit = 50,
    int offset = 0,
    String orderBy = 'room_name',
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/room-grants',
    ).replace(queryParameters: {'limit': '$limit', 'offset': '$offset', 'order_by': orderBy});
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list room grants. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['room_grants'] as List<dynamic>? ?? [];
    return list.whereType<Map<String, dynamic>>().map(ProjectRoomGrant.fromJson).toList();
  }

  /// GET /accounts/projects/{project_id}/room-grants/by-user/{user_id}?limit=&offset=&order_by=
  Future<List<ProjectRoomGrant>> listRoomGrantsByUser({
    required String projectId,
    required String userId,
    int limit = 100,
    int offset = 0,
    String orderBy = 'room_name',
    String? filter,
  }) async {
    final page = await listRoomGrantsByUserPage(
      projectId: projectId,
      userId: userId,
      limit: limit,
      offset: offset,
      orderBy: orderBy,
      filter: filter,
    );
    return page.roomGrants;
  }

  /// GET /accounts/projects/{project_id}/room-grants/by-user/{user_id}?limit=&offset=&order_by=&filter=
  Future<RoomGrantsPage> listRoomGrantsByUserPage({
    required String projectId,
    required String userId,
    int limit = 100,
    int offset = 0,
    String orderBy = 'room_name',
    String? filter,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedUserId = Uri.encodeComponent(userId);
    final queryParameters = {'limit': '$limit', 'offset': '$offset', 'order_by': orderBy};
    if (filter != null) {
      queryParameters['filter'] = filter;
    }
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/room-grants/by-user/$encodedUserId',
    ).replace(queryParameters: queryParameters);
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list room grants by user. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return RoomGrantsPage.fromJson(data);
  }

  /// GET /accounts/projects/{project_id}/room-grants/by-room/{room_name}?limit=&offset=&order_by=
  Future<List<ProjectRoomGrant>> listRoomGrantsByRoom({
    required String projectId,
    required String roomName,
    int limit = 50,
    int offset = 0,
    String orderBy = 'user_id',
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRoomName = Uri.encodeComponent(roomName);
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/room-grants/by-room/$encodedRoomName',
    ).replace(queryParameters: {'limit': '$limit', 'offset': '$offset', 'order_by': orderBy});

    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list room grants by room. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['room_grants'] as List<dynamic>? ?? [];
    return list.whereType<Map<String, dynamic>>().map(ProjectRoomGrant.fromJson).toList();
  }

  /// GET /accounts/projects/{project_id}/room-grants/by-room?limit=&offset=
  Future<List<ProjectRoomGrantCount>> listUniqueRoomsWithGrants({required String projectId, int limit = 50, int offset = 0}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/room-grants/by-room',
    ).replace(queryParameters: {'limit': '$limit', 'offset': '$offset'});
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list unique rooms with grants. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['rooms'] as List<dynamic>? ?? [];
    return list.whereType<Map<String, dynamic>>().map(ProjectRoomGrantCount.fromJson).toList();
  }

  /// GET /accounts/projects/{project_id}/room-grants/by-user?limit=&offset=
  Future<ProjectUserGrantCountsPage> listUniqueUsersWithGrantsPage({
    required String projectId,
    int limit = 100,
    int offset = 0,
    String? filter,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final query = <String, String>{'limit': '$limit', 'offset': '$offset'};
    if (filter != null && filter.trim().isNotEmpty) query['filter'] = filter;
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/room-grants/by-user').replace(queryParameters: query);
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list unique users with grants. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return ProjectUserGrantCountsPage.fromJson(data);
  }

  Future<List<ProjectUserGrantCount>> listUniqueUsersWithGrants({
    required String projectId,
    int limit = 100,
    int offset = 0,
    String? filter,
  }) async {
    final page = await listUniqueUsersWithGrantsPage(projectId: projectId, limit: limit, offset: offset, filter: filter);
    return page.users;
  }

  /// --------------------------------
  /// Rooms
  /// --------------------------------

  /// POST /accounts/projects/{project_id}/rooms
  /// Body: { "name": "name", "if_not_exists": bool }
  /// Returns a Room on success.
  Future<Room> createRoom({
    required String projectId,
    required String name,
    bool ifNotExists = false,
    Map<String, dynamic>? metadata,
    Map<String, String>? annotations,
    Map<String, ApiScope>? permissions,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/rooms');
    final body = _jsonMapWithoutNulls({
      'name': name,
      'if_not_exists': ifNotExists,
      'metadata': metadata,
      'annotations': annotations,
      'permissions': permissions?.map((key, value) => MapEntry(key, value.toJson())),
    });
    final response = await httpClient.post(uri, body: jsonEncode(body));

    if (response.statusCode == 409) {
      throw NameInUseException("The room name is already in use");
    } else if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to create room. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return Room.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// GET /accounts/projects/{project_id}/rooms/{room_name}
  /// Returns a Room (404 -> NotFoundException).
  Future<Room> getRoom({required String projectId, required String name}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRoomName = Uri.encodeComponent(name);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/rooms/$encodedRoomName');
    final response = await httpClient.get(uri);

    if (response.statusCode == 404) {
      throw NotFoundException('room not found');
    }

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to get room. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return Room.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// PUT /accounts/projects/{project_id}/rooms/{room_id}
  /// Body: { "name": "new name" }
  Future<void> updateRoom({
    required String projectId,
    required String roomId,
    required String name,
    Map<String, dynamic>? metadata,
    Map<String, String>? annotations,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRoomId = Uri.encodeComponent(roomId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/rooms/$encodedRoomId');
    final response = await httpClient.put(uri, body: jsonEncode({'name': name, 'metadata': metadata, 'annotations': annotations}));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to update room. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  /// DELETE /accounts/projects/{project_id}/rooms/{room_id}
  Future<void> deleteRoom({required String projectId, required String roomId}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRoomId = Uri.encodeComponent(roomId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/rooms/$encodedRoomId');
    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to delete room. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<ManagedAgent> createAgent({
    required String projectId,
    required Map<String, dynamic> configuration,
    bool ifNotExists = false,
    Map<String, ManagedAgentGrant>? permissions,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/agents');
    final body = {
      'configuration': _jsonMapWithoutNulls(configuration),
      'if_not_exists': ifNotExists,
      if (permissions != null) 'permissions': permissions.map((key, value) => MapEntry(key, value.toJson())),
    };
    final response = await httpClient.post(uri, body: jsonEncode(body));

    if (response.statusCode == 409) {
      throw NameInUseException("The agent name is already in use");
    } else if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to create agent. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return ManagedAgent.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<ManagedAgent> getAgent({required String projectId, required String name}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedAgentName = Uri.encodeComponent(name);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/agents/$encodedAgentName');
    final response = await httpClient.get(uri);

    if (response.statusCode == 404) {
      throw NotFoundException('agent not found');
    }

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to get agent. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return ManagedAgent.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<AgentsPage> listAgentsPage({
    required String projectId,
    int limit = 100,
    int offset = 0,
    String orderBy = 'agent_name',
    String? filter,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final queryParameters = {'limit': '$limit', 'offset': '$offset', 'order_by': orderBy};
    if (filter != null) {
      queryParameters['filter'] = filter;
    }
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/agents').replace(queryParameters: queryParameters);
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list agents. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return AgentsPage.fromJson(data);
  }

  Future<List<ManagedAgent>> listAgents({
    required String projectId,
    int limit = 100,
    int offset = 0,
    String orderBy = 'agent_name',
    String? filter,
  }) async {
    final page = await listAgentsPage(projectId: projectId, limit: limit, offset: offset, orderBy: orderBy, filter: filter);
    return page.agents;
  }

  Future<void> updateAgent({required String projectId, required String agentId, required Map<String, dynamic> configuration}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedAgentId = Uri.encodeComponent(agentId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/agents/$encodedAgentId');
    final response = await httpClient.put(uri, body: jsonEncode({'configuration': _jsonMapWithoutNulls(configuration)}));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to update agent. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<void> deleteAgent({required String projectId, required String agentId}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedAgentId = Uri.encodeComponent(agentId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/agents/$encodedAgentId');
    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to delete agent. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<void> createAgentGrant({
    required String projectId,
    required String agentId,
    required String userId,
    ManagedAgentGrant permissions = const ManagedAgentGrant(),
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/agent-grants');
    final body = {'agent_id': agentId, 'user_id': userId, 'permissions': permissions.toJson()};
    final response = await httpClient.post(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to create agent grant. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<void> createAgentGrantByEmail({
    required String projectId,
    required String agentId,
    required String email,
    ManagedAgentGrant permissions = const ManagedAgentGrant(),
    Uri? inviteRedirectUrl,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/agent-grants');
    final body = {
      'agent_id': agentId,
      'email': email,
      'permissions': permissions.toJson(),
      'invite_redirect_url': ?inviteRedirectUrl?.toString(),
    };
    final response = await httpClient.post(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to create agent grant. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<void> updateAgentGrant({
    required String projectId,
    required String agentId,
    required String userId,
    ManagedAgentGrant permissions = const ManagedAgentGrant(),
    String? grantId,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final gid = Uri.encodeComponent(grantId ?? 'unused');
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/agent-grants/$gid');
    final body = {'agent_id': agentId, 'user_id': userId, 'permissions': permissions.toJson()};
    final response = await httpClient.put(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to update agent grant. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<void> deleteAgentGrant({required String projectId, required String agentId, required String userId}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedAgentId = Uri.encodeComponent(agentId);
    final encodedUserId = Uri.encodeComponent(userId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/agent-grants/$encodedAgentId/$encodedUserId');
    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to delete agent grant. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<void> createAgentRoomGrant({
    required String projectId,
    required String agentId,
    required String roomId,
    AgentRoomGrant? permissions,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/agent-room-grants');
    final effectivePermissions = permissions ?? AgentRoomGrant.fromApiScope(ApiScope.agentDefault());
    final body = {'agent_id': agentId, 'room_id': roomId, 'permissions': effectivePermissions.toJson()};
    final response = await httpClient.post(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to create agent room grant. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<void> updateAgentRoomGrant({
    required String projectId,
    required String agentId,
    required String roomId,
    AgentRoomGrant? permissions,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedAgentId = Uri.encodeComponent(agentId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/agent-room-grants/$encodedAgentId');
    final body = {'agent_id': agentId, 'room_id': roomId, 'permissions': (permissions ?? AgentRoomGrant()).toJson()};
    final response = await httpClient.put(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to update agent room grant. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<void> deleteAgentRoomGrant({required String projectId, required String agentId, required String roomId}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedAgentId = Uri.encodeComponent(agentId);
    final encodedRoomId = Uri.encodeComponent(roomId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/agent-room-grants/$encodedAgentId/$encodedRoomId');
    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to delete agent room grant. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<List<ProjectAgentRoomGrant>> listAgentRoomGrantsByAgent({
    required String projectId,
    required String agentName,
    int limit = 50,
    int offset = 0,
    String orderBy = 'room_name',
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedAgentName = Uri.encodeComponent(agentName);
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/agent-room-grants/by-agent/$encodedAgentName',
    ).replace(queryParameters: {'limit': '$limit', 'offset': '$offset', 'order_by': orderBy});
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list agent room grants by agent. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['agent_room_grants'] as List<dynamic>? ?? [];
    return list.whereType<Map<String, dynamic>>().map(ProjectAgentRoomGrant.fromJson).toList();
  }

  Future<List<ProjectAgentRoomGrant>> listAgentRoomGrantsByRoom({
    required String projectId,
    required String roomName,
    int limit = 50,
    int offset = 0,
    String orderBy = 'agent_name',
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRoomName = Uri.encodeComponent(roomName);
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/agent-room-grants/by-room/$encodedRoomName',
    ).replace(queryParameters: {'limit': '$limit', 'offset': '$offset', 'order_by': orderBy});
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list agent room grants by room. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['agent_room_grants'] as List<dynamic>? ?? [];
    return list.whereType<Map<String, dynamic>>().map(ProjectAgentRoomGrant.fromJson).toList();
  }

  Future<List<ProjectAgentGrant>> listAgentGrantsByAgent({
    required String projectId,
    required String agentName,
    int limit = 50,
    int offset = 0,
    String orderBy = 'user_id',
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedAgentName = Uri.encodeComponent(agentName);
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/agent-grants/by-agent/$encodedAgentName',
    ).replace(queryParameters: {'limit': '$limit', 'offset': '$offset', 'order_by': orderBy});
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list agent grants by agent. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['agent_grants'] as List<dynamic>? ?? [];
    return list.whereType<Map<String, dynamic>>().map(ProjectAgentGrant.fromJson).toList();
  }

  Future<ProjectMembersPage> listAgentMembersByAgent({
    required String projectId,
    required String agentName,
    int limit = 50,
    int offset = 0,
    String? filter,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedAgentName = Uri.encodeComponent(agentName);
    final queryParameters = {'limit': '$limit', 'offset': '$offset'};
    if (filter != null) {
      queryParameters['filter'] = filter;
    }
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/members/by-agent/$encodedAgentName',
    ).replace(queryParameters: queryParameters);
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list agent members. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return ProjectMembersPage.fromJson(data);
  }

  Future<AgentGrantsPage> listAgentGrantsByUserPage({
    required String projectId,
    required String userId,
    int limit = 100,
    int offset = 0,
    String orderBy = 'agent_name',
    String? filter,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedUserId = Uri.encodeComponent(userId);
    final queryParameters = {'limit': '$limit', 'offset': '$offset', 'order_by': orderBy};
    if (filter != null) {
      queryParameters['filter'] = filter;
    }
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/agent-grants/by-user/$encodedUserId',
    ).replace(queryParameters: queryParameters);
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list agent grants by user. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return AgentGrantsPage.fromJson(data);
  }

  Future<AgentConnectionInfo> connectAgent({required String projectId, required String agentName}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedAgentName = Uri.encodeComponent(agentName);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/agents/$encodedAgentName/connect');
    final response = await httpClient.post(uri, body: jsonEncode({}));

    if (response.statusCode >= 400) {
      if (response.statusCode == 404) {
        throw NotFoundException('Agent not found');
      }

      throw MeshagentException(
        'Failed to connect agent. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return AgentConnectionInfo.fromJson(jsonDecode(response.body));
  }

  /// POST /accounts/projects/{project_id}/rooms/{room_name}/connect
  /// Body: {}
  /// Returns { "jwt", "room_name", "project_id", "room_url" } on success.
  Future<RoomConnectionInfo> connectRoom({required String projectId, required String roomName, String? client}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRoomName = Uri.encodeComponent(roomName);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/rooms/$encodedRoomName/connect');
    final response = await httpClient.post(uri, body: jsonEncode({"client": client}));

    if (response.statusCode >= 400) {
      if (response.statusCode == 404) {
        throw NotFoundException('Room not found');
      }

      throw MeshagentException(
        'Failed to connect room. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return RoomConnectionInfo.fromJson(jsonDecode(response.body));
  }

  /// GET /oauth/provider/list
  /// Returns a list of OAuth providers.
  Future<List<AuthProvider>> listOAuthProviders() async {
    final uri = Uri.parse('$baseUrl/oauth/provider/list');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list OAuth providers. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final list = decoded['providers'] as List<dynamic>? ?? const [];
    return list.whereType<Map<String, dynamic>>().map(AuthProvider.fromJson).toList();
  }

  /// POST /accounts/projects/{project_id}/oauth/clients
  /// Body: { grant_types, response_types, redirect_uris, scope, metadata? }
  /// Returns the newly created OAuthClient (often includes client_secret).
  Future<OAuthClient> createOAuthClient(
    String projectId, {
    required List<String> grantTypes,
    required List<String> responseTypes,
    required List<String> redirectUris,
    required String scope,
    Map<String, dynamic>? metadata,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/oauth/clients');
    final body = <String, dynamic>{
      'grant_types': grantTypes,
      'response_types': responseTypes,
      'redirect_uris': redirectUris,
      'scope': scope,
      'metadata': metadata ?? <String, dynamic>{},
    };

    final response = await httpClient.post(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to create OAuth client. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    return OAuthClient.fromJson(jsonDecode(response.body)["client"]);
  }

  /// PUT /accounts/projects/{project_id}/oauth/clients/{client_id}
  /// Body: any subset of { grant_types, response_types, redirect_uris, scope, metadata }
  /// Returns a small status JSON (e.g., { "ok": true }).
  Future<Map<String, dynamic>> updateOAuthClient(
    String projectId,
    String clientId, {
    List<String>? grantTypes,
    List<String>? responseTypes,
    List<String>? redirectUris,
    String? scope,
    Map<String, dynamic>? metadata,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedClientId = Uri.encodeComponent(clientId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/oauth/clients/$encodedClientId');

    final body = <String, dynamic>{};
    if (grantTypes != null) body['grant_types'] = grantTypes;
    if (responseTypes != null) body['response_types'] = responseTypes;
    if (redirectUris != null) body['redirect_uris'] = redirectUris;
    if (scope != null) body['scope'] = scope;
    if (metadata != null) body['metadata'] = metadata;

    final response = await httpClient.put(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to update OAuth client. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// GET /accounts/projects/{project_id}/oauth/clients
  /// Returns a list of OAuthClient (no secrets).
  Future<OAuthClientsPage> listOAuthClientsPage(String projectId, {int count = 100, int offset = 0, String? filter}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final query = <String, String>{'count': '$count', 'offset': '$offset'};
    if (filter != null && filter.trim().isNotEmpty) query['filter'] = filter;
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/oauth/clients').replace(queryParameters: query);
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list OAuth clients. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return OAuthClientsPage.fromJson(decoded);
  }

  Future<List<OAuthClient>> listOAuthClients(String projectId, {int count = 100, int offset = 0, String? filter}) async {
    final page = await listOAuthClientsPage(projectId, count: count, offset: offset, filter: filter);
    return page.clients;
  }

  /// GET /accounts/projects/{project_id}/oauth/clients/{client_id}
  /// Returns one OAuthClient (no secret). 404 -> NotFoundException.
  Future<OAuthClient> getOAuthClient(String projectId, String clientId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedClientId = Uri.encodeComponent(clientId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/oauth/clients/$encodedClientId');

    final response = await httpClient.get(uri);

    if (response.statusCode == 404) {
      throw NotFoundException('oauth client not found');
    }

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to get OAuth client. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return OAuthClient.fromJson(jsonDecode(response.body));
  }

  /// DELETE /accounts/projects/{project_id}/oauth/clients/{client_id}
  /// Returns 204 No Content on success.
  Future<void> deleteOAuthClient(String projectId, String clientId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedClientId = Uri.encodeComponent(clientId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/oauth/clients/$encodedClientId');
    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to delete OAuth client. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<String> createProjectExternalOAuthRegistration({
    required String projectId,
    required OAuthClientConfig oauth,
    required String clientId,
    String? clientSecret,
    String? delegatedTo,
    ConnectorRef? connector,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/external-oauth');
    final body = <String, dynamic>{
      'oauth': oauth.toJson(),
      'client_id': clientId,
      'client_secret': ?clientSecret,
      'delegated_to': ?delegatedTo,
      'connector': ?connector?.toJson(),
    };
    final response = await httpClient.post(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to create project external oauth registration. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return (jsonDecode(response.body) as Map<String, dynamic>)['id'] as String;
  }

  Future<void> updateProjectExternalOAuthRegistration({
    required String projectId,
    required String registrationId,
    required OAuthClientConfig oauth,
    required String clientId,
    String? clientSecret,
    String? delegatedTo,
    ConnectorRef? connector,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRegistrationId = Uri.encodeComponent(registrationId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/external-oauth/$encodedRegistrationId');
    final body = <String, dynamic>{
      'oauth': oauth.toJson(),
      'client_id': clientId,
      'client_secret': ?clientSecret,
      'delegated_to': ?delegatedTo,
      'connector': ?connector?.toJson(),
    };
    final response = await httpClient.put(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to update project external oauth registration. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<List<ExternalOAuthClientRegistration>> listProjectExternalOAuthRegistrations({
    required String projectId,
    String? delegatedTo,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final query = <String, String>{};
    if (delegatedTo != null) query['delegated_to'] = delegatedTo;
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/external-oauth',
    ).replace(queryParameters: query.isEmpty ? null : query);
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list project external oauth registrations. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final registrations = decoded['registrations'] as List<dynamic>? ?? const [];
    return registrations.whereType<Map<String, dynamic>>().map(ExternalOAuthClientRegistration.fromJson).toList();
  }

  Future<void> deleteProjectExternalOAuthRegistration({
    required String projectId,
    required String registrationId,
    String? delegatedTo,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRegistrationId = Uri.encodeComponent(registrationId);
    final query = <String, String>{};
    if (delegatedTo != null) query['delegated_to'] = delegatedTo;
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/external-oauth/$encodedRegistrationId',
    ).replace(queryParameters: query.isEmpty ? null : query);
    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to delete project external oauth registration. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<String> createRoomExternalOAuthRegistration({
    required String projectId,
    required String roomName,
    required OAuthClientConfig oauth,
    required String clientId,
    String? clientSecret,
    String? delegatedTo,
    ConnectorRef? connector,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRoomName = Uri.encodeComponent(roomName);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/rooms/$encodedRoomName/external-oauth');
    final body = <String, dynamic>{
      'oauth': oauth.toJson(),
      'client_id': clientId,
      'client_secret': ?clientSecret,
      'delegated_to': ?delegatedTo,
      'connector': ?connector?.toJson(),
    };
    final response = await httpClient.post(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to create room external oauth registration. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return (jsonDecode(response.body) as Map<String, dynamic>)['id'] as String;
  }

  Future<void> updateRoomExternalOAuthRegistration({
    required String projectId,
    required String roomName,
    required String registrationId,
    required OAuthClientConfig oauth,
    required String clientId,
    String? clientSecret,
    String? delegatedTo,
    ConnectorRef? connector,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRoomName = Uri.encodeComponent(roomName);
    final encodedRegistrationId = Uri.encodeComponent(registrationId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/rooms/$encodedRoomName/external-oauth/$encodedRegistrationId');
    final body = <String, dynamic>{
      'oauth': oauth.toJson(),
      'client_id': clientId,
      'client_secret': ?clientSecret,
      'delegated_to': ?delegatedTo,
      'connector': ?connector?.toJson(),
    };
    final response = await httpClient.put(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to update room external oauth registration. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<List<ExternalOAuthClientRegistration>> listRoomExternalOAuthRegistrations({
    required String projectId,
    required String roomName,
    String? delegatedTo,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRoomName = Uri.encodeComponent(roomName);
    final query = <String, String>{};
    if (delegatedTo != null) query['delegated_to'] = delegatedTo;
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/rooms/$encodedRoomName/external-oauth',
    ).replace(queryParameters: query.isEmpty ? null : query);
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list room external oauth registrations. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final registrations = decoded['registrations'] as List<dynamic>? ?? const [];
    return registrations.whereType<Map<String, dynamic>>().map(ExternalOAuthClientRegistration.fromJson).toList();
  }

  Future<void> deleteRoomExternalOAuthRegistration({
    required String projectId,
    required String roomName,
    required String registrationId,
    String? delegatedTo,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRoomName = Uri.encodeComponent(roomName);
    final encodedRegistrationId = Uri.encodeComponent(registrationId);
    final query = <String, String>{};
    if (delegatedTo != null) query['delegated_to'] = delegatedTo;
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/rooms/$encodedRoomName/external-oauth/$encodedRegistrationId',
    ).replace(queryParameters: query.isEmpty ? null : query);
    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to delete room external oauth registration. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  /// POST /accounts/projects/{project_id}/rooms/{room_name}/scheduled-tasks
  /// Returns { "task_id" }
  Future<String> createScheduledTask({required String projectId, required String roomName, required ScheduledTaskSpec spec}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRoomName = Uri.encodeComponent(roomName);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/rooms/$encodedRoomName/scheduled-tasks');
    final body = _CreateScheduledTaskRequest(spec: spec).toJson();
    final resp = await httpClient.post(uri, body: jsonEncode(body));

    if (resp.statusCode >= 400) {
      // mirror your python client’s "ensure_success" style
      throw MeshagentException('Failed to create scheduled task. Status code: ${resp.statusCode}, body: ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final tid = data['task_id'];

    if (tid is! String) {
      throw MeshagentException('Invalid create scheduled task response: missing "task_id"');
    }

    return tid;
  }

  /// PUT /accounts/projects/{project_id}/scheduled-tasks/{task_id}
  Future<void> updateScheduledTask({required String projectId, required String taskId, required ScheduledTaskSpec spec}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedTaskId = Uri.encodeComponent(taskId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/scheduled-tasks/$encodedTaskId');
    final body = _UpdateScheduledTaskRequest(spec: spec).toJson();

    final resp = await httpClient.put(uri, body: jsonEncode(body));

    if (resp.statusCode >= 400) {
      throw MeshagentException('Failed to update scheduled task. Status code: ${resp.statusCode}, body: ${resp.body}');
    }
  }

  /// DELETE /accounts/projects/{project_id}/scheduled-tasks/{task_id}
  /// Returns 204 or {} on success.
  Future<void> deleteScheduledTask({required String projectId, required String taskId}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedTaskId = Uri.encodeComponent(taskId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/scheduled-tasks/$encodedTaskId');

    final resp = await httpClient.delete(uri);

    if (resp.statusCode >= 400) {
      throw MeshagentException('Failed to delete scheduled task. Status code: ${resp.statusCode}, body: ${resp.body}');
    }
  }

  /// GET /accounts/projects/{project_id}/scheduled-tasks?room_id=&task_id=&active=&limit=&offset=
  /// Returns { "tasks": [ ... ] }
  Future<ScheduledTasksPage> listScheduledTasksPage({
    required String projectId,
    String? roomId,
    String? taskId,
    bool? active,
    int limit = 100,
    int offset = 0,
    String? filter,
  }) async {
    final qp = <String, String>{'limit': '$limit', 'offset': '$offset'};
    if (roomId != null) qp['room_id'] = roomId;
    if (taskId != null) qp['task_id'] = taskId;
    if (active != null) qp['active'] = active ? 'true' : 'false';
    if (filter != null && filter.trim().isNotEmpty) qp['filter'] = filter;

    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/scheduled-tasks').replace(queryParameters: qp);

    final resp = await httpClient.get(uri);

    if (resp.statusCode >= 400) {
      throw MeshagentException('Failed to list scheduled tasks. Status code: ${resp.statusCode}, body: ${resp.body}');
    }

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final tasksRaw = decoded['tasks'];

    if (tasksRaw is! List) {
      throw MeshagentException("Invalid scheduled-tasks payload: expected 'tasks' to be a list");
    }

    return ScheduledTasksPage.fromJson(decoded);
  }

  Future<List<ScheduledTask>> listScheduledTasks({
    required String projectId,
    String? roomId,
    String? taskId,
    bool? active,
    int limit = 100,
    int offset = 0,
    String? filter,
  }) async {
    final page = await listScheduledTasksPage(
      projectId: projectId,
      roomId: roomId,
      taskId: taskId,
      active: active,
      limit: limit,
      offset: offset,
      filter: filter,
    );
    return page.tasks;
  }

  Future<ScheduledTaskRunsPage> listScheduledTaskRunsPage({
    required String projectId,
    required String taskId,
    int limit = 100,
    int offset = 0,
  }) async {
    final qp = <String, String>{'limit': '$limit', 'offset': '$offset'};
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedTaskId = Uri.encodeComponent(taskId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/scheduled-tasks/$encodedTaskId/runs').replace(queryParameters: qp);

    final resp = await httpClient.get(uri);

    if (resp.statusCode >= 400) {
      throw MeshagentException('Failed to list scheduled task runs. Status code: ${resp.statusCode}, body: ${resp.body}');
    }

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final runsRaw = decoded['runs'];

    if (runsRaw is! List) {
      throw MeshagentException("Invalid scheduled-task-runs payload: expected 'runs' to be a list");
    }

    return ScheduledTaskRunsPage.fromJson(decoded);
  }

  Future<List<ScheduledTaskRun>> listScheduledTaskRuns({
    required String projectId,
    required String taskId,
    int limit = 100,
    int offset = 0,
  }) async {
    final page = await listScheduledTaskRunsPage(projectId: projectId, taskId: taskId, limit: limit, offset: offset);
    return page.runs;
  }
}

class OAuthClient {
  final String clientId;
  final String? clientSecret; // present on create responses
  final List<String> grantTypes;
  final List<String> responseTypes;
  final List<String> redirectUris;
  final String scope;
  final String projectId;
  final Map<String, dynamic> metadata;

  OAuthClient({
    required this.clientId,
    this.clientSecret,
    required this.grantTypes,
    required this.responseTypes,
    required this.redirectUris,
    required this.scope,
    required this.projectId,
    required this.metadata,
  });

  factory OAuthClient.fromJson(Map<String, dynamic> json) => OAuthClient(
    clientId: json['client_id'] as String,
    clientSecret: json['client_secret'] as String?, // may be absent
    grantTypes: (json['grant_types'] as List?)?.cast<String>() ?? const [],
    responseTypes: (json['response_types'] as List?)?.cast<String>() ?? const [],
    redirectUris: (json['redirect_uris'] as List?)?.cast<String>() ?? const [],
    scope: (json['scope'] as String?) ?? '',
    projectId: (json['project_id'] as String?) ?? '',
    metadata: (json['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
  );

  Map<String, dynamic> toJson() => {
    'client_id': clientId,
    if (clientSecret != null) 'client_secret': clientSecret,
    'grant_types': grantTypes,
    'response_types': responseTypes,
    'redirect_uris': redirectUris,
    'scope': scope,
    'project_id': projectId,
    'metadata': metadata,
  };
}

class OAuthClientsPage {
  final List<OAuthClient> clients;
  final int total;

  OAuthClientsPage({required this.clients, required this.total});

  factory OAuthClientsPage.fromJson(Map<String, dynamic> json) {
    final list = json['clients'] as List<dynamic>? ?? [];
    return OAuthClientsPage(
      clients: list.whereType<Map<String, dynamic>>().map(OAuthClient.fromJson).toList(),
      total: _parseInt(json['total']),
    );
  }
}

int _parseInt(dynamic value) {
  return value is int
      ? value
      : value is num
      ? value.toInt()
      : value is String
      ? int.tryParse(value) ?? 0
      : 0;
}

class Room {
  const Room({required this.name, required this.id, required this.metadata, required this.annotations});

  final String name;
  final String id;
  final Map<String, dynamic> metadata;
  final Map<String, String> annotations;

  static Room fromJson(Map<String, dynamic> json) {
    return Room(
      id: json["id"],
      name: json["name"],
      metadata: (json["metadata"] as Map?)?.cast<String, dynamic>() ?? {},
      annotations: (json["annotations"] as Map?)?.cast<String, String>() ?? {},
    );
  }

  Map<String, dynamic> toJson() => {"name": name, "id": id, "metadata": metadata, "annotations": annotations};
}

class RoomsPage {
  final List<Room> rooms;
  final int total;

  RoomsPage({required this.rooms, required this.total});

  factory RoomsPage.fromJson(Map<String, dynamic> json) {
    final list = json['rooms'] as List<dynamic>? ?? [];
    return RoomsPage(rooms: list.whereType<Map<String, dynamic>>().map(Room.fromJson).toList(), total: _parseInt(json['total']));
  }

  Map<String, dynamic> toJson() => {'rooms': rooms.map((room) => room.toJson()).toList(), 'total': total};
}

class ManagedAgent {
  const ManagedAgent({required this.name, required this.id, required this.configuration});

  final String name;
  final String id;
  final Map<String, dynamic> configuration;

  static ManagedAgent fromJson(Map<String, dynamic> json) {
    return ManagedAgent(id: json["id"], name: json["name"], configuration: (json["configuration"] as Map?)?.cast<String, dynamic>() ?? {});
  }

  Map<String, dynamic> toJson() => {"name": name, "id": id, "configuration": configuration};
}

class AgentsPage {
  final List<ManagedAgent> agents;
  final int total;

  AgentsPage({required this.agents, required this.total});

  factory AgentsPage.fromJson(Map<String, dynamic> json) {
    final list = json['agents'] as List<dynamic>? ?? [];
    return AgentsPage(agents: list.whereType<Map<String, dynamic>>().map(ManagedAgent.fromJson).toList(), total: _parseInt(json['total']));
  }

  Map<String, dynamic> toJson() => {'agents': agents.map((agent) => agent.toJson()).toList(), 'total': total};
}

class ProjectMembersPage {
  final List<Map<String, dynamic>> users;
  final int total;

  ProjectMembersPage({required this.users, required this.total});

  factory ProjectMembersPage.fromJson(Map<String, dynamic> json) {
    final list = json['users'] as List<dynamic>? ?? [];
    return ProjectMembersPage(users: list.whereType<Map<String, dynamic>>().toList(), total: _parseInt(json['total']));
  }
}

class ManagedAgentGrant {
  const ManagedAgentGrant({this.admin = false});

  final bool admin;

  factory ManagedAgentGrant.fromJson(Map<String, dynamic> json) {
    return ManagedAgentGrant(admin: json['admin'] == true);
  }

  Map<String, dynamic> toJson() => {'admin': admin};
}

class ProjectAgentGrant {
  final ManagedAgent agent;
  final String userId;
  final ManagedAgentGrant permissions;

  ProjectAgentGrant({required this.agent, required this.userId, required this.permissions});

  factory ProjectAgentGrant.fromJson(Map<String, dynamic> json) {
    return ProjectAgentGrant(
      agent: ManagedAgent.fromJson(json['agent']),
      userId: json['user_id'] as String,
      permissions: ManagedAgentGrant.fromJson((json['permissions'] as Map?)?.cast<String, dynamic>() ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {'agent': agent.toJson(), 'user_id': userId, 'permissions': permissions.toJson()};
}

class AgentGrantsPage {
  final List<ProjectAgentGrant> agentGrants;
  final int total;

  AgentGrantsPage({required this.agentGrants, required this.total});

  factory AgentGrantsPage.fromJson(Map<String, dynamic> json) {
    final list = json['agent_grants'] as List<dynamic>? ?? [];
    return AgentGrantsPage(
      agentGrants: list.whereType<Map<String, dynamic>>().map(ProjectAgentGrant.fromJson).toList(),
      total: _parseInt(json['total']),
    );
  }

  Map<String, dynamic> toJson() => {'agent_grants': agentGrants.map((grant) => grant.toJson()).toList(), 'total': total};
}

class AgentRoomGrant extends ApiScope {
  AgentRoomGrant({
    super.livekit,
    super.queues,
    super.messaging,
    super.dataset,
    super.memory,
    super.sync,
    super.storage,
    super.containers,
    super.developer,
    super.agents,
    super.llm,
    super.admin,
    super.secrets,
    super.tunnels,
    super.services,
  });

  factory AgentRoomGrant.fromApiScope(ApiScope scope) {
    return AgentRoomGrant(
      livekit: scope.livekit,
      queues: scope.queues,
      messaging: scope.messaging,
      dataset: scope.dataset,
      memory: scope.memory,
      sync: scope.sync,
      storage: scope.storage,
      containers: scope.containers,
      developer: scope.developer,
      agents: scope.agents,
      llm: scope.llm,
      admin: scope.admin,
      secrets: scope.secrets,
      tunnels: scope.tunnels,
      services: scope.services,
    );
  }

  factory AgentRoomGrant.fromJson(Map<String, dynamic> json) {
    return AgentRoomGrant.fromApiScope(ApiScope.fromJson(json));
  }
}

class ProjectAgentRoomGrant {
  final ManagedAgent agent;
  final Room room;
  final AgentRoomGrant permissions;

  ProjectAgentRoomGrant({required this.agent, required this.room, required this.permissions});

  factory ProjectAgentRoomGrant.fromJson(Map<String, dynamic> json) {
    return ProjectAgentRoomGrant(
      agent: ManagedAgent.fromJson(json['agent']),
      room: Room.fromJson(json['room']),
      permissions: AgentRoomGrant.fromJson((json['permissions'] as Map?)?.cast<String, dynamic>() ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {'agent': agent.toJson(), 'room': room.toJson(), 'permissions': permissions.toJson()};
}

class ProjectAgentGrantCount {
  final ManagedAgent agent;
  final int count;

  ProjectAgentGrantCount({required this.agent, required this.count});

  factory ProjectAgentGrantCount.fromJson(Map<String, dynamic> json) {
    final dynamic c = json['count'];
    final int parsedCount = c is int
        ? c
        : c is num
        ? c.toInt()
        : c is String
        ? int.tryParse(c) ?? 0
        : 0;
    return ProjectAgentGrantCount(agent: ManagedAgent.fromJson(json['agent']), count: parsedCount);
  }

  Map<String, dynamic> toJson() => {'agent': agent.toJson(), 'count': count};
}

class ProjectRoomGrant {
  final Room room; // room name
  final String userId;
  final ApiScope permissions;

  ProjectRoomGrant({required this.room, required this.userId, required this.permissions});

  factory ProjectRoomGrant.fromJson(Map<String, dynamic> json) {
    return ProjectRoomGrant(
      room: Room.fromJson(json['room']),
      userId: json['user_id'] as String,
      permissions: ApiScope.fromJson(json['permissions'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() => {'room': room.toJson(), 'user_id': userId, 'permissions': permissions.toJson()};
}

class RoomGrantsPage {
  final List<ProjectRoomGrant> roomGrants;
  final int total;

  RoomGrantsPage({required this.roomGrants, required this.total});

  factory RoomGrantsPage.fromJson(Map<String, dynamic> json) {
    final list = json['room_grants'] as List<dynamic>? ?? [];
    return RoomGrantsPage(
      roomGrants: list.whereType<Map<String, dynamic>>().map(ProjectRoomGrant.fromJson).toList(),
      total: _parseInt(json['total']),
    );
  }

  Map<String, dynamic> toJson() => {'room_grants': roomGrants.map((grant) => grant.toJson()).toList(), 'total': total};
}

class ProjectRoomGrantCount {
  final Room room;
  final int count;

  ProjectRoomGrantCount({required this.room, required this.count});

  factory ProjectRoomGrantCount.fromJson(Map<String, dynamic> json) {
    final dynamic c = json['count'];
    final int parsedCount = c is int
        ? c
        : c is num
        ? c.toInt()
        : c is String
        ? int.tryParse(c) ?? 0
        : 0;
    return ProjectRoomGrantCount(room: Room.fromJson(json['room']), count: parsedCount);
  }

  Map<String, dynamic> toJson() => {'room': room, 'count': count};
}

class ProjectUserGrantCount {
  final String userId;
  final int count;
  final String? firstName;
  final String? lastName;
  final String email;

  ProjectUserGrantCount({required this.userId, required this.count, this.firstName, this.lastName, required this.email});

  factory ProjectUserGrantCount.fromJson(Map<String, dynamic> json) {
    final dynamic c = json['count'];
    final int parsedCount = c is int
        ? c
        : c is num
        ? c.toInt()
        : c is String
        ? int.tryParse(c) ?? 0
        : 0;

    return ProjectUserGrantCount(
      userId: json['user_id'] as String,
      count: parsedCount,
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      email: (json['email'] ?? '') as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'count': count,
    if (firstName != null) 'first_name': firstName,
    if (lastName != null) 'last_name': lastName,
    'email': email,
  };
}

class ProjectUserGrantCountsPage {
  final List<ProjectUserGrantCount> users;
  final int total;

  ProjectUserGrantCountsPage({required this.users, required this.total});

  factory ProjectUserGrantCountsPage.fromJson(Map<String, dynamic> json) {
    final list = json['users'] as List<dynamic>? ?? [];
    return ProjectUserGrantCountsPage(
      users: list.whereType<Map<String, dynamic>>().map(ProjectUserGrantCount.fromJson).toList(),
      total: _parseInt(json['total']),
    );
  }
}

/// A simple custom exception to denote HTTP errors.
class MeshagentException implements Exception {
  final String message;
  MeshagentException(this.message);

  @override
  String toString() => 'HttpException: $message';
}

class NotFoundException extends MeshagentException {
  NotFoundException(super.message);
}

class NameInUseException extends MeshagentException {
  NameInUseException(super.message);
}

class ForbiddenException extends MeshagentException {
  ForbiddenException(super.message);
}

class ApiKeyInfo {
  ApiKeyInfo({required this.id, required this.name, this.description, required this.value});

  final String id;
  final String name;
  final String? description;
  final String value;

  static ApiKeyInfo fromJson(Map<String, dynamic> json) {
    return ApiKeyInfo(id: json["id"], name: json["name"], description: json["description"], value: json["value"]);
  }
}
