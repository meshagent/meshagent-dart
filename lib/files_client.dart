import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'file_permissions.dart';
export 'file_permissions.dart' show FileAction, FilePathRule, FilesPolicy, FilePermissions;

import 'client.dart';
import 'room_server_client.dart' show StorageEntry;

String _component(String value) {
  if (value.isEmpty || value == '.' || value == '..' || value.contains(RegExp(r'[/\\\x00-\x1f\x7f-\x9f]'))) {
    throw ArgumentError.value(value, 'identifier', 'Expected a single path component');
  }
  return value;
}

String _path(String value) => validateFilePath(value);

enum FilesTargetKind { room, agent }

class FilesTarget {
  FilesTarget({required String projectId, required this.kind, required String name})
    : projectId = _component(projectId),
      name = _component(name);

  final String projectId;
  final FilesTargetKind kind;
  final String name;

  Map<String, dynamic> toJson() => {'project_id': projectId, 'kind': kind.name, 'name': name};
}

class FileLocation {
  FileLocation({required this.target, required String path}) : path = _path(path);

  final FilesTarget target;
  final String path;

  Map<String, dynamic> toJson() => {'target': target.toJson(), 'path': path};
}

class FilesPage {
  FilesPage({required this.entries, this.continuationToken});

  final List<StorageEntry> entries;
  final String? continuationToken;

  factory FilesPage.fromJson(Map<String, dynamic> json) => FilesPage(
    entries: (json['entries'] as List)
        .map((value) {
          final entry = (value as Map).cast<String, dynamic>();
          return StorageEntry(
            name: entry['name'] as String,
            isFolder: entry['is_folder'] as bool,
            size: entry['size'] as int?,
            createdAt: entry['created_at'] == null ? null : DateTime.parse(entry['created_at'] as String),
            updatedAt: entry['updated_at'] == null ? null : DateTime.parse(entry['updated_at'] as String),
          );
        })
        .toList(growable: false),
    continuationToken: json['continuation_token'] as String?,
  );
}

class FileMetadata {
  FileMetadata({required this.path, required this.size, required this.isFolder, this.contentType, this.etag, this.lastModified});

  final String path;
  final int size;
  final bool isFolder;
  final String? contentType;
  final String? etag;
  final String? lastModified;
}

enum PresignedFileMethod { get, head, put, delete }

class PresignedFileUrl {
  PresignedFileUrl({required this.url, required this.method, required this.headers, required this.expiresAt});

  final Uri url;
  final PresignedFileMethod method;
  final Map<String, String> headers;
  final DateTime expiresAt;

  factory PresignedFileUrl.fromJson(Map<String, dynamic> json) => PresignedFileUrl(
    url: Uri.parse(json['url'] as String),
    method: PresignedFileMethod.values.byName((json['method'] as String).toLowerCase()),
    headers: Map<String, String>.from(json['headers'] as Map? ?? const {}),
    expiresAt: DateTime.parse(json['expires_at'] as String),
  );
}

class MeshagentDomains {
  MeshagentDomains({this.studio, this.accounts, this.powerboards, this.api, this.mail, this.pages, this.registry, this.files});

  final String? studio;
  final String? accounts;
  final String? powerboards;
  final String? api;
  final String? mail;
  final String? pages;
  final String? registry;
  final String? files;

  factory MeshagentDomains.fromJson(Map<String, dynamic> json) => MeshagentDomains(
    studio: json['studio'] as String?,
    accounts: json['accounts'] as String?,
    powerboards: json['powerboards'] as String?,
    api: json['api'] as String?,
    mail: json['mail'] as String?,
    pages: json['pages'] as String?,
    registry: json['registry'] as String?,
    files: json['files'] as String?,
  );
}

class MeshagentDeploymentConfig {
  MeshagentDeploymentConfig({required this.domains, this.version});

  final MeshagentDomains domains;
  final String? version;

  factory MeshagentDeploymentConfig.fromJson(Map<String, dynamic> json) => MeshagentDeploymentConfig(
    domains: MeshagentDomains.fromJson((json['domains'] as Map).cast<String, dynamic>()),
    version: json['version'] as String?,
  );
}

