import 'dart:convert';

import 'room_server_client.dart';

class MCPHeader {
  final String name;
  final String value;

  const MCPHeader({required this.name, required this.value});

  factory MCPHeader.fromJson(Map<String, dynamic> json) {
    return MCPHeader(name: json['name'] as String, value: json['value'] as String);
  }

  Map<String, dynamic> toJson() => {'name': name, 'value': value};
}

List<MCPHeader>? _parseMcpHeaders(Object? value) {
  if (value == null) {
    return null;
  }

  if (value is List) {
    return value.map((entry) => MCPHeader.fromJson(Map<String, dynamic>.from(entry as Map))).toList();
  }

  if (value is Map) {
    return value.entries.map((entry) => MCPHeader(name: entry.key.toString(), value: entry.value.toString())).toList();
  }

  throw ArgumentError.value(value, 'headers', 'Expected a list of header entries or a map');
}

class MCPServer {
  final String serverLabel;
  final String? authorization;
  final String? serverUrl;
  final List<String>? allowedTools;
  final List<MCPHeader>? headers;
  final String? requireApproval; // "always" | "never"
  final List<String>? alwaysRequireApproval;
  final List<String>? neverRequireApproval;
  final String? openaiConnectorId;

  MCPServer({
    required this.serverLabel,
    this.authorization,
    this.serverUrl,
    this.allowedTools,
    this.headers,
    this.requireApproval,
    this.alwaysRequireApproval,
    this.neverRequireApproval,
    this.openaiConnectorId,
  });

