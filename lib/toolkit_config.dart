import 'dart:convert';

import 'room_server_client.dart';

/// Base class for all tool configurations
abstract class ToolkitConfig {
  final String name;

  const ToolkitConfig(this.name);

  Map<String, dynamic> toJson();

  static ToolkitConfig fromJson(Map<String, dynamic> json) {
    switch (json['name']) {
      case 'mcp':
        return MCPConfig.fromJson(json);
      case 'web_search':
        return WebSearchConfig.fromJson(json);
      case 'image_generation':
        return ImageGenerationConfig.fromJson(json);
      case 'local_shell':
        return LocalShellConfig.fromJson(json);
      case 'shell':
        return ShellConfig.fromJson(json);
      case 'storage':
        return StorageConfig.fromJson(json);
      case 'script':
        return ScriptToolConfig.fromJson(json);
      default:
        throw ArgumentError('Unknown ToolkitConfig name: ${json['name']}');
    }
  }
}

/// ----------------------------------------------
/// MCP CONFIGURATION
/// ----------------------------------------------

class MCPServer {
  final String serverLabel;
  final String? authorization;
  final String? serverUrl;
  final List<String>? allowedTools;
  final Map<String, dynamic>? headers;
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
      headers: json['headers'] != null ? Map<String, dynamic>.from(json['headers']) : null,
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
      if (headers != null) 'headers': headers,
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
    Map<String, dynamic>? headers,
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

class MCPConfig extends ToolkitConfig {
  final List<MCPServer> servers;

  MCPConfig({required this.servers}) : super('mcp');

  factory MCPConfig.fromJson(Map<String, dynamic> json) {
    return MCPConfig(servers: (json['servers'] as List<dynamic>).map((e) => MCPServer.fromJson(e as Map<String, dynamic>)).toList());
  }

  @override
  Map<String, dynamic> toJson() => {'name': name, 'servers': servers.map((s) => s.toJson()).toList()};
}

/// ----------------------------------------------
/// WEB SEARCH CONFIGURATION
/// ----------------------------------------------

class WebSearchConfig extends ToolkitConfig {
  WebSearchConfig() : super('web_search');

  factory WebSearchConfig.fromJson(Map<String, dynamic> json) => WebSearchConfig();

  @override
  Map<String, dynamic> toJson() => {'name': name};
}

/// ----------------------------------------------
/// IMAGE GENERATION CONFIGURATION
/// ----------------------------------------------

class ImageGenerationConfig extends ToolkitConfig {
  final String? background; // "transparent" | "opaque" | "auto"
  final String? inputImageMaskUrl;
  final String? model;
  final String? moderation;
  final int? outputCompression;
  final String? outputFormat; // "png" | "webp" | "jpeg"
  final int? partialImages;
  final String? quality; // "auto" | "low" | "medium" | "high"
  final String? size; // "1024x1024" | "1024x1536" | "1536x1024" | "auto"

  ImageGenerationConfig({
    this.background,
    this.inputImageMaskUrl,
    this.model,
    this.moderation,
    this.outputCompression,
    this.outputFormat,
    this.partialImages,
    this.quality,
    this.size,
  }) : super('image_generation');

  factory ImageGenerationConfig.fromJson(Map<String, dynamic> json) {
    return ImageGenerationConfig(
      background: json['background'],
      inputImageMaskUrl: json['input_image_mask_url'] ?? json['inputImageMaskUrl'],
      model: json['model'],
      moderation: json['moderation'],
      outputCompression: json['output_compression'] ?? json['outputCompression'],
      outputFormat: json['output_format'] ?? json['outputFormat'],
      partialImages: json['partial_images'] ?? json['partialImages'],
      quality: json['quality'],
      size: json['size'],
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'name': name,
    if (background != null) 'background': background,
    if (inputImageMaskUrl != null) 'input_image_mask_url': inputImageMaskUrl,
    if (model != null) 'model': model,
    if (moderation != null) 'moderation': moderation,
    if (outputCompression != null) 'output_compression': outputCompression,
    if (outputFormat != null) 'output_format': outputFormat,
    if (partialImages != null) 'partial_images': partialImages,
    if (quality != null) 'quality': quality,
    if (size != null) 'size': size,
  };
}

/// ----------------------------------------------
/// LOCAL SHELL CONFIGURATION
/// ----------------------------------------------

class LocalShellConfig extends ToolkitConfig {
  LocalShellConfig() : super('local_shell');

