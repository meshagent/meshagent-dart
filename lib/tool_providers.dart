import 'dart:convert';

/// Base class for all tool configurations
abstract class ToolConfig {
  final String name;

  const ToolConfig(this.name);

  Map<String, dynamic> toJson();

  static ToolConfig fromJson(Map<String, dynamic> json) {
    switch (json['name']) {
      case 'mcp':
        return MCPConfig.fromJson(json);
      case 'web_search':
        return WebSearchConfig.fromJson(json);
      case 'image_generation':
        return ImageGenerationConfig.fromJson(json);
      case 'local_shell':
        return LocalShellConfig.fromJson(json);
      default:
        throw ArgumentError('Unknown ToolConfig name: ${json['name']}');
    }
  }
}

/// ----------------------------------------------
/// MCP CONFIGURATION
/// ----------------------------------------------

class MCPServer {
  final String serverLabel;
  final String serverUrl;
  final List<String>? allowedTools;
  final Map<String, dynamic>? headers;
  final String? requireApproval; // "always" | "never"
  final List<String>? alwaysRequireApproval;
  final List<String>? neverRequireApproval;
  final String? openaiConnectorId;

  MCPServer({
    required this.serverLabel,
    required this.serverUrl,
    this.allowedTools,
    this.headers,
    this.requireApproval,
    this.alwaysRequireApproval,
    this.neverRequireApproval,
    this.openaiConnectorId,
  });

  factory MCPServer.fromJson(Map<String, dynamic> json) {
    return MCPServer(
      serverLabel: json['server_label'] ?? json['serverLabel'],
      serverUrl: json['server_url'] ?? json['serverUrl'],
      allowedTools: (json['allowed_tools'] ?? json['allowedTools'])?.cast<String>(),
      headers: json['headers'] != null ? Map<String, dynamic>.from(json['headers']) : null,
      requireApproval: json['require_approval'] ?? json['requireApproval'],
      alwaysRequireApproval: (json['always_require_approval'] ?? json['alwaysRequireApproval'])?.cast<String>(),
      neverRequireApproval: (json['never_require_approval'] ?? json['neverRequireApproval'])?.cast<String>(),
      openaiConnectorId: json['openai_connector_id'] ?? json['openaiConnectorId'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'server_label': serverLabel,
      'server_url': serverUrl,
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
}

class MCPConfig extends ToolConfig {
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

class WebSearchConfig extends ToolConfig {
  WebSearchConfig() : super('web_search');

  factory WebSearchConfig.fromJson(Map<String, dynamic> json) => WebSearchConfig();

  @override
  Map<String, dynamic> toJson() => {'name': name};
}

/// ----------------------------------------------
/// IMAGE GENERATION CONFIGURATION
/// ----------------------------------------------

class ImageGenerationConfig extends ToolConfig {
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

class LocalShellConfig extends ToolConfig {
  LocalShellConfig() : super('local_shell');

  factory LocalShellConfig.fromJson(Map<String, dynamic> json) => LocalShellConfig();

  @override
  Map<String, dynamic> toJson() => {'name': name};
}