  factory MCPServer.fromJson(Map<String, dynamic> json) {
    return MCPServer(
      serverLabel: json['server_label'],
      authorization: json['authorization'],
      serverUrl: json['server_url'],
      allowedTools: (json['allowed_tools'])?.cast<String>(),
      headers: _parseMcpHeaders(json['headers']),
      requireApproval: json['require_approval'],
      alwaysRequireApproval: (json['always_require_approval'])?.cast<String>(),
      neverRequireApproval: (json['never_require_approval'])?.cast<String>(),
      openaiConnectorId: json['openai_connector_id'] ?? json['openaiConnectorId'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'server_label': serverLabel,
      'server_url': serverUrl,
      if (authorization != null) 'authorization': authorization,
      if (allowedTools != null) 'allowed_tools': allowedTools,
      if (headers != null) 'headers': headers!.map((header) => header.toJson()).toList(),
      if (requireApproval != null) 'require_approval': requireApproval,
      if (alwaysRequireApproval != null) 'always_require_approval': alwaysRequireApproval,
      if (neverRequireApproval != null) 'never_require_approval': neverRequireApproval,
      if (openaiConnectorId != null) 'openai_connector_id': openaiConnectorId,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  static MCPServer fromJsonString(String data) => MCPServer.fromJson(jsonDecode(data));

  MCPServer copyWith({
    String? serverLabel,
    String? authorization,
    String? serverUrl,
    List<String>? allowedTools,
    List<MCPHeader>? headers,
    String? requireApproval,
    List<String>? alwaysRequireApproval,
    List<String>? neverRequireApproval,
    String? openaiConnectorId,
  }) {
    return MCPServer(
      serverLabel: serverLabel ?? this.serverLabel,
      authorization: authorization ?? this.authorization,
      serverUrl: serverUrl ?? this.serverUrl,
      allowedTools: allowedTools ?? this.allowedTools,
      headers: headers ?? this.headers,
      requireApproval: requireApproval ?? this.requireApproval,
      alwaysRequireApproval: alwaysRequireApproval ?? this.alwaysRequireApproval,
      neverRequireApproval: neverRequireApproval ?? this.neverRequireApproval,
      openaiConnectorId: openaiConnectorId ?? this.openaiConnectorId,
    );
  }
}

class Connector {
  Connector({required this.name, required this.server, this.oauth});

  final String name;
  final OAuthClientConfig? oauth;
  final MCPServer server;

  static String? _oauthClientSecretIdFromHeaders(MCPServer server) {
    for (final header in server.headers ?? const <MCPHeader>[]) {
      if (header.name == 'Meshagent-OAuth-Client-Secret-Id') {
        final value = header.value.trim();
        if (value.isNotEmpty) {
          return value;
        }
      }
    }
    return null;
  }

  static ConnectorRef? buildConnectorRef({required MCPServer server, OAuthClientConfig? oauth}) {
    final clientSecretId = _oauthClientSecretIdFromHeaders(server);
    final serverUrl = server.serverUrl;
    final hasServerUrl = serverUrl != null && serverUrl.trim().isNotEmpty;
    final requiresOAuth = oauth != null || server.openaiConnectorId != null || clientSecretId != null;
    if (!requiresOAuth) {
      return null;
    }
    if (server.openaiConnectorId == null && clientSecretId == null && !hasServerUrl) {
      return null;
    }
    return ConnectorRef(
      openaiConnectorId: server.openaiConnectorId,
      serverUrl: hasServerUrl ? serverUrl.trim() : null,
      clientSecretId: clientSecretId,
    );
  }

  ConnectorRef? _buildConnectorRef() {
    return buildConnectorRef(server: server, oauth: oauth);
  }

  Future<bool> isConnected(RoomClient room, String agentName) async {
    final connectorRef = _buildConnectorRef();
    if (connectorRef == null && oauth == null) {
      return true;
    }
    final token = await room.secrets.getOfflineOAuthToken(connector: connectorRef, oauth: oauth, delegatedTo: agentName);
    return token != null;
  }

  Future<String?> authenticate(RoomClient client, RemoteParticipant agent, Uri redirectUri) async {
    final connectorRef = _buildConnectorRef();
    if (connectorRef != null || oauth != null) {
      return await client.secrets.requestOAuthToken(
        fromParticipantId: client.localParticipant!.id,
        connector: connectorRef,
        oauth: oauth,
        redirectUri: redirectUri,
        delegateTo: agent.getAttribute("name"),
      );
    } else {
      return null;
    }
  }
}

List<MCPHeader>? _headersFromEndpointSpec(Map<String, String>? headers) {
  if (headers == null || headers.isEmpty) {
    return null;
  }

  return [for (final entry in headers.entries) MCPHeader(name: entry.key, value: entry.value)];
}

String? _roomServiceMcpServerUrl({required ServiceSpec service, required PortSpec port, required EndpointSpec endpoint}) {
  final endpointPath = endpoint.path.startsWith('/') ? endpoint.path : '/${endpoint.path}';
  final portValue = port.num.value;

  if (service.external == null) {
    if (portValue == null) {
      return Uri(scheme: 'http', host: 'localhost', path: endpointPath).toString();
    }
    return Uri(scheme: 'http', host: 'localhost', port: portValue, path: endpointPath).toString();
  }

  final externalUrl = service.external?.url;
  if (externalUrl == null || externalUrl.isEmpty) {
    return null;
  }

  var baseUri = Uri.tryParse(externalUrl);
  if (baseUri == null) {
    return null;
  }
  if (!baseUri.hasScheme) {
    final withDefaultScheme = Uri.tryParse('https://$externalUrl');
    if (withDefaultScheme == null) {
      return null;
    }
    baseUri = withDefaultScheme;
  }
  if (!baseUri.hasAuthority) {
    return null;
  }

  final normalizedBasePath = baseUri.path.endsWith('/') ? baseUri.path.substring(0, baseUri.path.length - 1) : baseUri.path;
  final joinedPath = normalizedBasePath.isEmpty || normalizedBasePath == '/' ? endpointPath : '$normalizedBasePath$endpointPath';
  if (portValue == null) {
    return baseUri.replace(path: joinedPath).toString();
  }

  final authorityBuffer = StringBuffer();
  if (baseUri.userInfo.isNotEmpty) {
    authorityBuffer
      ..write(baseUri.userInfo)
      ..write('@');
  }

  final host = baseUri.host.contains(':') ? '[${baseUri.host}]' : baseUri.host;
  authorityBuffer
    ..write(host)
    ..write(':')
    ..write(portValue);

  final uriBuffer = StringBuffer()
    ..write(baseUri.scheme)
    ..write('://')
    ..write(authorityBuffer)
    ..write(joinedPath);

  if (baseUri.hasQuery) {
    uriBuffer
      ..write('?')
      ..write(baseUri.query);
  }

  if (baseUri.hasFragment) {
    uriBuffer
      ..write('#')
      ..write(baseUri.fragment);
  }

  return uriBuffer.toString();
}

List<Connector> mcpConnectorsFromRoomServices({required Iterable<ServiceSpec> services, String? agentName}) {
  final connectors = <Connector>[];

  for (final service in services) {
    final filter = service.metadata.annotations["meshagent.agent.filter"];
    if (filter != null && filter != agentName) {
      continue;
    }

    for (final port in service.ports) {
      for (final endpoint in port.endpoints) {
        final mcp = endpoint.mcp;
        if (mcp == null) {
          continue;
        }

        connectors.add(
          Connector(
            name: mcp.label,
            server: MCPServer(
              serverLabel: mcp.label,
              serverUrl: _roomServiceMcpServerUrl(service: service, port: port, endpoint: endpoint),
              headers: _headersFromEndpointSpec(mcp.headers),
              requireApproval: mcp.requireApproval,
              openaiConnectorId: mcp.openaiConnectorId,
            ),
            oauth: mcp.oauth,
          ),
        );
      }
    }
  }

  return connectors;
}

class OpenAIConnectors {
  static final dropbox = Connector(
    name: "Dropbox",
    server: MCPServer(serverLabel: "Dropbox", openaiConnectorId: "connector_dropbox"),
    oauth: OAuthClientConfig(
      clientId: const String.fromEnvironment("DROPBOX_CONNECTOR_OAUTH_CLIENT_ID"),
      clientSecret: "CLIENT_SECRET",
      authorizationEndpoint: "https://www.dropbox.com/oauth2/authorize",
      tokenEndpoint: "https://api.dropbox.com/oauth2/token",
      noPkce: true,
      scopes: ["files.metadata.read", "account_info.read", "files.content.read"],
    ),
  );

  static final gmail = Connector(
    name: "Gmail",
    server: MCPServer(serverLabel: "Gmail", openaiConnectorId: "connector_gmail"),
    oauth: OAuthClientConfig(
      clientId: const String.fromEnvironment("GOOGLE_CONNECTOR_OAUTH_CLIENT_ID"),
      authorizationEndpoint: "https://accounts.google.com/o/oauth2/v2/auth",
      tokenEndpoint: "https://oauth2.googleapis.com/token",
      noPkce: false,
      scopes: [
        "https://www.googleapis.com/auth/gmail.modify",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
      ],
    ),
  );

  static final googleCalendar = Connector(
    name: "Google Calendar",
    server: MCPServer(serverLabel: "Google_Calendar", openaiConnectorId: "connector_googlecalendar"),
    oauth: OAuthClientConfig(
      clientId: const String.fromEnvironment("GOOGLE_CONNECTOR_OAUTH_CLIENT_ID"),
      authorizationEndpoint: "https://accounts.google.com/o/oauth2/v2/auth",
      tokenEndpoint: "https://oauth2.googleapis.com/token",
      noPkce: false,
      scopes: [
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
        "https://www.googleapis.com/auth/calendar.events",
      ],
    ),
  );

  static final googleDrive = Connector(
    name: "Google Drive",
    server: MCPServer(serverLabel: "Google_Drive", openaiConnectorId: "connector_googledrive"),
    oauth: OAuthClientConfig(
      clientId: "CLIENT_ID",
      clientSecret: const String.fromEnvironment("GOOGLE_CONNECTOR_OAUTH_CLIENT_ID"),
      authorizationEndpoint: "https://accounts.google.com/o/oauth2/v2/auth",
      tokenEndpoint: "https://oauth2.googleapis.com/token",
      noPkce: false,
      scopes: [
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
        "https://www.googleapis.com/auth/drive.readonly",
      ],
    ),
  );

  static final microsoftTeams = Connector(
    name: "Microsoft Teams",
    server: MCPServer(serverLabel: "Microsoft_Teams", openaiConnectorId: "connector_microsoftteams"),
    oauth: OAuthClientConfig(
      clientId: const String.fromEnvironment("MICROSOFT_CONNECTOR_OAUTH_CLIENT_ID"),
      clientSecret: "CLIENT_SECRET",
      authorizationEndpoint: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
      tokenEndpoint: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
      noPkce: false,
      scopes: ["User.Read", "Chat.Read", "ChannelMessage.Read.All"],
    ),
  );

  static final outlookCalendar = Connector(
    name: "Outlook Calendar",
    server: MCPServer(serverLabel: "Outlook_Calendar", openaiConnectorId: "connector_outlookcalendar"),
    oauth: OAuthClientConfig(
      clientId: const String.fromEnvironment("MICROSOFT_CONNECTOR_OAUTH_CLIENT_ID"),
      clientSecret: "CLIENT_SECRET",
      authorizationEndpoint: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
      tokenEndpoint: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
      noPkce: false,
      scopes: ["Calendars.Read", "User.Read"],
    ),
  );

  static final outlookEmail = Connector(
    name: "Outlook Email",
    server: MCPServer(serverLabel: "Outlook_Email", openaiConnectorId: "connector_outlookemail"),
    oauth: OAuthClientConfig(
      clientId: const String.fromEnvironment("MICROSOFT_CONNECTOR_OAUTH_CLIENT_ID"),
      clientSecret: "CLIENT_SECRET",
      authorizationEndpoint: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
      tokenEndpoint: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
      noPkce: false,
      scopes: ["User.Read", "Mail.Read"],
    ),
  );

  static final sharepoint = Connector(
    name: "Sharepoint",
    server: MCPServer(serverLabel: "Sharepoint", openaiConnectorId: "connector_sharepoint"),
    oauth: OAuthClientConfig(
      clientId: const String.fromEnvironment("MICROSOFT_CONNECTOR_OAUTH_CLIENT_ID"),
      clientSecret: "CLIENT_SECRET",
      authorizationEndpoint: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
      tokenEndpoint: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
      noPkce: false,
      scopes: ["Sites.Read.All", "Files.Read.All", "User.Read"],
    ),
  );

  static final all = [dropbox, gmail, googleCalendar, googleDrive, microsoftTeams, sharepoint, outlookEmail, outlookCalendar];
}
