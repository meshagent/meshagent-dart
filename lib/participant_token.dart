import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'api_keys.dart';

/// ---------------------------
/// Helpers
/// ---------------------------

int _semverCompare(String a, String b) {
  // Compare "0.6.0" style strings
  List<int> pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  List<int> pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  while (pa.length < 3) {
    pa.add(0);
  }
  while (pb.length < 3) {
    pb.add(0);
  }
  for (var i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i] - pb[i];
  }
  return 0;
}

bool _hasWildcardSuffix(String s) => s.endsWith('*');
String _stripWildcardSuffix(String s) => _hasWildcardSuffix(s) ? s.substring(0, s.length - 1) : s;

/// ---------------------------
/// Grant Types (mirror Python)
/// ---------------------------

class AgentsGrant {
  final bool registerAgent;
  final bool registerPublicToolkit;
  final bool registerPrivateToolkit;
  final bool call;
  final bool useAgents;
  final bool useTools;
  final List<String>? allowedToolkits;

  AgentsGrant({
    this.registerAgent = true,
    this.registerPublicToolkit = true,
    this.registerPrivateToolkit = true,
    this.call = true,
    this.useAgents = true,
    this.useTools = true,
    this.allowedToolkits,
  });

  Map<String, dynamic> toJson() => {
    'register_agent': registerAgent,
    'register_public_toolkit': registerPublicToolkit,
    'register_private_toolkit': registerPrivateToolkit,
    'call': call,
    'use_agents': useAgents,
    'use_tools': useTools,
    'allowed_toolkits': allowedToolkits,
  };

  factory AgentsGrant.fromJson(Map<String, dynamic> j) => AgentsGrant(
    registerAgent: j['register_agent'] ?? true,
    registerPublicToolkit: j['register_public_toolkit'] ?? true,
    registerPrivateToolkit: j['register_private_toolkit'] ?? true,
    call: j['call'] ?? true,
    useAgents: j['use_agents'] ?? true,
    useTools: j['use_tools'] ?? true,
    allowedToolkits: j['allowed_toolkits'] == null ? null : (j['allowed_toolkits'] as List).cast<String>().toList(),
  );
}

class LivekitGrant {
  final List<String>? breakoutRooms;

  LivekitGrant({this.breakoutRooms});

  bool canJoinBreakoutRoom(String name) => breakoutRooms == null || breakoutRooms!.contains(name);

  Map<String, dynamic> toJson() => {if (breakoutRooms != null) 'breakout_rooms': breakoutRooms};

  factory LivekitGrant.fromJson(Map<String, dynamic> j) => LivekitGrant(breakoutRooms: (j['breakout_rooms'] as List?)?.cast<String>());
}

class QueuesGrant {
  final List<String>? send;
  final List<String>? receive;
  final bool list;

  QueuesGrant({this.send, this.receive, this.list = true});

  bool canSend(String queue) => send == null || send!.contains(queue);
  bool canReceive(String queue) => receive == null || receive!.contains(queue);

  Map<String, dynamic> toJson() => {if (send != null) 'send': send, if (receive != null) 'receive': receive, 'list': list};

  factory QueuesGrant.fromJson(Map<String, dynamic> j) =>
      QueuesGrant(send: (j['send'] as List?)?.cast<String>(), receive: (j['receive'] as List?)?.cast<String>(), list: j['list'] ?? true);
}

class MessagingGrant {
  final bool broadcast;
  final bool list;
  final bool send;

  MessagingGrant({this.broadcast = true, this.list = true, this.send = true});

  Map<String, dynamic> toJson() => {'broadcast': broadcast, 'list': list, 'send': send};

  factory MessagingGrant.fromJson(Map<String, dynamic> j) =>
      MessagingGrant(broadcast: j['broadcast'] ?? true, list: j['list'] ?? true, send: j['send'] ?? true);
}

class TableGrant {
  final String name;
  final bool write;
  final bool read;
  final bool alter;

  TableGrant({required this.name, this.write = false, this.read = true, this.alter = false});

  Map<String, dynamic> toJson() => {'name': name, 'write': write, 'read': read, 'alter': alter};