/// Shares its owning client's HTTP transport and current credentials.
class FilesClient {
  FilesClient(this._client);

  final Meshagent _client;
  Future<Uri>? _discovery;

  TargetFilesClient forRoom({required String projectId, required String roomName}) =>
      forTarget(FilesTarget(projectId: projectId, kind: FilesTargetKind.room, name: roomName));
  TargetFilesClient forAgent({required String projectId, required String agentName}) =>
      forTarget(FilesTarget(projectId: projectId, kind: FilesTargetKind.agent, name: agentName));
  TargetFilesClient forTarget(FilesTarget target) => TargetFilesClient._(this, target);

  Future<Uri> _endpoint() => _discovery ??= _discover().catchError((Object error, StackTrace stack) {
    _discovery = null;
    Error.throwWithStackTrace(error, stack);
  });

  Future<Uri> _discover() async {
    final domain = (await _client.getConfig()).domains.files;
    if (domain == null || domain.isEmpty) throw MeshagentException('The files API is unavailable: deployment config has no domains.files');
    final url = Uri.parse(domain.contains('://') ? domain : 'https://$domain');
    if (!{'http', 'https'}.contains(url.scheme) || url.host.isEmpty || url.userInfo.isNotEmpty || url.hasQuery || url.hasFragment) {
      throw MeshagentException('Deployment config contains an invalid files endpoint');
    }
    return url.replace(path: url.path.replaceFirst(RegExp(r'/+$'), ''));
  }

  Future<Uri> _url(FilesTarget target, String path, [Map<String, String>? query]) async {
    _path(path);
    final base = await _endpoint();
    final namespace = target.kind == FilesTargetKind.room ? 'rooms' : 'agents';
    return base.replace(
      pathSegments: [...base.pathSegments.where((part) => part.isNotEmpty), target.projectId, namespace, target.name, ...path.split('/')],
      queryParameters: query,
    );
  }

  Future<http.StreamedResponse> _send(http.BaseRequest request) async {
    request.followRedirects = false;
    final response = await _client.httpClient.send(request);
    if (response.statusCode >= 200 && response.statusCode < 300) return response;
    final body = await _bounded(response.stream, 64 * 1024);
    throw MeshagentException.fromResponse(
      'Files request failed.',
      http.Response.bytes(body, response.statusCode, headers: response.headers),
    );
  }

  Future<Map<String, dynamic>> _json(http.BaseRequest request) async {
    final response = await _send(request);
    return (jsonDecode(utf8.decode(await _bounded(response.stream, 1024 * 1024))) as Map).cast<String, dynamic>();
  }
}

Future<Uint8List> _bounded(Stream<List<int>> stream, int limit) async {
  final result = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    if (result.length + chunk.length > limit) throw MeshagentException('Files control response exceeds its size limit');
    result.add(chunk);
  }
  return result.takeBytes();
}

class _FilesUploadRequest extends http.BaseRequest with http.Abortable {
  _FilesUploadRequest(super.method, super.url, this.data, {this.abortTrigger});

  final Stream<List<int>> data;
  @override
  final Future<void>? abortTrigger;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(data);
  }
}

class TargetFilesClient {
  TargetFilesClient._(this._files, this.target);

  final FilesClient _files;
  final FilesTarget target;

  FileLocation location(String path) => FileLocation(target: target, path: path);

  Future<FilePermissions> permissions(String path) async =>
      FilePermissions.fromJson(await _files._json(http.Request('GET', await _files._url(target, path, {'permissions': ''}))));

  Future<FilesPage> listPage({String path = '', String? continuationToken, int limit = 1000}) async {
    _path(path);
    if (limit < 1 || limit > 1000) throw ArgumentError.value(limit, 'limit', 'Expected 1–1000');
    final url = await _files._url(target, '', {'list': '', 'prefix': path, 'limit': '$limit', 'continuation_token': ?continuationToken});
    return FilesPage.fromJson(await _files._json(http.Request('GET', url)));
  }