  factory LocalShellConfig.fromJson(Map<String, dynamic> json) => LocalShellConfig();

  @override
  Map<String, dynamic> toJson() => {'name': name};
}

class ShellConfig extends ToolkitConfig {
  ShellConfig() : super('shell');

  factory ShellConfig.fromJson(Map<String, dynamic> json) => ShellConfig();

  @override
  Map<String, dynamic> toJson() => {'name': name};
}

class ScriptToolConfig extends ToolkitConfig {
  ScriptToolConfig({required this.serviceId, required this.commands, required this.toolName, this.title, this.description})
    : super('script');

  final String serviceId;
  final List<String> commands;
  final String toolName;
  final String? title;
  final String? description;
  factory ScriptToolConfig.fromJson(Map<String, dynamic> json) => ScriptToolConfig(
    serviceId: json["service_id"],
    commands: json["commands"],
    toolName: json["tool_name"],
    title: json["title"],
    description: json["description"],
  );

  @override
  Map<String, dynamic> toJson() => {
    'name': name,
    "service_id": serviceId,
    "tool_name": toolName,
    "commands": commands,
    'title': title,
    'description': description,
  };
}

class StorageConfig extends ToolkitConfig {
  StorageConfig() : super('storage');

  factory StorageConfig.fromJson(Map<String, dynamic> json) => StorageConfig();

  @override
  Map<String, dynamic> toJson() => {'name': name};
}

class Connector {
  Connector({required this.name, required this.server, this.oauth});

  final String name;
  final OAuthClientConfig? oauth;
  final MCPServer server;

  String? get _oauthClientSecretIdFromHeaders {
    final value = server.headers?['Meshagent-OAuth-Client-Secret-Id'];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  ConnectorRef? _buildConnectorRef() {
    final clientSecretId = _oauthClientSecretIdFromHeaders;
    final serverUrl = server.serverUrl;
    final hasServerUrl = serverUrl != null && serverUrl.trim().isNotEmpty;
    if (server.openaiConnectorId == null && clientSecretId == null && !hasServerUrl) {
      return null;
    }
    return ConnectorRef(
      openaiConnectorId: server.openaiConnectorId,
      serverUrl: hasServerUrl ? serverUrl.trim() : null,
      clientSecretId: clientSecretId,
    );
  }

  Future<bool> isConnected(RoomClient room, String agentName) async {
    final connectorRef = _buildConnectorRef();
    final includeOauthWithConnector = connectorRef?.clientSecretId != null;
    if (connectorRef == null && oauth == null) {
      return true;
    }
    final token = await room.secrets.getOfflineOAuthToken(
      connector: connectorRef,
      oauth: includeOauthWithConnector ? oauth : (connectorRef != null ? null : oauth),
      delegatedTo: agentName,
    );
    return token != null;
  }

  Future<String?> authenticate(RoomClient client, RemoteParticipant agent, Uri redirectUri) async {
    final connectorRef = _buildConnectorRef();
    final includeOauthWithConnector = connectorRef?.clientSecretId != null;
    if (connectorRef != null || oauth != null) {
      return await client.secrets.requestOAuthToken(
        fromParticipantId: client.localParticipant!.id,
        connector: connectorRef,
        oauth: includeOauthWithConnector ? oauth : (connectorRef != null ? null : oauth),
        redirectUri: redirectUri,
        delegateTo: agent.getAttribute("name"),
      );
    } else {
      return null;
    }
  }
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