  factory TableGrant.fromJson(Map<String, dynamic> j) =>
      TableGrant(name: j['name'], write: j['write'] ?? false, read: j['read'] ?? true, alter: j['alter'] ?? false);
}

class DatabaseGrant {
  final List<TableGrant>? tables;
  final bool listTables;

  DatabaseGrant({this.tables, this.listTables = true});

  bool canWrite(String table) {
    if (tables == null) return true;
    for (final t in tables!) {
      if (t.name == table) return t.write;
    }
    return false;
  }

  bool canRead(String table) {
    if (tables == null) return true;
    for (final t in tables!) {
      if (t.name == table) return t.read;
    }
    return false;
  }

  bool canAlter(String table) {
    if (tables == null) return true;
    for (final t in tables!) {
      if (t.name == table) return t.alter;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {if (tables != null) 'tables': tables!.map((e) => e.toJson()).toList(), 'list_tables': listTables};

  factory DatabaseGrant.fromJson(Map<String, dynamic> j) => DatabaseGrant(
    tables: (j['tables'] as List?)?.map((e) => TableGrant.fromJson(e as Map<String, dynamic>)).toList(),
    listTables: j['list_tables'] ?? true,
  );
}

class MemoryGrant {
  final bool list;
  final bool create;
  final bool drop;
  final bool inspect;
  final bool query;
  final bool upsert;
  final bool ingest;
  final bool recall;
  final bool optimize;

  MemoryGrant({
    this.list = true,
    this.create = true,
    this.drop = true,
    this.inspect = true,
    this.query = true,
    this.upsert = true,
    this.ingest = true,
    this.recall = true,
    this.optimize = true,
  });

  Map<String, dynamic> toJson() => {
    'list': list,
    'create': create,
    'drop': drop,
    'inspect': inspect,
    'query': query,
    'upsert': upsert,
    'ingest': ingest,
    'recall': recall,
    'optimize': optimize,
  };

  factory MemoryGrant.fromJson(Map<String, dynamic> j) => MemoryGrant(
    list: j['list'] ?? true,
    create: j['create'] ?? true,
    drop: j['drop'] ?? true,
    inspect: j['inspect'] ?? true,
    query: j['query'] ?? true,
    upsert: j['upsert'] ?? true,
    ingest: j['ingest'] ?? true,
    recall: j['recall'] ?? true,
    optimize: j['optimize'] ?? true,
  );
}

class SyncPathGrant {
  final String path;
  final bool readOnly;

  SyncPathGrant({required this.path, this.readOnly = false});

  Map<String, dynamic> toJson() => {'path': path, 'read_only': readOnly};

  factory SyncPathGrant.fromJson(Map<String, dynamic> j) => SyncPathGrant(path: j['path'], readOnly: j['read_only'] ?? false);
}

class SyncGrant {
  final List<SyncPathGrant>? paths;

  SyncGrant({this.paths});

  bool _matches(String base, String path) => base == path || (_hasWildcardSuffix(base) && path.startsWith(_stripWildcardSuffix(base)));

  bool canRead(String path) {
    if (paths == null) return true;
    for (final t in paths!) {
      if (_matches(t.path, path)) return true;
    }
    return false;
  }

  bool canWrite(String path) {
    if (paths == null) return true;
    for (final t in paths!) {
      if (_matches(t.path, path)) return !t.readOnly;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {if (paths != null) 'paths': paths!.map((e) => e.toJson()).toList()};

  factory SyncGrant.fromJson(Map<String, dynamic> j) =>
      SyncGrant(paths: (j['paths'] as List?)?.map((e) => SyncPathGrant.fromJson(e as Map<String, dynamic>)).toList());
}

class StoragePathGrant {
  final String path;
  final bool readOnly;

  StoragePathGrant({required this.path, this.readOnly = false});

  Map<String, dynamic> toJson() => {'path': path, 'read_only': readOnly};

  factory StoragePathGrant.fromJson(Map<String, dynamic> j) => StoragePathGrant(path: j['path'], readOnly: j['read_only'] ?? false);
}

class StorageGrant {
  final List<StoragePathGrant>? paths;

  StorageGrant({this.paths});

  bool canRead(String path) {
    if (paths == null) return true;
    for (final t in paths!) {
      if (path.startsWith(t.path)) return true;
    }
    return false;
  }

  bool canWrite(String path) {
    if (paths == null) return true;
    for (final t in paths!) {
      if (path.startsWith(t.path)) return !t.readOnly;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {if (paths != null) 'paths': paths!.map((e) => e.toJson()).toList()};

  factory StorageGrant.fromJson(Map<String, dynamic> j) =>
      StorageGrant(paths: (j['paths'] as List?)?.map((e) => StoragePathGrant.fromJson(e as Map<String, dynamic>)).toList());
}

class ContainersGrant {
  final bool logs;
  final List<String>? pull;
  final List<String>? run;
  final bool useContainers;

  ContainersGrant({this.logs = true, this.pull, this.run, this.useContainers = true});

  bool _matchesTag(String rule, String tag) => tag == rule || tag.startsWith(_stripWildcardSuffix(rule));

  bool canPull(String tag) {
    if (pull == null) return true;
    for (final r in pull!) {
      if (_matchesTag(r, tag)) return true;
    }
    return false;
  }

  bool canRun(String tag) {
    if (run == null) return true;
    for (final r in run!) {
      if (_matchesTag(r, tag)) return true;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
    'logs': logs,
    if (pull != null) 'pull': pull,
    if (run != null) 'run': run,
    'use_containers': useContainers,
  };

  factory ContainersGrant.fromJson(Map<String, dynamic> j) => ContainersGrant(
    logs: j['logs'] ?? true,
    pull: (j['pull'] as List?)?.cast<String>(),
    run: (j['run'] as List?)?.cast<String>(),
    useContainers: j['use_containers'] ?? true,
  );
}

class DeveloperGrant {
  final bool logs;

  DeveloperGrant({this.logs = true});

  Map<String, dynamic> toJson() => {'logs': logs};

  factory DeveloperGrant.fromJson(Map<String, dynamic> j) => DeveloperGrant(logs: j['logs'] ?? true);
}

class AdminGrant {
  AdminGrant();

  Map<String, dynamic> toJson() => {};

  factory AdminGrant.fromJson(Map<String, dynamic> j) => AdminGrant();
}

class ServicesGrant {
  ServicesGrant({this.list = true});

  final bool list;

  Map<String, dynamic> toJson() => {"list": list};

  factory ServicesGrant.fromJson(Map<String, dynamic> j) => ServicesGrant(list: j["list"]);
}

class OAuthEndpoint {
  final String endpoint;
  final String clientId;

  OAuthEndpoint({required this.endpoint, required this.clientId});

  Map<String, dynamic> toJson() => {'endpoint': endpoint, 'client_id': clientId};

  factory OAuthEndpoint.fromJson(Map<String, dynamic> j) => OAuthEndpoint(endpoint: j['endpoint'], clientId: j['client_id']);
}

class SecretsGrant {
  final List<OAuthEndpoint>? requestOAuthToken;

  SecretsGrant({this.requestOAuthToken});

  bool canRequestOAuthToken({required String authorizationEndpoint, required String clientId}) {
    if (requestOAuthToken == null) return true;
    for (final t in requestOAuthToken!) {
      final match =
          t.endpoint == authorizationEndpoint ||
          (_hasWildcardSuffix(t.endpoint) && authorizationEndpoint.startsWith(_stripWildcardSuffix(t.endpoint)));
      if (match && t.clientId == clientId) return true;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
    if (requestOAuthToken != null) 'request_oauth_token': requestOAuthToken!.map((e) => e.toJson()).toList(),
  };

  factory SecretsGrant.fromJson(Map<String, dynamic> j) => SecretsGrant(
    requestOAuthToken: (j['request_oauth_token'] as List?)?.map((e) => OAuthEndpoint.fromJson(e as Map<String, dynamic>)).toList(),
  );
}

class TunnelsGrant {
  final List<String>? ports;

  TunnelsGrant({this.ports});

  Map<String, dynamic> toJson() => {if (ports != null) 'ports': ports};

  factory TunnelsGrant.fromJson(Map<String, dynamic> j) => TunnelsGrant(ports: (j['ports'] as List?)?.cast<String>());
}

/// ---------------------------
/// ApiScope (mirror Python)
/// ---------------------------

class ApiScope {
  final LivekitGrant? livekit;
  final QueuesGrant? queues;
  final MessagingGrant? messaging;
  final DatabaseGrant? database;
  final MemoryGrant? memory;
  final SyncGrant? sync;
  final StorageGrant? storage;
  final ContainersGrant? containers;
  final DeveloperGrant? developer;
  final AgentsGrant? agents;
  final AdminGrant? admin;
  final SecretsGrant? secrets;
  final TunnelsGrant? tunnels;
  final ServicesGrant? services;

  ApiScope({
    this.livekit,
    this.queues,
    this.messaging,
    this.database,
    this.memory,
    this.sync,
    this.storage,
    this.containers,
    this.developer,
    this.agents,
    this.admin,
    this.secrets,
    this.tunnels,
    this.services,
  });

  static ApiScope agentDefault() => ApiScope(
    livekit: LivekitGrant(),
    queues: QueuesGrant(),
    messaging: MessagingGrant(),
    database: DatabaseGrant(),
    memory: MemoryGrant(),
    sync: SyncGrant(),
    storage: StorageGrant(),
    containers: ContainersGrant(),
    developer: DeveloperGrant(),
    agents: AgentsGrant(),
    services: ServicesGrant(),
  );

  static ApiScope userDefault() => ApiScope(
    livekit: LivekitGrant(),
    queues: QueuesGrant(),
    messaging: MessagingGrant(),
    database: DatabaseGrant(),
    sync: SyncGrant(),
    storage: StorageGrant(),
    containers: ContainersGrant(),
    developer: DeveloperGrant(),
    agents: AgentsGrant(),
    secrets: SecretsGrant(),
    services: ServicesGrant(),
  );

  static ApiScope full() => ApiScope(
    livekit: LivekitGrant(),
    queues: QueuesGrant(),
    messaging: MessagingGrant(),
    database: DatabaseGrant(),
    memory: MemoryGrant(),
    sync: SyncGrant(),
    storage: StorageGrant(),
    containers: ContainersGrant(),
    developer: DeveloperGrant(),
    agents: AgentsGrant(),
    admin: AdminGrant(),
    secrets: SecretsGrant(),
    tunnels: TunnelsGrant(),
    services: ServicesGrant(),
  );

  Map<String, dynamic> toJson() => {
    if (livekit != null) 'livekit': livekit!.toJson(),
    if (queues != null) 'queues': queues!.toJson(),
    if (messaging != null) 'messaging': messaging!.toJson(),
    if (database != null) 'database': database!.toJson(),
    if (memory != null) 'memory': memory!.toJson(),
    if (sync != null) 'sync': sync!.toJson(),
    if (storage != null) 'storage': storage!.toJson(),
    if (containers != null) 'containers': containers!.toJson(),
    if (developer != null) 'developer': developer!.toJson(),
    if (agents != null) 'agents': agents!.toJson(),
    if (admin != null) 'admin': admin!.toJson(),
    if (secrets != null) 'secrets': secrets!.toJson(),
    if (tunnels != null) 'tunnels': tunnels!.toJson(),
    if (services != null) 'services': services!.toJson(),
  };

  factory ApiScope.fromJson(Map<String, dynamic> j) => ApiScope(
    livekit: j['livekit'] != null ? LivekitGrant.fromJson(j['livekit'] as Map<String, dynamic>) : null,
    queues: j['queues'] != null ? QueuesGrant.fromJson(j['queues'] as Map<String, dynamic>) : null,
    messaging: j['messaging'] != null ? MessagingGrant.fromJson(j['messaging'] as Map<String, dynamic>) : null,
    database: j['database'] != null ? DatabaseGrant.fromJson(j['database'] as Map<String, dynamic>) : null,
    memory: j['memory'] != null ? MemoryGrant.fromJson(j['memory'] as Map<String, dynamic>) : null,
    sync: j['sync'] != null ? SyncGrant.fromJson(j['sync'] as Map<String, dynamic>) : null,
    storage: j['storage'] != null ? StorageGrant.fromJson(j['storage'] as Map<String, dynamic>) : null,
    containers: j['containers'] != null ? ContainersGrant.fromJson(j['containers'] as Map<String, dynamic>) : null,
    developer: j['developer'] != null ? DeveloperGrant.fromJson(j['developer'] as Map<String, dynamic>) : null,
    agents: j['agents'] != null ? AgentsGrant.fromJson(j['agents'] as Map<String, dynamic>) : null,
    admin: j['admin'] != null ? AdminGrant.fromJson(j['admin'] as Map<String, dynamic>) : null,
    secrets: j['secrets'] != null ? SecretsGrant.fromJson(j['secrets'] as Map<String, dynamic>) : null,
    tunnels: j['tunnels'] != null ? TunnelsGrant.fromJson(j['tunnels'] as Map<String, dynamic>) : null,
    services: j['services'] != null ? ServicesGrant.fromJson(j['services'] as Map<String, dynamic>) : null,
  );
}

/// ---------------------------
/// ParticipantGrant (now supports ApiScope)
/// ---------------------------

class ParticipantGrant {
  final String name;
  final Object? scope; // String? for most, ApiScope for 'api'

  ParticipantGrant({required this.name, this.scope});

  /// Convenience for creating an API grant.
  factory ParticipantGrant.api(ApiScope scope) => ParticipantGrant(name: 'api', scope: scope);

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'scope': name == 'api' ? (scope == null ? null : (scope as ApiScope).toJson()) : scope, // String? passthrough
    };
  }

  factory ParticipantGrant.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String;
    final rawScope = json['scope'];

    if (name == 'api') {
      if (rawScope == null) {
        return ParticipantGrant(name: name, scope: null);
      }
      if (rawScope is Map<String, dynamic>) {
        return ParticipantGrant(name: name, scope: ApiScope.fromJson(rawScope));
      }
      throw ArgumentError("Invalid 'api' scope; expected object, got ${rawScope.runtimeType}");
    } else {
      // room/role/tunnel_ports/etc. remain String?
      return ParticipantGrant(name: name, scope: rawScope as String?);
    }
  }
}

/// ---------------------------
/// ParticipantToken
/// ---------------------------

class ParticipantToken {
  final String name;
  final String? projectId;
  final String? apiKeyId;
  final List<ParticipantGrant> grants;
  final Map<String, dynamic>? extra;
  final String version; // aligns with Python versioning in payload

  ParticipantToken({required this.name, this.projectId, this.apiKeyId, this.extra, List<ParticipantGrant>? grants, String? version})
    : version = version ?? '0.6.0', // default current version
      grants = grants ?? [];

  /// "role" value; defaults to "user".
  String get role {
    for (final g in grants) {
      if (g.name == 'role' && g.scope is String && g.scope != 'user') {
        return g.scope as String;
      }
    }
    return 'user';
  }

  bool get isUser {
    for (final g in grants) {
      if (g.name == 'role' && g.scope is String && g.scope != 'user') {
        return false;
      }
    }
    return true;
  }

  /// Backwards compatible agent flag, if you still need it.
  bool get isAgent => role == 'agent';

  void addRoleGrant(String role) {
    grants.add(ParticipantGrant(name: 'role', scope: role));
  }

  void addRoomGrant(String roomName) {
    grants.add(ParticipantGrant(name: 'room', scope: roomName));
  }

  void addApiGrant(ApiScope grant) {
    for (final g in grants) {
      if (g.name == 'api') {
        throw StateError('Can only have a single api grant');
      }
    }
    grants.add(ParticipantGrant.api(grant));
  }

  /// Returns the scope (String? or ApiScope) for a given grant name.
  Object? grantScope(String name) {
    for (final g in grants) {
      if (g.name == name) return g.scope;
    }
    return null;
  }

  /// Returns the ApiScope if present; for versions < 0.6.0, returns a
  /// permissive default when absent (mirrors Python fallback).
  ApiScope? getApiGrant() {
    final api = grantScope('api');
    if (api is ApiScope) return api;

    if (_semverCompare(version, '0.6.0') < 0) {
      // <= 0.6.0 didn't fine-grain; default to broad access.
      return ApiScope(
        livekit: LivekitGrant(),
        queues: QueuesGrant(),
        messaging: MessagingGrant(),
        database: DatabaseGrant(),
        sync: SyncGrant(),
        storage: StorageGrant(),
        agents: AgentsGrant(),
        developer: DeveloperGrant(),
        // Note: matching Python "temp hack" to include containers.
        containers: ContainersGrant(),
      );
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'name': name, 'grants': grants.map((g) => g.toJson()).toList(), 'version': version};
    if (projectId != null) map['sub'] = projectId;
    if (apiKeyId != null) map['kid'] = apiKeyId;
    return map;
  }

  /// Encodes as JWT (HS256).
  /// If [token] is null, tries compile-time env ('MESHAGENT_SECRET').
  /// [expiration] adds 'exp' (seconds since epoch) to the payload.
  /// If [apiKey] is provided (or set via `MESHAGENT_API_KEY`), it determines
  /// the signing secret and ensures the payload contains the API key metadata.
  String toJwt({String? token, String? apiKey, DateTime? expiration}) {
    ApiKey? resolvedApiKey;

    var resolvedSecret = token;
    var providedApiKey = apiKey;
    providedApiKey ??= const String.fromEnvironment('MESHAGENT_API_KEY');

    if (providedApiKey.isNotEmpty) {
      resolvedApiKey = parseApiKey(providedApiKey);
      resolvedSecret = resolvedApiKey.secret;
    }

    final usingDefaultSecret = resolvedSecret == null;
    resolvedSecret ??= const String.fromEnvironment('MESHAGENT_SECRET');

    // Warn if missing ApiScope on newer versions (mirrors Python logger.warning)
    final hasApi = grants.any((g) => g.name == 'api');
    if (!hasApi && _semverCompare(version, '0.3.5') > 0) {
      // ignore: avoid_print
      print(
        'Warning: there is no ApiScope in the participant token; this participant will not be able to call the room API. Use addApiGrant to add an ApiScope.',
      );
    }

    final payload = Map<String, dynamic>.from(toJson());

    if (resolvedApiKey != null) {
      payload['kid'] = resolvedApiKey.id;
      payload['sub'] = resolvedApiKey.projectId;
    }

    // Match Python behavior: if exporting with default secret, drop kid.
    if (usingDefaultSecret && payload.containsKey('kid')) {
      payload.remove('kid');
    }

    // Merge extras
    final merged = <String, dynamic>{...payload, if (extra != null) ...extra!};

    if (expiration != null) {
      // 'exp' is a NumericDate (seconds since epoch)
      merged['exp'] = (expiration.millisecondsSinceEpoch / 1000).floor();
    }

    final jwt = JWT(merged);
    return jwt.sign(SecretKey(resolvedSecret), algorithm: JWTAlgorithm.HS256);
  }

  factory ParticipantToken.fromJson(Map<String, dynamic> json) {
    final knownKeys = {'name', 'sub', 'grants', 'kid', 'version'};
    final extra = <String, dynamic>{};
    json.forEach((k, v) {
      if (!knownKeys.contains(k)) extra[k] = v;
    });

    final version = json['version'] as String? ?? '0.5.3'; // Python default

    return ParticipantToken(
      name: json['name'] as String,
      projectId: json['sub'] as String?,
      apiKeyId: json['kid'] as String?,
      version: version,
      grants: (json['grants'] as List<dynamic>).map((g) => ParticipantGrant.fromJson(g as Map<String, dynamic>)).toList(),
      extra: extra.isEmpty ? null : extra,
    );
  }

  factory ParticipantToken.fromJwt(String jwtStr, {String? token, bool verify = true}) {
    if (verify) {
      token ??= const String.fromEnvironment('MESHAGENT_SECRET');
      final jwt = JWT.verify(jwtStr, SecretKey(token), checkHeaderType: false);
      final payload = jwt.payload as Map<String, dynamic>;
      return ParticipantToken.fromJson(payload);
    } else {
      final jwt = JWT.decode(jwtStr);
      final payload = jwt.payload as Map<String, dynamic>;
      return ParticipantToken.fromJson(payload);
    }
  }
}
