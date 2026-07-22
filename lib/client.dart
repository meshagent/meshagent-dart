import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:meshagent/meshagent.dart';

String? _jsonString(Object? value) => value is String ? value : null;

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

class _ParsedErrorResponse {
  const _ParsedErrorResponse({this.code, this.message});

  final String? code;
  final String? message;
}

_ParsedErrorResponse _parseErrorResponseBody(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      final error = decoded['error'];
      if (error is Map<String, dynamic>) {
        return _ParsedErrorResponse(code: error['code'] as String?, message: error['message'] as String?);
      }
      return _ParsedErrorResponse(code: decoded['code'] as String?, message: decoded['message'] as String?);
    }
  } catch (_) {
    // Fall through to the generic message below.
  }
  return const _ParsedErrorResponse();
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

abstract final class ProjectRoles {
  static const member = 'member';
  static const admin = 'admin';
  static const developer = 'developer';
  static const roomCreator = 'room_creator';
  static const roomInventory = 'room_inventory';
  static const roomManager = 'room_manager';
  static const sessionInventory = 'session_inventory';
  static const agentCreator = 'agent_creator';
  static const agentInventory = 'agent_inventory';
  static const agentManager = 'agent_manager';
  static const repositoryCreator = 'repository_creator';
  static const repositoryInventory = 'repository_inventory';
  static const repositoryManager = 'repository_manager';
  static const feedCreator = 'feed_creator';
  static const feedInventory = 'feed_inventory';
  static const feedManager = 'feed_manager';
  static const oauthClientCreator = 'oauth_client_creator';
  static const oauthClientInventory = 'oauth_client_inventory';
  static const oauthClientManager = 'oauth_client_manager';
  static const apiKeyCreator = 'api_key_creator';
  static const apiKeyInventory = 'api_key_inventory';
  static const apiKeyManager = 'api_key_manager';
  static const serviceCreator = 'service_creator';
  static const serviceInventory = 'service_inventory';
  static const serviceManager = 'service_manager';
  static const serviceAccountCreator = 'service_account_creator';
  static const serviceAccountInventory = 'service_account_inventory';
  static const serviceAccountManager = 'service_account_manager';
  static const participantTokenCreator = 'participant_token_creator';
  static const mailboxCreator = 'mailbox_creator';
  static const mailboxInventory = 'mailbox_inventory';
  static const mailboxManager = 'mailbox_manager';
  static const routeCreator = 'route_creator';
  static const routeInventory = 'route_inventory';
  static const routeManager = 'route_manager';
  static const scheduledTaskCreator = 'scheduled_task_creator';
  static const scheduledTaskInventory = 'scheduled_task_inventory';
  static const scheduledTaskManager = 'scheduled_task_manager';
  static const feedSubscriptionCreator = 'feed_subscription_creator';
  static const feedSubscriptionInventory = 'feed_subscription_inventory';
  static const feedSubscriptionManager = 'feed_subscription_manager';
  static const llmLoggerCreator = 'llm_logger_creator';
  static const llmLoggerInventory = 'llm_logger_inventory';
  static const llmLoggerManager = 'llm_logger_manager';
  static const llmProxyUser = 'llm_proxy_user';
  static const usageReporter = 'usage_reporter';
  static const billingManager = 'billing_manager';
  static const groupManager = 'group_manager';

  static const all = [
    member,
    admin,
    developer,
    roomCreator,
    roomInventory,
    roomManager,
    sessionInventory,
    agentCreator,
    agentInventory,
    agentManager,
    repositoryCreator,
    repositoryInventory,
    repositoryManager,
    feedCreator,
    feedInventory,
    feedManager,
    oauthClientCreator,
    oauthClientInventory,
    oauthClientManager,
    apiKeyCreator,
    apiKeyInventory,
    apiKeyManager,
    serviceCreator,
    serviceInventory,
    serviceManager,
    serviceAccountCreator,
    serviceAccountInventory,
    serviceAccountManager,
    participantTokenCreator,
    mailboxCreator,
    mailboxInventory,
    mailboxManager,
    routeCreator,
    routeInventory,
    routeManager,
    scheduledTaskCreator,
    scheduledTaskInventory,
    scheduledTaskManager,
    feedSubscriptionCreator,
    feedSubscriptionInventory,
    feedSubscriptionManager,
    llmLoggerCreator,
    llmLoggerInventory,
    llmLoggerManager,
    llmProxyUser,
    usageReporter,
    billingManager,
    groupManager,
  ];
}

enum ProjectRole {
  none('none', 'None'),
  member(ProjectRoles.member, 'Member'),
  admin(ProjectRoles.admin, 'Admin'),
  developer(ProjectRoles.developer, 'Developer'),
  roomCreator(ProjectRoles.roomCreator, 'Room Creator'),
  roomInventory(ProjectRoles.roomInventory, 'Room Inventory'),
  roomManager(ProjectRoles.roomManager, 'Room Manager'),
  sessionInventory(ProjectRoles.sessionInventory, 'Session Inventory'),
  agentCreator(ProjectRoles.agentCreator, 'Agent Creator'),
  agentInventory(ProjectRoles.agentInventory, 'Agent Inventory'),
  agentManager(ProjectRoles.agentManager, 'Agent Manager'),
  repositoryCreator(ProjectRoles.repositoryCreator, 'Repository Creator'),
  repositoryInventory(ProjectRoles.repositoryInventory, 'Repository Inventory'),
  repositoryManager(ProjectRoles.repositoryManager, 'Repository Manager'),
  feedCreator(ProjectRoles.feedCreator, 'Feed Creator'),
  feedInventory(ProjectRoles.feedInventory, 'Feed Inventory'),
  feedManager(ProjectRoles.feedManager, 'Feed Manager'),
  oauthClientCreator(ProjectRoles.oauthClientCreator, 'OAuth Client Creator'),
  oauthClientInventory(ProjectRoles.oauthClientInventory, 'OAuth Client Inventory'),
  oauthClientManager(ProjectRoles.oauthClientManager, 'OAuth Client Manager'),
  apiKeyCreator(ProjectRoles.apiKeyCreator, 'API Key Creator'),
  apiKeyInventory(ProjectRoles.apiKeyInventory, 'API Key Inventory'),
  apiKeyManager(ProjectRoles.apiKeyManager, 'API Key Manager'),
  serviceCreator(ProjectRoles.serviceCreator, 'Service Creator'),
  serviceInventory(ProjectRoles.serviceInventory, 'Service Inventory'),
  serviceManager(ProjectRoles.serviceManager, 'Service Manager'),
  serviceAccountCreator(ProjectRoles.serviceAccountCreator, 'Service Account Creator'),
  serviceAccountInventory(ProjectRoles.serviceAccountInventory, 'Service Account Inventory'),
  serviceAccountManager(ProjectRoles.serviceAccountManager, 'Service Account Manager'),
  participantTokenCreator(ProjectRoles.participantTokenCreator, 'Participant Token Creator'),
  mailboxCreator(ProjectRoles.mailboxCreator, 'Mailbox Creator'),
  mailboxInventory(ProjectRoles.mailboxInventory, 'Mailbox Inventory'),
  mailboxManager(ProjectRoles.mailboxManager, 'Mailbox Manager'),
  routeCreator(ProjectRoles.routeCreator, 'Route Creator'),
  routeInventory(ProjectRoles.routeInventory, 'Route Inventory'),
  routeManager(ProjectRoles.routeManager, 'Route Manager'),
  scheduledTaskCreator(ProjectRoles.scheduledTaskCreator, 'Scheduled Task Creator'),
  scheduledTaskInventory(ProjectRoles.scheduledTaskInventory, 'Scheduled Task Inventory'),
  scheduledTaskManager(ProjectRoles.scheduledTaskManager, 'Scheduled Task Manager'),
  feedSubscriptionCreator(ProjectRoles.feedSubscriptionCreator, 'Feed Subscription Creator'),
  feedSubscriptionInventory(ProjectRoles.feedSubscriptionInventory, 'Feed Subscription Inventory'),
  feedSubscriptionManager(ProjectRoles.feedSubscriptionManager, 'Feed Subscription Manager'),
  llmLoggerCreator(ProjectRoles.llmLoggerCreator, 'LLM Logger Creator'),
  llmLoggerInventory(ProjectRoles.llmLoggerInventory, 'LLM Logger Inventory'),
  llmLoggerManager(ProjectRoles.llmLoggerManager, 'LLM Logger Manager'),
  llmProxyUser(ProjectRoles.llmProxyUser, 'LLM Proxy User'),
  usageReporter(ProjectRoles.usageReporter, 'Usage Reporter'),
  billingManager(ProjectRoles.billingManager, 'Billing Manager'),
  groupManager(ProjectRoles.groupManager, 'Group Manager');

  const ProjectRole(this.relation, this.label);

  final String relation;
  final String label;