  Stream<StorageEntry> list({String path = ''}) async* {
    String? token;
    final seen = <String>{};
    do {
      final page = await listPage(path: path, continuationToken: token);
      for (final entry in page.entries) {
        yield entry;
      }
      token = page.continuationToken;
      if (token != null && !seen.add(token)) throw MeshagentException('Files server returned a repeated pagination token');
    } while (token != null);
  }

  Future<FileMetadata> stat(String path) async {
    final response = await _files._send(http.Request('HEAD', await _files._url(target, path)));
    await response.stream.drain<void>();
    return FileMetadata(
      path: path,
      size: int.parse(response.headers['content-length'] ?? '0'),
      isFolder: response.headers['x-meshagent-is-folder'] == 'true',
      contentType: response.headers['content-type'],
      etag: response.headers['etag'],
      lastModified: response.headers['last-modified'],
    );
  }

  Future<bool> exists(String path) async {
    try {
      await stat(path);
      return true;
    } on MeshagentException catch (error) {
      if (error.statusCode == 404) return false;
      rethrow;
    }
  }

  Stream<List<int>> downloadStream(String path, {Future<void>? abortTrigger}) async* {
    final response = await _files._send(http.AbortableRequest('GET', await _files._url(target, path), abortTrigger: abortTrigger));
    yield* response.stream;
  }

  /// Buffers the complete file. Use [downloadStream] for large files.
  Future<Uint8List> download(String path) async {
    final data = BytesBuilder(copy: false);
    await for (final chunk in downloadStream(path)) {
      data.add(chunk);
    }
    return data.takeBytes();
  }

  Future<void> upload(
    String path,
    List<int> data, {
    String contentType = 'application/octet-stream',
    bool overwrite = true,
    Future<void>? abortTrigger,
  }) => uploadStream(
    path,
    Stream.value(data),
    contentLength: data.length,
    contentType: contentType,
    overwrite: overwrite,
    abortTrigger: abortTrigger,
  );

  /// Streams on transports that support it; browser transports may buffer uploads.
  Future<void> uploadStream(
    String path,
    Stream<List<int>> data, {
    int? contentLength,
    String contentType = 'application/octet-stream',
    bool overwrite = true,
    Future<void>? abortTrigger,
  }) async {
    final request =
        _FilesUploadRequest('PUT', await _files._url(target, path, {'overwrite': '$overwrite'}), data, abortTrigger: abortTrigger)
          ..headers['Content-Type'] = contentType
          ..contentLength = contentLength;
    final response = await _files._send(request);
    await response.stream.drain<void>();
  }

  Future<void> delete(String path, {bool recursive = false}) async {
    final response = await _files._send(http.Request('DELETE', await _files._url(target, path, {'recursive': '$recursive'})));
    await response.stream.drain<void>();
  }

  Future<void> mkdir(String path) => _action(path, 'mkdir', const {});
  Future<void> copy(FileLocation source, String destination, {bool overwrite = false}) =>
      _action(destination, 'copy', {'source': source.toJson(), 'overwrite': overwrite});
  Future<void> move(FileLocation source, String destination, {bool overwrite = false}) =>
      _action(destination, 'move', {'source': source.toJson(), 'overwrite': overwrite});

  Future<void> _action(String path, String action, Map<String, dynamic> body) async {
    final request = http.Request('POST', await _files._url(target, path, {'action': action}))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(body);
    final response = await _files._send(request);
    await response.stream.drain<void>();
  }

  Future<PresignedFileUrl> presign(String path, {PresignedFileMethod method = PresignedFileMethod.get, int expiresIn = 3600}) async {
    _path(path);
    if (expiresIn < 1 || expiresIn > 604800) throw ArgumentError.value(expiresIn, 'expiresIn', 'Expected 1–604800 seconds');
    final base = await _files._endpoint();
    final url = base.replace(pathSegments: [...base.pathSegments.where((part) => part.isNotEmpty), 'v1', 'presign']);
    final request = http.Request('POST', url)
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'target': target.toJson(), 'path': path, 'method': method.name.toUpperCase(), 'expires_in': expiresIn});
    return PresignedFileUrl.fromJson(await _files._json(request));
  }
}