  static const assignable = [
    member,
    admin,
    developer,
    roomCreator,
    roomInventory,
    roomManager,
    sessionInventory,
    agentCreator,
    agentInventory,
    agentManager,
    repositoryCreator,
    repositoryInventory,
    repositoryManager,
    feedCreator,
    feedInventory,
    feedManager,
    oauthClientCreator,
    oauthClientInventory,
    oauthClientManager,
    apiKeyCreator,
    apiKeyInventory,
    apiKeyManager,
    serviceCreator,
    serviceInventory,
    serviceManager,
    serviceAccountCreator,
    serviceAccountInventory,
    serviceAccountManager,
    participantTokenCreator,
    mailboxCreator,
    mailboxInventory,
    mailboxManager,
    routeCreator,
    routeInventory,
    routeManager,
    scheduledTaskCreator,
    scheduledTaskInventory,
    scheduledTaskManager,
    feedSubscriptionCreator,
    feedSubscriptionInventory,
    feedSubscriptionManager,
    llmLoggerCreator,
    llmLoggerInventory,
    llmLoggerManager,
    llmProxyUser,
    usageReporter,
    billingManager,
    groupManager,
  ];

  static ProjectRole fromRelation(String? relation) {
    for (final role in values) {
      if (role.relation == relation) {
        return role;
      }
    }
    return none;
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
    final agentName = json["agent_name"] as String;
    final projectId = json["project_id"] as String;
    final agentUrl = Uri.parse(json["agent_url"] as String);
    final legacySuffix = '/accounts/projects/${Uri.encodeComponent(projectId)}/agents/${Uri.encodeComponent(agentName)}/messages';
    final normalizedAgentUrl = agentUrl.path.endsWith(legacySuffix)
        ? agentUrl.replace(
            path:
                '${agentUrl.path.substring(0, agentUrl.path.length - legacySuffix.length)}/agents/${Uri.encodeComponent(projectId)}/${Uri.encodeComponent(agentName)}/messages',
          )
        : agentUrl;
    return AgentConnectionInfo(jwt: json["jwt"], agentName: agentName, projectId: projectId, agentUrl: normalizedAgentUrl);
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
  final String? continuationToken;

  MailboxesPage({required this.mailboxes, required this.total, this.continuationToken});

  factory MailboxesPage.fromJson(Map<String, dynamic> json) {
    final list = json['mailboxes'] as List<dynamic>? ?? [];
    final mailboxes = list.whereType<Map<String, dynamic>>().map(Mailbox.fromJson).toList();
    return MailboxesPage(
      mailboxes: mailboxes,
      total: json.containsKey('total') ? _parseInt(json['total']) : mailboxes.length,
      continuationToken: json['continuation_token'] as String?,
    );
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
  final String? continuationToken;

  RoutesPage({required this.routes, required this.total, this.continuationToken});

  factory RoutesPage.fromJson(Map<String, dynamic> json) {
    final list = json['routes'] as List<dynamic>? ?? [];
    final routes = list.whereType<Map<String, dynamic>>().map(Route.fromJson).toList();
    return RoutesPage(
      routes: routes,
      total: json.containsKey('total') ? _parseInt(json['total']) : routes.length,
      continuationToken: json['continuation_token'] as String?,
    );
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
  final String status;

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
    this.status = 'ready',
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
    status: json['status'] as String? ?? 'ready',
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
    'status': status,
  };
}

class FeedsPage {
  final List<Feed> feeds;
  final int total;
  final String? continuationToken;

  FeedsPage({required this.feeds, required this.total, this.continuationToken});

  factory FeedsPage.fromJson(Map<String, dynamic> json) {
    final list = json['feeds'] as List<dynamic>? ?? [];
    final feeds = list.whereType<Map<String, dynamic>>().map(Feed.fromJson).toList();
    return FeedsPage(
      feeds: feeds,
      total: json.containsKey('total') ? _parseInt(json['total']) : feeds.length,
      continuationToken: json['continuation_token'] as String?,
    );
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
  final String status;

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
    this.status = 'ready',
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
    status: json['status'] as String? ?? 'ready',
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
    'status': status,
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

class MeshagentRepositoriesPage {
  final List<ProjectRepository> repositories;
  final int total;
  final String? continuationToken;

  MeshagentRepositoriesPage({required this.repositories, required this.total, this.continuationToken});

  factory MeshagentRepositoriesPage.fromJson(Map<String, dynamic> json) {
    final list = json['repositories'] as List<dynamic>? ?? [];
    final repositories = list.whereType<Map>().map((m) => ProjectRepository.fromJson(m.cast<String, dynamic>())).toList();
    return MeshagentRepositoriesPage(
      repositories: repositories,
      total: json.containsKey('total') ? _parseInt(json['total']) : repositories.length,
      continuationToken: json['continuation_token'] as String?,
    );
  }
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
      total: json.containsKey('total') ? _parseInt(json['total']) : list.length,
    );
  }
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
  final String? continuationToken;

  ScheduledTasksPage({required this.tasks, required this.total, this.continuationToken});

  factory ScheduledTasksPage.fromJson(Map<String, dynamic> json) {
    final list = json['tasks'] as List<dynamic>? ?? [];
    final tasks = list.whereType<Map>().map((m) => ScheduledTask.fromJson(m.cast<String, dynamic>())).toList();
    return ScheduledTasksPage(
      tasks: tasks,
      total: json.containsKey('total') ? _parseInt(json['total']) : tasks.length,
      continuationToken: json['continuation_token'] as String?,
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

  Map<String, dynamic> _secretPayload({
    String? projectId,
    String? name,
    String? type,
    bool? httpOnly,
    Map<String, dynamic>? metadata,
    Map<String, dynamic>? annotations,
  }) {
    return <String, dynamic>{
      'project_id': ?projectId,
      'name': ?name,
      'type': ?type,
      'http_only': ?httpOnly,
      'metadata': ?metadata,
      'annotations': ?annotations,
    };
  }

  Map<String, dynamic> _secretSearchPayload({
    String? filter,
    String? name,
    String? type,
    bool? httpOnly,
    Map<String, dynamic>? metadata,
    Map<String, dynamic>? annotations,
    int pageSize = 100,
    String? continuationToken,
  }) {
    return <String, dynamic>{
      'page_size': pageSize,
      'filter': ?filter,
      'name': ?name,
      'type': ?type,
      'http_only': ?httpOnly,
      'metadata': ?metadata,
      'annotations': ?annotations,
      'continuation_token': ?continuationToken,
    };
  }

  Map<String, dynamic> _secretVersionPayload({required Uint8List value, bool setCurrent = true}) {
    return <String, dynamic>{'value_base64': base64Encode(value), 'set_current': setCurrent};
  }

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
  Future<MailboxesPage> listMailboxesPage(String projectId, {int pageSize = 100, String? continuationToken, String? filter}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final query = <String, String>{'page_size': '$pageSize'};
    if (continuationToken != null) query['continuation_token'] = continuationToken;
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

  Future<List<Mailbox>> listMailboxes(String projectId, {int pageSize = 100, String? filter}) async {
    final mailboxes = <Mailbox>[];
    String? nextToken;
    do {
      final page = await listMailboxesPage(projectId, pageSize: pageSize, continuationToken: nextToken, filter: filter);
      mailboxes.addAll(page.mailboxes);
      nextToken = page.continuationToken;
    } while (nextToken != null);
    return mailboxes;
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
  Future<RoutesPage> listRoutesPage(String projectId, {int pageSize = 100, String? continuationToken, String? filter}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final query = <String, String>{'page_size': '$pageSize'};
    if (continuationToken != null) query['continuation_token'] = continuationToken;
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

  Future<List<Route>> listRoutes(String projectId, {int pageSize = 100, String? filter}) async {
    final routes = <Route>[];
    String? nextToken;
    do {
      final page = await listRoutesPage(projectId, pageSize: pageSize, continuationToken: nextToken, filter: filter);
      routes.addAll(page.routes);
      nextToken = page.continuationToken;
    } while (nextToken != null);
    return routes;
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

  Future<FeedsPage> listFeedsPage(String projectId, {int pageSize = 100, String? continuationToken, String? filter, String? view}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final query = <String, String>{'page_size': '$pageSize'};
    if (continuationToken != null) query['continuation_token'] = continuationToken;
    if (filter != null && filter.trim().isNotEmpty) query['filter'] = filter;
    if (view != null && view.trim().isNotEmpty) query['view'] = view;
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

  Future<List<Feed>> listFeeds(String projectId, {int pageSize = 100, String? filter, String? view}) async {
    final feeds = <Feed>[];
    String? nextToken;
    do {
      final page = await listFeedsPage(projectId, pageSize: pageSize, continuationToken: nextToken, filter: filter, view: view);
      feeds.addAll(page.feeds);
      nextToken = page.continuationToken;
    } while (nextToken != null);
    return feeds;
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

  Future<MeshagentRepositoriesPage> listRepositoriesPage({
    required String projectId,
    int pageSize = 100,
    String? view,
    String? continuationToken,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/repositories',
    ).replace(queryParameters: {'page_size': '$pageSize', 'view': ?view, 'continuation_token': ?continuationToken});
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

  Future<List<ProjectRepository>> listRepositories({required String projectId, String? view}) async {
    final repositories = <ProjectRepository>[];
    String? nextToken;
    do {
      final page = await listRepositoriesPage(projectId: projectId, view: view, continuationToken: nextToken);
      repositories.addAll(page.repositories);
      nextToken = page.continuationToken;
    } while (nextToken != null);
    return repositories;
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

  Future<Map<String, dynamic>> getProjectSettings({required String projectId}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/settings');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to get project settings. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
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
  /// Body: a ServiceSpec JSON object.
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
  /// Body: a ServiceSpec JSON object.
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
    List<String>? roles,
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
      'roles':
          roles ??
          _projectRolesFromFlags(
            isAdmin: isAdmin,
            isDeveloper: isDeveloper,
            canCreateRooms: canCreateRooms,
            canCreateAgents: canCreateAgents,
            canUseLlmProxy: canUseLlmProxy,
          ),
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
    List<String>? roles,
    bool? isAdmin,
    bool? isDeveloper,
    bool? canCreateRooms,
    bool? canCreateAgents,
    bool? canUseLlmProxy,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedUserId = Uri.encodeComponent(userId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/users/$encodedUserId');
    final body = {
      'roles':
          roles ??
          _projectRolesFromFlags(
            isAdmin: isAdmin,
            isDeveloper: isDeveloper,
            canCreateRooms: canCreateRooms,
            canCreateAgents: canCreateAgents,
            canUseLlmProxy: canUseLlmProxy,
          ),
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
    List<String>? roles,
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
      'roles':
          roles ??
          _projectRolesFromFlags(
            isAdmin: isAdmin,
            isDeveloper: isDeveloper,
            canCreateRooms: canCreateRooms,
            canCreateAgents: canCreateAgents,
            canUseLlmProxy: canUseLlmProxy,
          ),
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
    int pageSize = 100,
    String? continuationToken,
    String? filter,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    Uri uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/users');

    if (email != null) {
      uri = uri.replace(queryParameters: {"email": email});
    } else {
      final query = <String, String>{'page_size': '$pageSize'};
      if (continuationToken != null) query['continuation_token'] = continuationToken;
      if (filter != null && filter.trim().isNotEmpty) query['filter'] = filter;
      uri = uri.replace(queryParameters: query);
    }

    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to get users in project. Status code: ${response.statusCode}, body: ${response.body}');
    }
    return ProjectMembersPage.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<ProjectMember>> getUsersInProject(
    String projectId, {
    String? email,
    int pageSize = 100,
    String? continuationToken,
    String? filter,
  }) async {
    final page = await getUsersInProjectPage(
      projectId,
      email: email,
      pageSize: pageSize,
      continuationToken: continuationToken,
      filter: filter,
    );
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

  Future<ServiceAccountsPage> listServiceAccountsPage(
    String projectId, {
    int pageSize = 100,
    String? continuationToken,
    String? filter,
    String? view,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final query = <String, String>{'page_size': '$pageSize'};
    if (continuationToken != null) {
      query['continuation_token'] = continuationToken;
    }
    if (filter != null) {
      query['filter'] = filter;
    }
    if (view != null) {
      query['view'] = view;
    }
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/service-accounts').replace(queryParameters: query);
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list service accounts. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return ServiceAccountsPage.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<AccessSubject> resolveSubject(String projectId, String email) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/subjects:resolve').replace(queryParameters: {'email': email});
    final response = await httpClient.get(uri);

    if (response.statusCode == 404) {
      throw NotFoundException('subject not found');
    }
    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to resolve subject. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return AccessSubject.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<ServiceAccount> createServiceAccount(
    String projectId,
    String name, {
    String? displayName,
    String? description,
    Map<String, dynamic>? metadata,
    Map<String, String>? annotations,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/service-accounts');
    final body = <String, dynamic>{'name': name};
    if (displayName != null) {
      body['display_name'] = displayName;
    }
    if (description != null) {
      body['description'] = description;
    }
    if (metadata != null) {
      body['metadata'] = metadata;
    }
    if (annotations != null) {
      body['annotations'] = annotations;
    }

    final response = await httpClient.post(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to create service account. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return ServiceAccount.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> updateServiceAccount(
    String projectId,
    String serviceAccountId, {
    required String name,
    String? displayName,
    String? description,
    Map<String, dynamic>? metadata,
    Map<String, String>? annotations,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedServiceAccountId = Uri.encodeComponent(serviceAccountId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/service-accounts/$encodedServiceAccountId');
    final body = <String, dynamic>{'name': name};
    if (displayName != null) {
      body['display_name'] = displayName;
    }
    if (description != null) {
      body['description'] = description;
    }
    if (metadata != null) {
      body['metadata'] = metadata;
    }
    if (annotations != null) {
      body['annotations'] = annotations;
    }

    final response = await httpClient.put(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to update service account. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<void> deleteServiceAccount(String projectId, String serviceAccountId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedServiceAccountId = Uri.encodeComponent(serviceAccountId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/service-accounts/$encodedServiceAccountId');
    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to delete service account. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<String> mintParticipantToken(
    String projectId, {
    required String name,
    String? roomName,
    String? role,
    Map<String, dynamic>? api,
    List<Map<String, dynamic>>? grants,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/participant-tokens');
    final body = <String, dynamic>{'name': name};
    if (grants != null) {
      body['grants'] = grants;
    } else {
      if (roomName != null) {
        body['room_name'] = roomName;
      }
      if (role != null) {
        body['role'] = role;
      }
      if (api != null) {
        body['api'] = api;
      }
    }

    final response = await httpClient.post(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to mint participant token. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final token = payload['token'];
    if (token is! String || token.trim().isEmpty) {
      throw MeshagentException('Invalid participant token mint response');
    }
    return token;
  }

  /// Corresponds to: POST /accounts/projects/{project_id}/service-accounts/{service_account_id}/api-keys
  /// Body: { "name": "", "description": "" }
  /// Returns an Api Key.
  Future<ApiKeyInfo> createApiKey(String projectId, String serviceAccountId, String name, String description) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedServiceAccountId = Uri.encodeComponent(serviceAccountId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/service-accounts/$encodedServiceAccountId/api-keys');
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

  /// Corresponds to: DELETE /accounts/projects/{project_id}/service-accounts/{service_account_id}/api-keys/{token_id}
  /// Returns 204 No Content on success (no JSON body).
  Future<void> deleteApiKey(String projectId, String serviceAccountId, String tokenId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedServiceAccountId = Uri.encodeComponent(serviceAccountId);
    final encodedTokenId = Uri.encodeComponent(tokenId);
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/service-accounts/$encodedServiceAccountId/api-keys/$encodedTokenId',
    );
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

  Future<ApiKeysRevocationResult> revokeApiKeysByMsid(String projectId, String serviceAccountId, String msid) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedServiceAccountId = Uri.encodeComponent(serviceAccountId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/service-accounts/$encodedServiceAccountId/api-keys:revoke');
    final response = await httpClient.post(uri, body: jsonEncode({'msid': msid}));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to revoke project API keys. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return ApiKeysRevocationResult.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Corresponds to: GET /accounts/projects/{project_id}/service-accounts/{service_account_id}/api-keys
  /// Returns a JSON dict like: { "tokens": [ { ... }, ... ] }.
  Future<MeshagentApiKeysPage> listApiKeysPage(String projectId, String serviceAccountId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedServiceAccountId = Uri.encodeComponent(serviceAccountId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/service-accounts/$encodedServiceAccountId/api-keys');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list project API keys. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return MeshagentApiKeysPage.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<Map<String, dynamic>>> listApiKeys(String projectId, String serviceAccountId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedServiceAccountId = Uri.encodeComponent(serviceAccountId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/service-accounts/$encodedServiceAccountId/api-keys');
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

  Future<Secret> createUserSecret({
    required String projectId,
    required String name,
    String type = 'opaque',
    bool httpOnly = false,
    Map<String, dynamic>? metadata,
    Map<String, dynamic>? annotations,
  }) async {
    final uri = Uri.parse('$baseUrl/accounts/users/me/secrets');
    final response = await httpClient.post(
      uri,
      body: jsonEncode(
        _secretPayload(projectId: projectId, name: name, type: type, httpOnly: httpOnly, metadata: metadata, annotations: annotations),
      ),
    );

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to create user secret. Status code: ${response.statusCode}, body: ${response.body}');
    }

    return Secret.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<SecretsPage> listUserSecrets({int pageSize = 100, String? continuationToken, String? filter}) async {
    final query = <String, String>{'page_size': '$pageSize'};
    if (continuationToken != null) {
      query['continuation_token'] = continuationToken;
    }
    if (filter != null) {
      query['filter'] = filter;
    }
    final uri = Uri.parse('$baseUrl/accounts/users/me/secrets').replace(queryParameters: query);
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to list user secrets. Status code: ${response.statusCode}, body: ${response.body}');
    }

    return SecretsPage.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<SecretsPage> searchUserSecrets({
    String? filter,
    String? name,
    String? type,
    bool? httpOnly,
    Map<String, dynamic>? metadata,
    Map<String, dynamic>? annotations,
    int pageSize = 100,
    String? continuationToken,
  }) async {
    final uri = Uri.parse('$baseUrl/accounts/users/me/secrets:search');
    final response = await httpClient.post(
      uri,
      body: jsonEncode(
        _secretSearchPayload(
          filter: filter,
          name: name,
          type: type,
          httpOnly: httpOnly,
          metadata: metadata,
          annotations: annotations,
          pageSize: pageSize,
          continuationToken: continuationToken,
        ),
      ),
    );

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to search user secrets. Status code: ${response.statusCode}, body: ${response.body}');
    }

    return SecretsPage.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Secret> getUserSecret(String secretId, {bool includeValue = false}) async {
    final encodedSecretId = Uri.encodeComponent(secretId);
    final uri = Uri.parse(
      '$baseUrl/accounts/users/me/secrets/$encodedSecretId',
    ).replace(queryParameters: includeValue ? <String, String>{'include_value': 'true'} : null);
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to get user secret. Status code: ${response.statusCode}, body: ${response.body}');
    }

    return Secret.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Secret> updateUserSecret(
    String secretId, {
    String? name,
    String? type,
    bool? httpOnly,
    Map<String, dynamic>? metadata,
    Map<String, dynamic>? annotations,
  }) async {
    final encodedSecretId = Uri.encodeComponent(secretId);
    final uri = Uri.parse('$baseUrl/accounts/users/me/secrets/$encodedSecretId');
    final response = await httpClient.patch(
      uri,
      body: jsonEncode(_secretPayload(name: name, type: type, httpOnly: httpOnly, metadata: metadata, annotations: annotations)),
    );

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to update user secret. Status code: ${response.statusCode}, body: ${response.body}');
    }

    return Secret.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> deleteUserSecret(String secretId) async {
    final encodedSecretId = Uri.encodeComponent(secretId);
    final uri = Uri.parse('$baseUrl/accounts/users/me/secrets/$encodedSecretId');
    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to delete user secret. Status code: ${response.statusCode}, body: ${response.body}');
    }
  }

  Future<List<SecretVersion>> listUserSecretVersions(String secretId) async {
    final encodedSecretId = Uri.encodeComponent(secretId);
    final uri = Uri.parse('$baseUrl/accounts/users/me/secrets/$encodedSecretId/versions');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to list user secret versions. Status code: ${response.statusCode}, body: ${response.body}');
    }

    return SecretVersionsPage.fromJson(jsonDecode(response.body) as Map<String, dynamic>).versions;
  }

  Future<SecretVersion> createUserSecretVersion(String secretId, {required Uint8List value, bool setCurrent = true}) async {
    final encodedSecretId = Uri.encodeComponent(secretId);
    final uri = Uri.parse('$baseUrl/accounts/users/me/secrets/$encodedSecretId/versions');
    final response = await httpClient.post(
      uri,
      body: jsonEncode(_secretVersionPayload(value: value, setCurrent: setCurrent)),
    );

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to create user secret version. Status code: ${response.statusCode}, body: ${response.body}');
    }

    return SecretVersion.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Uint8List> accessUserSecretVersion(String secretId, String versionId) async {
    final encodedSecretId = Uri.encodeComponent(secretId);
    final encodedVersionId = Uri.encodeComponent(versionId);
    final uri = Uri.parse('$baseUrl/accounts/users/me/secrets/$encodedSecretId/versions/$encodedVersionId:access');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to access user secret version. Status code: ${response.statusCode}, body: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return base64Decode(data['value_base64'] as String);
  }

  Future<void> deleteUserSecretVersion(String secretId, String versionId) async {
    final encodedSecretId = Uri.encodeComponent(secretId);
    final encodedVersionId = Uri.encodeComponent(versionId);
    final uri = Uri.parse('$baseUrl/accounts/users/me/secrets/$encodedSecretId/versions/$encodedVersionId');
    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to delete user secret version. Status code: ${response.statusCode}, body: ${response.body}');
    }
  }

  Future<SecretProxyAccessGrantsPage> listUserSecretProxyAccess(String secretId, {int pageSize = 100, String? continuationToken}) async {
    final encodedSecretId = Uri.encodeComponent(secretId);
    final query = <String, String>{'page_size': '$pageSize'};
    if (continuationToken != null) {
      query['continuation_token'] = continuationToken;
    }
    final uri = Uri.parse('$baseUrl/accounts/users/me/secrets/$encodedSecretId/access').replace(queryParameters: query);
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to list user secret proxy access. Status code: ${response.statusCode}, body: ${response.body}');
    }

    return SecretProxyAccessGrantsPage.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> grantUserSecretProxyAccess(String secretId, String serviceAccountId) async {
    final encodedSecretId = Uri.encodeComponent(secretId);
    final uri = Uri.parse('$baseUrl/accounts/users/me/secrets/$encodedSecretId/access:grant-proxy');
    final response = await httpClient.post(
      uri,
      body: jsonEncode({
        'subject': {'type': 'service_account', 'id': serviceAccountId},
      }),
    );

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to grant user secret proxy access. Status code: ${response.statusCode}, body: ${response.body}');
    }
  }

  Future<void> revokeUserSecretProxyAccess(String secretId, String serviceAccountId) async {
    final encodedSecretId = Uri.encodeComponent(secretId);
    final uri = Uri.parse('$baseUrl/accounts/users/me/secrets/$encodedSecretId/access:revoke-proxy');
    final response = await httpClient.post(
      uri,
      body: jsonEncode({
        'subject': {'type': 'service_account', 'id': serviceAccountId},
      }),
    );

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to revoke user secret proxy access. Status code: ${response.statusCode}, body: ${response.body}');
    }
  }

  Future<Secret> createServiceAccountSecret(
    String projectId,
    String serviceAccountId, {
    required String name,
    String type = 'opaque',
    bool httpOnly = false,
    Map<String, dynamic>? metadata,
    Map<String, dynamic>? annotations,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedServiceAccountId = Uri.encodeComponent(serviceAccountId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/service-accounts/$encodedServiceAccountId/secrets');
    final response = await httpClient.post(
      uri,
      body: jsonEncode(_secretPayload(name: name, type: type, httpOnly: httpOnly, metadata: metadata, annotations: annotations)),
    );

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to create service account secret. Status code: ${response.statusCode}, body: ${response.body}');
    }

    return Secret.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<SecretsPage> listServiceAccountSecrets(
    String projectId,
    String serviceAccountId, {
    int pageSize = 100,
    String? continuationToken,
    String? filter,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedServiceAccountId = Uri.encodeComponent(serviceAccountId);
    final query = <String, String>{'page_size': '$pageSize'};
    if (continuationToken != null) {
      query['continuation_token'] = continuationToken;
    }
    if (filter != null) {
      query['filter'] = filter;
    }
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/service-accounts/$encodedServiceAccountId/secrets',
    ).replace(queryParameters: query);
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to list service account secrets. Status code: ${response.statusCode}, body: ${response.body}');
    }

    return SecretsPage.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<SecretsPage> searchServiceAccountSecrets(
    String projectId,
    String serviceAccountId, {
    String? filter,
    String? name,
    String? type,
    bool? httpOnly,
    Map<String, dynamic>? metadata,
    Map<String, dynamic>? annotations,
    int pageSize = 100,
    String? continuationToken,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedServiceAccountId = Uri.encodeComponent(serviceAccountId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/service-accounts/$encodedServiceAccountId/secrets:search');
    final response = await httpClient.post(
      uri,
      body: jsonEncode(
        _secretSearchPayload(
          filter: filter,
          name: name,
          type: type,
          httpOnly: httpOnly,
          metadata: metadata,
          annotations: annotations,
          pageSize: pageSize,
          continuationToken: continuationToken,
        ),
      ),
    );

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to search service account secrets. Status code: ${response.statusCode}, body: ${response.body}');
    }

    return SecretsPage.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Secret> getServiceAccountSecret(String projectId, String serviceAccountId, String secretId, {bool includeValue = false}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedServiceAccountId = Uri.encodeComponent(serviceAccountId);
    final encodedSecretId = Uri.encodeComponent(secretId);
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/service-accounts/$encodedServiceAccountId/secrets/$encodedSecretId',
    ).replace(queryParameters: includeValue ? <String, String>{'include_value': 'true'} : null);
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to get service account secret. Status code: ${response.statusCode}, body: ${response.body}');
    }

    return Secret.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Secret> updateServiceAccountSecret(
    String projectId,
    String serviceAccountId,
    String secretId, {
    String? name,
    String? type,
    bool? httpOnly,
    Map<String, dynamic>? metadata,
    Map<String, dynamic>? annotations,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedServiceAccountId = Uri.encodeComponent(serviceAccountId);
    final encodedSecretId = Uri.encodeComponent(secretId);
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/service-accounts/$encodedServiceAccountId/secrets/$encodedSecretId',
    );
    final response = await httpClient.patch(
      uri,
      body: jsonEncode(_secretPayload(name: name, type: type, httpOnly: httpOnly, metadata: metadata, annotations: annotations)),
    );

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to update service account secret. Status code: ${response.statusCode}, body: ${response.body}');
    }

    return Secret.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> deleteServiceAccountSecret(String projectId, String serviceAccountId, String secretId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedServiceAccountId = Uri.encodeComponent(serviceAccountId);
    final encodedSecretId = Uri.encodeComponent(secretId);
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/service-accounts/$encodedServiceAccountId/secrets/$encodedSecretId',
    );
    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to delete service account secret. Status code: ${response.statusCode}, body: ${response.body}');
    }
  }

  Future<List<SecretVersion>> listServiceAccountSecretVersions(String projectId, String serviceAccountId, String secretId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedServiceAccountId = Uri.encodeComponent(serviceAccountId);
    final encodedSecretId = Uri.encodeComponent(secretId);
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/service-accounts/$encodedServiceAccountId/secrets/$encodedSecretId/versions',
    );
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list service account secret versions. Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return SecretVersionsPage.fromJson(jsonDecode(response.body) as Map<String, dynamic>).versions;
  }

  Future<SecretVersion> createServiceAccountSecretVersion(
    String projectId,
    String serviceAccountId,
    String secretId, {
    required Uint8List value,
    bool setCurrent = true,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedServiceAccountId = Uri.encodeComponent(serviceAccountId);
    final encodedSecretId = Uri.encodeComponent(secretId);
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/service-accounts/$encodedServiceAccountId/secrets/$encodedSecretId/versions',
    );
    final response = await httpClient.post(
      uri,
      body: jsonEncode(_secretVersionPayload(value: value, setCurrent: setCurrent)),
    );

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to create service account secret version. Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return SecretVersion.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Uint8List> accessServiceAccountSecretVersion(String projectId, String serviceAccountId, String secretId, String versionId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedServiceAccountId = Uri.encodeComponent(serviceAccountId);
    final encodedSecretId = Uri.encodeComponent(secretId);
    final encodedVersionId = Uri.encodeComponent(versionId);
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/service-accounts/$encodedServiceAccountId/secrets/$encodedSecretId/versions/$encodedVersionId:access',
    );
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to access service account secret version. Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return base64Decode(data['value_base64'] as String);
  }

  Future<void> deleteServiceAccountSecretVersion(String projectId, String serviceAccountId, String secretId, String versionId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedServiceAccountId = Uri.encodeComponent(serviceAccountId);
    final encodedSecretId = Uri.encodeComponent(secretId);
    final encodedVersionId = Uri.encodeComponent(versionId);
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/service-accounts/$encodedServiceAccountId/secrets/$encodedSecretId/versions/$encodedVersionId',
    );
    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to delete service account secret version. Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<List<Secret>> listServiceAccountPullSecrets(String projectId, String serviceAccountId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedServiceAccountId = Uri.encodeComponent(serviceAccountId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/service-accounts/$encodedServiceAccountId/pull-secrets');
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to list service account pull secrets. Status code: ${response.statusCode}, body: ${response.body}');
    }

    return SecretsPage.fromJson(jsonDecode(response.body) as Map<String, dynamic>).secrets;
  }

  Future<void> addServiceAccountPullSecret(String projectId, String serviceAccountId, String secretId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedServiceAccountId = Uri.encodeComponent(serviceAccountId);
    final encodedSecretId = Uri.encodeComponent(secretId);
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/service-accounts/$encodedServiceAccountId/pull-secrets/$encodedSecretId',
    );
    final response = await httpClient.put(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to add service account pull secret. Status code: ${response.statusCode}, body: ${response.body}');
    }
  }

  Future<void> removeServiceAccountPullSecret(String projectId, String serviceAccountId, String secretId) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedServiceAccountId = Uri.encodeComponent(serviceAccountId);
    final encodedSecretId = Uri.encodeComponent(secretId);
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/service-accounts/$encodedServiceAccountId/pull-secrets/$encodedSecretId',
    );
    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException('Failed to remove service account pull secret. Status code: ${response.statusCode}, body: ${response.body}');
    }
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

  Future<List<RoomSession>> listRecentRoomSessions(String projectId, String roomName, {int limit = 25}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedRoomName = Uri.encodeComponent(roomName);
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/rooms/$encodedRoomName/sessions',
    ).replace(queryParameters: {'limit': '$limit'});
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list recent room sessions. '
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

  Future<List<RoomSession>> listRecentSingleAgentSessions(String projectId, String agentName, {int limit = 25}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedAgentName = Uri.encodeComponent(agentName);
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/agents/$encodedAgentName/sessions',
    ).replace(queryParameters: {'limit': '$limit'});
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

    if (response.statusCode == 404) {
      throw NotFoundException('session not live: $sessionId');
    }
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

  /// GET /accounts/projects/{project_id}/rooms?page_size=&offset=&order_by=&filter=
  Future<List<Room>> listRooms({
    required String projectId,
    int pageSize = 100,
    String? continuationToken,
    String? filter,
    String? view,
  }) async {
    final page = await listRoomsPage(
      projectId: projectId,
      pageSize: pageSize,
      continuationToken: continuationToken,
      filter: filter,
      view: view,
    );
    return page.rooms;
  }

  /// GET /accounts/projects/{project_id}/rooms?page_size=&continuation_token=&filter=&view=
  Future<RoomsPage> listRoomsPage({
    required String projectId,
    int pageSize = 100,
    String? filter,
    String? view,
    String? continuationToken,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final queryParameters = {'page_size': '$pageSize'};
    if (filter != null) {
      queryParameters['filter'] = filter;
    }
    if (view != null) {
      queryParameters['view'] = view;
    }
    if (continuationToken != null) {
      queryParameters['continuation_token'] = continuationToken;
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
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/rooms');
    final body = _jsonMapWithoutNulls({'name': name, 'if_not_exists': ifNotExists, 'metadata': metadata, 'annotations': annotations});
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

  Future<Group> createGroup({
    required String projectId,
    required String name,
    Map<String, dynamic>? metadata,
    Map<String, String>? annotations,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/groups');
    final body = _jsonMapWithoutNulls({'name': name, 'metadata': metadata, 'annotations': annotations});
    final response = await httpClient.post(uri, body: jsonEncode(body));

    if (response.statusCode == 409) {
      throw NameInUseException("The group name is already in use");
    } else if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to create group. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return Group.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Group> getGroup({required String projectId, required String groupId}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedGroupId = Uri.encodeComponent(groupId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/groups/$encodedGroupId');
    final response = await httpClient.get(uri);

    if (response.statusCode == 404) {
      throw NotFoundException('group not found');
    }
    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to get group. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return Group.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> updateGroup({
    required String projectId,
    required String groupId,
    required String name,
    Map<String, dynamic>? metadata,
    Map<String, String>? annotations,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedGroupId = Uri.encodeComponent(groupId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/groups/$encodedGroupId');
    final body = _jsonMapWithoutNulls({'name': name, 'metadata': metadata, 'annotations': annotations});
    final response = await httpClient.put(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to update group. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<void> deleteGroup({required String projectId, required String groupId}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedGroupId = Uri.encodeComponent(groupId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/groups/$encodedGroupId');
    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to delete group. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<GroupsPage> listGroupsPage({required String projectId, int pageSize = 50, String? continuationToken, String? filter}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/groups',
    ).replace(queryParameters: {'page_size': '$pageSize', 'continuation_token': ?continuationToken, 'filter': ?filter});
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list groups. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return GroupsPage.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<Group>> listGroups({required String projectId, int pageSize = 50, String? continuationToken, String? filter}) async {
    final page = await listGroupsPage(projectId: projectId, pageSize: pageSize, continuationToken: continuationToken, filter: filter);
    return page.groups;
  }

  Future<void> setGroupMember({
    required String projectId,
    required String groupId,
    required AccessSubject subject,
    String role = 'member',
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedGroupId = Uri.encodeComponent(groupId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/groups/$encodedGroupId/members');
    final response = await httpClient.post(uri, body: jsonEncode({'subject': subject.toJson(), 'role': role}));

    if (response.statusCode >= 400) {
      throw MeshagentException.fromResponse('Failed to set group member.', response);
    }
  }

  Future<GroupMembersPage> listGroupMembersPage({
    required String projectId,
    required String groupId,
    int pageSize = 50,
    String? continuationToken,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedGroupId = Uri.encodeComponent(groupId);
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/groups/$encodedGroupId/members',
    ).replace(queryParameters: {'page_size': '$pageSize', 'continuation_token': ?continuationToken});
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list group members. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return GroupMembersPage.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<GroupMember>> listGroupMembers({
    required String projectId,
    required String groupId,
    int pageSize = 50,
    String? continuationToken,
  }) async {
    final page = await listGroupMembersPage(
      projectId: projectId,
      groupId: groupId,
      pageSize: pageSize,
      continuationToken: continuationToken,
    );
    return page.members;
  }

  Future<void> deleteGroupMember({
    required String projectId,
    required String groupId,
    required String subjectType,
    required String subjectId,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedGroupId = Uri.encodeComponent(groupId);
    final encodedSubjectType = Uri.encodeComponent(subjectType);
    final encodedSubjectId = Uri.encodeComponent(subjectId);
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/groups/$encodedGroupId/members/$encodedSubjectType/$encodedSubjectId',
    );
    final response = await httpClient.delete(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to delete group member. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<ManagedAgent> createAgent({
    required String projectId,
    required Map<String, dynamic> configuration,
    bool ifNotExists = false,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/agents');
    final body = {'configuration': _jsonMapWithoutNulls(configuration), 'if_not_exists': ifNotExists};
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
    int pageSize = 100,
    String? filter,
    String? view,
    String? continuationToken,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final queryParameters = {'page_size': '$pageSize'};
    if (filter != null) {
      queryParameters['filter'] = filter;
    }
    if (view != null) {
      queryParameters['view'] = view;
    }
    if (continuationToken != null) {
      queryParameters['continuation_token'] = continuationToken;
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
    int pageSize = 100,
    String? continuationToken,
    String? filter,
    String? view,
  }) async {
    final page = await listAgentsPage(
      projectId: projectId,
      pageSize: pageSize,
      continuationToken: continuationToken,
      filter: filter,
      view: view,
    );
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

  Future<AccessTestResult> testAccess({
    required String projectId,
    required AccessSubject subject,
    required AccessResource resource,
    required String relation,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/access:test');
    final response = await httpClient.post(
      uri,
      body: jsonEncode({'subject': subject.toJson(), 'resource': resource.toJson(), 'relation': relation}),
    );

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to test access. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return AccessTestResult.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<EffectiveAccess> getEffectiveAccess({
    required String projectId,
    required AccessSubject subject,
    required AccessResource resource,
    List<String>? relations,
  }) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/access:effective');
    final response = await httpClient.post(
      uri,
      body: jsonEncode({'subject': subject.toJson(), 'resource': resource.toJson(), 'relations': ?relations}),
    );

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to get effective access. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return EffectiveAccess.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<AccessBindingsPage> listAccessBindingsPage({required String projectId, required AccessSubject subject}) async {
    final encodedProjectId = Uri.encodeComponent(projectId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/access:bindings');
    final response = await httpClient.post(uri, body: jsonEncode({'subject': subject.toJson()}));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to list access bindings. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return AccessBindingsPage.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<ProjectAccessGrant>> listAccessBindings({required String projectId, required AccessSubject subject}) async {
    final page = await listAccessBindingsPage(projectId: projectId, subject: subject);
    return page.accessGrants;
  }

  Future<ResourcePolicyPage> getResourcePolicyPage({
    required String projectId,
    required String resourceType,
    required String resourceId,
    int pageSize = 50,
    String? continuationToken,
  }) async {
    _validateResourcePolicyType(resourceType);
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedResourceType = Uri.encodeComponent(resourceType);
    final encodedResourceId = Uri.encodeComponent(resourceId);
    final uri = Uri.parse(
      '$baseUrl/accounts/projects/$encodedProjectId/iam/$encodedResourceType/$encodedResourceId/policy',
    ).replace(queryParameters: {'page_size': '$pageSize', 'continuation_token': ?continuationToken});
    final response = await httpClient.get(uri);

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to get resource policy. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return ResourcePolicyPage.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<ProjectRoomGrant>> getResourcePolicy({
    required String projectId,
    required String resourceType,
    required String resourceId,
    int pageSize = 50,
    String? continuationToken,
  }) async {
    final grants = <ProjectRoomGrant>[];
    var nextToken = continuationToken;
    do {
      final page = await getResourcePolicyPage(
        projectId: projectId,
        resourceType: resourceType,
        resourceId: resourceId,
        pageSize: pageSize,
        continuationToken: nextToken,
      );
      grants.addAll(page.accessGrants);
      nextToken = page.continuationToken;
    } while (nextToken != null);
    return grants;
  }

  Future<void> grantResourcePolicy({
    required String projectId,
    required String resourceType,
    required String resourceId,
    required AccessSubject subject,
    required List<String> roles,
    Uri? inviteRedirectUrl,
  }) async {
    _validateResourcePolicyType(resourceType);
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedResourceType = Uri.encodeComponent(resourceType);
    final encodedResourceId = Uri.encodeComponent(resourceId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/iam/$encodedResourceType/$encodedResourceId/policy:grant');
    final body = {'subject': subject.toJson(), 'roles': roles, 'invite_redirect_url': ?inviteRedirectUrl?.toString()};
    final response = await httpClient.post(uri, body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to grant resource policy. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  Future<void> revokeResourcePolicy({
    required String projectId,
    required String resourceType,
    required String resourceId,
    required AccessSubject subject,
  }) async {
    _validateResourcePolicyType(resourceType);
    final encodedProjectId = Uri.encodeComponent(projectId);
    final encodedResourceType = Uri.encodeComponent(resourceType);
    final encodedResourceId = Uri.encodeComponent(resourceId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$encodedProjectId/iam/$encodedResourceType/$encodedResourceId/policy:revoke');
    final response = await httpClient.post(uri, body: jsonEncode({'subject': subject.toJson()}));

    if (response.statusCode >= 400) {
      throw MeshagentException(
        'Failed to revoke resource policy. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  static void _validateResourcePolicyType(String resourceType) {
    if (resourceType == 'agent') {
      throw ArgumentError.value(
        resourceType,
        'resourceType',
        'managed agent resource policies are not supported; use agent run_as instead',
      );
    }
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

  /// GET /accounts/projects/{project_id}/scheduled-tasks?room_id=&task_id=&active=&page_size=&offset=
  /// Returns { "tasks": [ ... ] }
  Future<ScheduledTasksPage> listScheduledTasksPage({
    required String projectId,
    String? roomId,
    String? taskId,
    bool? active,
    int pageSize = 100,
    int offset = 0,
    String? continuationToken,
    String? filter,
  }) async {
    final qp = <String, String>{'page_size': '$pageSize'};
    if (roomId != null) {
      qp['room_id'] = roomId;
      qp['offset'] = '$offset';
    } else if (continuationToken != null) {
      qp['continuation_token'] = continuationToken;
    }
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
    int pageSize = 100,
    int offset = 0,
    String? continuationToken,
    String? filter,
  }) async {
    final page = await listScheduledTasksPage(
      projectId: projectId,
      roomId: roomId,
      taskId: taskId,
      active: active,
      pageSize: pageSize,
      offset: offset,
      continuationToken: continuationToken,
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

List<String> _projectRolesFromFlags({
  bool? isAdmin,
  bool? isDeveloper,
  bool? canCreateRooms,
  bool? canCreateAgents,
  bool? canUseLlmProxy,
  bool? canCreateMailboxes,
  bool? canCreateRoutes,
  bool? canCreateScheduledTasks,
}) {
  return [
    'member',
    if (isAdmin == true) 'admin',
    if (isDeveloper == true) 'developer',
    if (canCreateRooms == true) 'room_creator',
    if (canCreateAgents == true) 'agent_creator',
    if (canCreateMailboxes == true) 'mailbox_creator',
    if (canCreateRoutes == true) 'route_creator',
    if (canCreateScheduledTasks == true) 'scheduled_task_creator',
    if (canUseLlmProxy == true) 'llm_proxy_user',
  ];
}

String resourceRoleFromApiScope(ApiScope scope) {
  if (scope.admin != null) return 'admin';
  if (scope.developer != null || scope.tunnels != null) return 'developer';
  return 'operator';
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
  final String? continuationToken;

  RoomsPage({required this.rooms, required this.total, this.continuationToken});

  factory RoomsPage.fromJson(Map<String, dynamic> json) {
    final list = json['rooms'] as List<dynamic>? ?? [];
    final rooms = list.whereType<Map<String, dynamic>>().map(Room.fromJson).toList();
    return RoomsPage(
      rooms: rooms,
      total: json.containsKey('total') ? _parseInt(json['total']) : rooms.length,
      continuationToken: json['continuation_token'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'rooms': rooms.map((room) => room.toJson()).toList(),
    'total': total,
    'continuation_token': ?continuationToken,
  };
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
  final String? continuationToken;

  AgentsPage({required this.agents, required this.total, this.continuationToken});

  factory AgentsPage.fromJson(Map<String, dynamic> json) {
    final list = json['agents'] as List<dynamic>? ?? [];
    final agents = list.whereType<Map<String, dynamic>>().map(ManagedAgent.fromJson).toList();
    return AgentsPage(
      agents: agents,
      total: json.containsKey('total') ? _parseInt(json['total']) : agents.length,
      continuationToken: json['continuation_token'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'agents': agents.map((agent) => agent.toJson()).toList(),
    'total': total,
    'continuation_token': ?continuationToken,
  };
}

class ProjectMembersPage {
  final List<ProjectMember> users;
  final String? continuationToken;

  ProjectMembersPage({required this.users, this.continuationToken});

  factory ProjectMembersPage.fromJson(Map<String, dynamic> json) {
    final list = json['users'] as List<dynamic>? ?? [];
    return ProjectMembersPage(
      users: list.whereType<Map<String, dynamic>>().map(ProjectMember.fromJson).toList(),
      continuationToken: json['continuation_token'] as String?,
    );
  }
}

class ProjectMember {
  final String id;
  final String email;
  final String? firstName;
  final String? lastName;
  final List<String> directRoles;

  const ProjectMember({required this.id, required this.email, this.firstName, this.lastName, List<String>? directRoles})
    : directRoles = directRoles ?? const [];

  factory ProjectMember.fromJson(Map<String, dynamic> json) {
    final user = (json['user'] as Map?)?.cast<String, dynamic>() ?? json;
    final directRoles = (json['direct_roles'] as List? ?? json['roles'] as List? ?? const []).whereType<String>().toList();
    return ProjectMember(
      id: user['id'] as String? ?? '',
      email: user['email'] as String? ?? '',
      firstName: user['first_name'] as String?,
      lastName: user['last_name'] as String?,
      directRoles: directRoles,
    );
  }

  Map<String, dynamic> toJson() => {
    'user': {'id': id, 'email': email, if (firstName != null) 'first_name': firstName, if (lastName != null) 'last_name': lastName},
    'direct_roles': directRoles,
  };
}

class AccessSubject {
  final String type;
  final String id;
  final String? name;
  final String? firstName;
  final String? lastName;
  final String? email;
  final String? objectType;
  final String? relation;

  const AccessSubject({
    required this.type,
    required this.id,
    this.name,
    this.firstName,
    this.lastName,
    this.email,
    this.objectType,
    this.relation,
  });

  factory AccessSubject.fromJson(Map<String, dynamic> json) {
    return AccessSubject(
      type: json['type'] as String,
      id: json['id'] as String,
      name: json['name'] as String?,
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      email: json['email'] as String?,
      objectType: json['object_type'] as String?,
      relation: json['relation'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'id': id,
    if (name != null) 'name': name,
    if (firstName != null) 'first_name': firstName,
    if (lastName != null) 'last_name': lastName,
    if (email != null) 'email': email,
    if (objectType != null) 'object_type': objectType,
    if (relation != null) 'relation': relation,
  };
}

class AccessResource {
  final String type;
  final String id;
  final String? name;
  final Map<String, dynamic>? metadata;
  final Map<String, String>? annotations;

  const AccessResource({required this.type, required this.id, this.name, this.metadata, this.annotations});

  factory AccessResource.fromJson(Map<String, dynamic> json) {
    return AccessResource(
      type: json['type'] as String,
      id: json['id'] as String,
      name: json['name'] as String?,
      metadata: (json['metadata'] as Map?)?.cast<String, dynamic>(),
      annotations: (json['annotations'] as Map?)?.cast<String, String>(),
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'id': id,
    if (name != null) 'name': name,
    if (metadata != null) 'metadata': metadata,
    if (annotations != null) 'annotations': annotations,
  };
}

class AccessTestResult {
  final bool allowed;
  final AccessResource? resource;
  final AccessSubject? subject;
  final String? relation;

  const AccessTestResult({required this.allowed, this.resource, this.subject, this.relation});

  factory AccessTestResult.fromJson(Map<String, dynamic> json) {
    return AccessTestResult(
      allowed: json['allowed'] == true,
      resource: json['resource'] is Map ? AccessResource.fromJson((json['resource'] as Map).cast<String, dynamic>()) : null,
      subject: json['subject'] is Map ? AccessSubject.fromJson((json['subject'] as Map).cast<String, dynamic>()) : null,
      relation: json['relation'] as String?,
    );
  }
}

class EffectiveAccess {
  final AccessResource resource;
  final AccessSubject subject;
  final List<String> effectiveRoles;
  final Map<String, bool> capabilities;

  const EffectiveAccess({required this.resource, required this.subject, required this.effectiveRoles, required this.capabilities});

  factory EffectiveAccess.fromJson(Map<String, dynamic> json) {
    return EffectiveAccess(
      resource: AccessResource.fromJson((json['resource'] as Map).cast<String, dynamic>()),
      subject: AccessSubject.fromJson((json['subject'] as Map).cast<String, dynamic>()),
      effectiveRoles: (json['effective_roles'] as List? ?? const []).whereType<String>().toList(),
      capabilities: (json['capabilities'] as Map? ?? const {}).map((key, value) => MapEntry(key.toString(), value == true)),
    );
  }
}

class Group {
  final String id;
  final String name;
  final String? displayName;
  final String? email;
  final Map<String, dynamic> metadata;
  final Map<String, String> annotations;

  const Group({required this.id, required this.name, this.displayName, this.email, this.metadata = const {}, this.annotations = const {}});

  factory Group.fromJson(Map<String, dynamic> json) {
    final metadata = (json['metadata'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    return Group(
      id: json['id'] as String,
      name: json['name'] as String,
      displayName: _jsonString(metadata['display_name']) ?? _jsonString(metadata['name']) ?? json['display_name'] as String?,
      email: json['email'] as String?,
      metadata: metadata,
      annotations: (json['annotations'] as Map?)?.cast<String, String>() ?? const {},
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (displayName != null) 'display_name': displayName,
    if (email != null) 'email': email,
    'metadata': metadata,
    'annotations': annotations,
  };
}

class GroupsPage {
  final List<Group> groups;
  final String? continuationToken;

  const GroupsPage({required this.groups, this.continuationToken});

  factory GroupsPage.fromJson(Map<String, dynamic> json) {
    final list = json['groups'] as List<dynamic>? ?? [];
    return GroupsPage(
      groups: list.whereType<Map<String, dynamic>>().map(Group.fromJson).toList(),
      continuationToken: json['continuation_token'] as String?,
    );
  }
}

class GroupMember {
  final AccessSubject subject;
  final List<String> directRoles;

  const GroupMember({required this.subject, List<String>? directRoles}) : directRoles = directRoles ?? const [];

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      subject: AccessSubject.fromJson((json['subject'] as Map).cast<String, dynamic>()),
      directRoles: (json['direct_roles'] as List? ?? const []).whereType<String>().toList(),
    );
  }
}

class ServiceAccount {
  final String id;
  final String projectId;
  final String key;
  final String name;
  final String? displayName;
  final String? email;
  final String description;
  final Map<String, dynamic> metadata;
  final Map<String, String> annotations;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdByUserId;

  const ServiceAccount({
    required this.id,
    required this.projectId,
    required this.key,
    required this.name,
    this.displayName,
    this.email,
    this.description = '',
    this.metadata = const {},
    this.annotations = const {},
    this.createdAt,
    this.updatedAt,
    this.createdByUserId,
  });

  factory ServiceAccount.fromJson(Map<String, dynamic> json) {
    final metadata = (json['metadata'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    return ServiceAccount(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      key: json['key'] as String? ?? json['name'] as String,
      name: json['name'] as String,
      displayName: _jsonString(metadata['display_name']) ?? _jsonString(metadata['name']) ?? json['display_name'] as String?,
      email: json['email'] as String?,
      description: json['description'] as String? ?? '',
      metadata: metadata,
      annotations: (json['annotations'] as Map?)?.cast<String, String>() ?? const {},
      createdAt: json['created_at'] is String ? DateTime.tryParse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] is String ? DateTime.tryParse(json['updated_at'] as String) : null,
      createdByUserId: json['created_by_user_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'project_id': projectId,
    'key': key,
    'name': name,
    if (displayName != null) 'display_name': displayName,
    if (email != null) 'email': email,
    'description': description,
    'metadata': metadata,
    'annotations': annotations,
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    if (createdByUserId != null) 'created_by_user_id': createdByUserId,
  };
}

class ServiceAccountsPage {
  final List<ServiceAccount> serviceAccounts;
  final String? continuationToken;

  const ServiceAccountsPage({required this.serviceAccounts, this.continuationToken});

  factory ServiceAccountsPage.fromJson(Map<String, dynamic> json) {
    final list = json['service_accounts'] as List<dynamic>? ?? [];
    return ServiceAccountsPage(
      serviceAccounts: list.whereType<Map<String, dynamic>>().map(ServiceAccount.fromJson).toList(),
      continuationToken: json['continuation_token'] as String?,
    );
  }
}

class GroupMembersPage {
  final List<GroupMember> members;
  final String? continuationToken;

  const GroupMembersPage({required this.members, this.continuationToken});

  factory GroupMembersPage.fromJson(Map<String, dynamic> json) {
    final list = json['members'] as List<dynamic>? ?? [];
    return GroupMembersPage(
      members: list.whereType<Map<String, dynamic>>().map(GroupMember.fromJson).toList(),
      continuationToken: json['continuation_token'] as String?,
    );
  }
}

class ProjectAccessGrant {
  final AccessResource resource;
  final AccessSubject subject;
  final List<String> directRoles;

  ProjectAccessGrant({required this.resource, required this.subject, List<String>? directRoles}) : directRoles = directRoles ?? const [];

  factory ProjectAccessGrant.fromJson(Map<String, dynamic> json) {
    return ProjectAccessGrant(
      resource: AccessResource.fromJson((json['resource'] as Map).cast<String, dynamic>()),
      subject: AccessSubject.fromJson((json['subject'] as Map).cast<String, dynamic>()),
      directRoles: (json['direct_roles'] as List? ?? const []).whereType<String>().toList(),
    );
  }

  Map<String, dynamic> toJson() => {'resource': resource.toJson(), 'subject': subject.toJson(), 'direct_roles': directRoles};
}

class AccessBindingsPage {
  final List<ProjectAccessGrant> accessGrants;
  final String? continuationToken;

  AccessBindingsPage({required this.accessGrants, this.continuationToken});

  factory AccessBindingsPage.fromJson(Map<String, dynamic> json) {
    final list = json['access_grants'] as List<dynamic>? ?? [];
    return AccessBindingsPage(
      accessGrants: list.whereType<Map<String, dynamic>>().map(ProjectAccessGrant.fromJson).toList(),
      continuationToken: json['continuation_token'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'access_grants': accessGrants.map((grant) => grant.toJson()).toList(),
    'continuation_token': ?continuationToken,
  };
}

class ResourcePolicyPage {
  final AccessResource resource;
  final List<ProjectRoomGrant> accessGrants;
  final String? continuationToken;

  const ResourcePolicyPage({required this.resource, required this.accessGrants, this.continuationToken});

  factory ResourcePolicyPage.fromJson(Map<String, dynamic> json) {
    final list = json['access_grants'] as List<dynamic>? ?? [];
    return ResourcePolicyPage(
      resource: AccessResource.fromJson((json['resource'] as Map).cast<String, dynamic>()),
      accessGrants: list.whereType<Map<String, dynamic>>().map(ProjectRoomGrant.fromJson).toList(),
      continuationToken: json['continuation_token'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'resource': resource.toJson(),
    'access_grants': accessGrants.map((grant) => grant.toJson()).toList(),
    'continuation_token': ?continuationToken,
  };
}

class ProjectRoomGrant {
  final AccessResource resource;
  final AccessSubject subject;
  final List<String> directRoles;

  ProjectRoomGrant({required this.resource, required this.subject, List<String>? directRoles}) : directRoles = directRoles ?? const [];

  Room get room => Room(
    id: resource.id,
    name: resource.name ?? resource.id,
    metadata: resource.metadata ?? const {},
    annotations: resource.annotations ?? const {},
  );
  String get userId => subject.id;
  ApiScope get permissions {
    if (directRoles.contains('admin')) return ApiScope.full();
    if (directRoles.contains('developer')) return ApiScope.full();
    return ApiScope.userDefault();
  }

  factory ProjectRoomGrant.fromJson(Map<String, dynamic> json) {
    return ProjectRoomGrant(
      resource: AccessResource.fromJson((json['resource'] as Map).cast<String, dynamic>()),
      subject: AccessSubject.fromJson((json['subject'] as Map).cast<String, dynamic>()),
      directRoles: (json['direct_roles'] as List? ?? const []).whereType<String>().toList(),
    );
  }

  Map<String, dynamic> toJson() => {'resource': resource.toJson(), 'subject': subject.toJson(), 'direct_roles': directRoles};
}

/// A simple custom exception to denote HTTP errors.
class MeshagentException implements Exception {
  final String message;
  final int? statusCode;
  final String? errorCode;
  final String? errorMessage;

  MeshagentException(this.message, {this.statusCode, this.errorCode, this.errorMessage});

  factory MeshagentException.fromResponse(String message, http.Response response) {
    final parsed = _parseErrorResponseBody(response.body);
    return MeshagentException(
      '$message Status code: ${response.statusCode}, body: ${response.body}',
      statusCode: response.statusCode,
      errorCode: parsed.code,
      errorMessage: parsed.message,
    );
  }

  String get displayMessage => errorMessage ?? message;

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

class ApiKeysRevocationResult {
  ApiKeysRevocationResult({required this.revoked});

  final List<String> revoked;

  static ApiKeysRevocationResult fromJson(Map<String, dynamic> json) {
    return ApiKeysRevocationResult(revoked: ((json['revoked'] as List?) ?? const []).map((item) => item.toString()).toList());
  }
}

class ApiKeyInfo {
  ApiKeyInfo({required this.id, required this.name, this.description, required this.value, required this.serviceAccountId});

  final String id;
  final String name;
  final String? description;
  final String value;
  final String serviceAccountId;

  static ApiKeyInfo fromJson(Map<String, dynamic> json) {
    return ApiKeyInfo(
      id: json["id"],
      name: json["name"],
      description: json["description"],
      value: json["value"],
      serviceAccountId: json["service_account_id"],
    );
  }
}

class Secret {
  Secret({
    required this.id,
    required this.projectId,
    this.ownerUserId,
    this.ownerServiceAccountId,
    this.createdByUserId,
    this.createdByServiceAccountId,
    required this.type,
    required this.name,
    required this.httpOnly,
    required this.metadata,
    required this.annotations,
    this.currentVersionId,
    this.valueBase64,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String projectId;
  final String? ownerUserId;
  final String? ownerServiceAccountId;
  final String? createdByUserId;
  final String? createdByServiceAccountId;
  final String type;
  final String name;
  final bool httpOnly;
  final Map<String, dynamic> metadata;
  final Map<String, dynamic> annotations;
  final String? currentVersionId;
  final String? valueBase64;
  final DateTime createdAt;
  final DateTime updatedAt;

  static Secret fromJson(Map<String, dynamic> json) {
    return Secret(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      ownerUserId: json['owner_user_id'] as String?,
      ownerServiceAccountId: json['owner_service_account_id'] as String?,
      createdByUserId: json['created_by_user_id'] as String?,
      createdByServiceAccountId: json['created_by_service_account_id'] as String?,
      type: json['type'] as String,
      name: json['name'] as String,
      httpOnly: json['http_only'] as bool? ?? false,
      metadata: (json['metadata'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
      annotations: (json['annotations'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
      currentVersionId: json['current_version_id'] as String?,
      valueBase64: json['value_base64'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

class SecretVersion {
  SecretVersion({
    required this.id,
    required this.secretId,
    required this.version,
    this.valueSha256,
    this.createdByUserId,
    this.createdByServiceAccountId,
    required this.createdAt,
  });

  final String id;
  final String secretId;
  final int version;
  final String? valueSha256;
  final String? createdByUserId;
  final String? createdByServiceAccountId;
  final DateTime createdAt;

  static SecretVersion fromJson(Map<String, dynamic> json) {
    return SecretVersion(
      id: json['id'] as String,
      secretId: json['secret_id'] as String,
      version: json['version'] as int,
      valueSha256: json['value_sha256'] as String?,
      createdByUserId: json['created_by_user_id'] as String?,
      createdByServiceAccountId: json['created_by_service_account_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class SecretsPage {
  SecretsPage({required this.secrets, this.continuationToken});

  final List<Secret> secrets;
  final String? continuationToken;

  static SecretsPage fromJson(Map<String, dynamic> json) {
    return SecretsPage(
      secrets: ((json['secrets'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => Secret.fromJson(item.cast<String, dynamic>()))
          .toList(),
      continuationToken: json['continuation_token'] as String?,
    );
  }
}

class SecretVersionsPage {
  SecretVersionsPage({required this.versions});

  final List<SecretVersion> versions;

  static SecretVersionsPage fromJson(Map<String, dynamic> json) {
    return SecretVersionsPage(
      versions: ((json['versions'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => SecretVersion.fromJson(item.cast<String, dynamic>()))
          .toList(),
    );
  }
}

class SecretProxyAccessGrant {
  SecretProxyAccessGrant({required this.subject, required this.roles});

  final AccessSubject subject;
  final List<String> roles;

  static SecretProxyAccessGrant fromJson(Map<String, dynamic> json) {
    return SecretProxyAccessGrant(
      subject: AccessSubject.fromJson((json['subject'] as Map).cast<String, dynamic>()),
      roles: ((json['roles'] as List?) ?? const []).map((item) => item.toString()).toList(),
    );
  }
}

class SecretProxyAccessGrantsPage {
  SecretProxyAccessGrantsPage({required this.accessGrants, this.continuationToken});

  final List<SecretProxyAccessGrant> accessGrants;
  final String? continuationToken;

  static SecretProxyAccessGrantsPage fromJson(Map<String, dynamic> json) {
    return SecretProxyAccessGrantsPage(
      accessGrants: ((json['access_grants'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => SecretProxyAccessGrant.fromJson(item.cast<String, dynamic>()))
          .toList(),
      continuationToken: json['continuation_token'] as String?,
    );
  }
}
