import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:meshagent/participant_token.dart';

enum ProjectRole { member, developer, admin }

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

class RoomShareConnectionInfo extends RoomConnectionInfo {
  RoomShareConnectionInfo({
    required super.roomName,
    required super.projectId,
    required this.settings,
    required super.jwt,
    required super.roomUrl,
  });

  final Map<String, dynamic> settings;

  static RoomShareConnectionInfo fromJson(Map<String, dynamic> json) {
    return RoomShareConnectionInfo(
      roomName: json["room_name"],
      projectId: json["project_id"],
      settings: json["settings"],
      jwt: json["jwt"],
      roomUrl: Uri.parse(json["room_url"]),
    );
  }
}

class RoomSession {
  final String id;
  final String roomName;
  final DateTime createdAt;
  final bool isActive;

  RoomSession({required this.id, required this.roomName, required this.createdAt, required this.isActive});

  factory RoomSession.fromJson(Map<String, dynamic> json) => RoomSession(
    id: json["id"],
    roomName: json['room_name'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    isActive: json['is_active'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {'id': id, 'room_name': roomName, 'started_at': createdAt.toIso8601String(), 'is_active': isActive};
}

class Balance {
  Balance({required this.balance, required this.autoRechargeAmount, required this.autoRechargeThreshhold, required this.lastRecharge});

  final double balance;
  final double? autoRechargeThreshhold;
  final double? autoRechargeAmount;
  final DateTime? lastRecharge;
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
  final String queue;

  Mailbox({required this.address, required this.room, required this.queue});

  factory Mailbox.fromJson(Map<String, dynamic> json) =>
      Mailbox(address: json['address'] as String, room: json['room'] as String, queue: json['queue'] as String);

  Map<String, dynamic> toJson() => {'address': address, 'room': room, 'queue': queue};
}

/// A client to interact with the accounts routes.
abstract class AccountsClient {
  final String baseUrl;

  /// Creates an instance of [AccountsClient].
  ///
  /// [baseUrl] is the root URL of your server, e.g. 'http://localhost:8080'.
  /// [token] is your Bearer token for authorization.
  AccountsClient({required this.baseUrl});

  String get token {
    throw Exception("Not implemented");
  }

  /// Returns the default headers including Bearer Authorization.
  Map<String, String> _getHeaders() {
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  /// POST /accounts/projects/{project_id}/mailboxes
  /// Body: { "address", "room", "queue" }
  /// Returns {} on success.
  Future<void> createMailbox({required String projectId, required String address, required String room, required String queue}) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/mailboxes');
    final body = {'address': address, 'room': room, 'queue': queue};

    final response = await http.post(uri, headers: _getHeaders(), body: jsonEncode(body));

    if (response.statusCode == 409) {
      throw AccountsClientException(
        'Failed to create mailbox. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to create mailbox. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  /// PUT /accounts/projects/{project_id}/mailboxes/{address}
  /// Body: { "room", "queue" }
  /// Returns {} on success.
  Future<void> updateMailbox({required String projectId, required String address, required String room, required String queue}) async {
    final encodedAddress = Uri.encodeComponent(address);
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/mailboxes/$encodedAddress');
    final body = {'room': room, 'queue': queue};

    final response = await http.put(uri, headers: _getHeaders(), body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to update mailbox. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  /// GET /accounts/projects/{project_id}/mailboxes
  /// Returns { "mailboxes": [ { "address","room","queue" }, ... ] }
  Future<List<Mailbox>> listMailboxes(String projectId) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/mailboxes');
    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to list mailboxes. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['mailboxes'] as List<dynamic>? ?? [];
    return list.whereType<Map<String, dynamic>>().map(Mailbox.fromJson).toList();
  }

  /// DELETE /accounts/projects/{project_id}/mailboxes/{address}
  /// Returns {} on success.
  Future<void> deleteMailbox({required String projectId, required String address}) async {
    final encodedAddress = Uri.encodeComponent(address);
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/mailboxes/$encodedAddress');

    final response = await http.delete(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to delete mailbox. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  /// Corresponds to: POST /accounts/projects/{project_id}/secrets
  /// Body: { "name": "...", "type": "...", "data": ... }
  /// Returns JSON like { "id": "new_secret_id" } on success.
  Future<Map<String, dynamic>> createProjectSecret({
    required String projectId,
    required String name,
    required String type,
    required Map<String, dynamic> data,
  }) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/secrets');
    final body = {'name': name, 'type': type, 'data': data};

    final response = await http.post(uri, headers: _getHeaders(), body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to create secret. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // Corresponds to: GET /pricing
  Future<Map<String, dynamic>> getPricing() async {
    final uri = Uri.parse('$baseUrl/pricing');
    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to get pricing data. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Corresponds to: GET /accounts/projects/{project_id}/secrets
  /// Returns JSON like { "secrets": [ { "id": ..., "name": ..., "type": ..., "data": ... } ] }.
  Future<List<Map<String, dynamic>>> listProjectSecrets(String projectId) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/secrets');
    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to list secrets. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final secretsList = data['secrets'] as List<dynamic>? ?? [];
    return secretsList.whereType<Map<String, dynamic>>().toList();
  }

  Future<void> updateProjectSettings({required String projectId, required Map<String, dynamic> settings}) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/settings');

    final response = await http.put(uri, headers: _getHeaders(), body: jsonEncode(settings));

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to update secret. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  /// Corresponds to: PUT /accounts/projects/{project_id}/secrets/{secret_id}
  /// Body: { "name": "...", "type": "...", "data": ... }
  /// Returns empty JSON object {} on success.
  Future<void> updateProjectSecret({
    required String projectId,
    required String secretId,
    required String name,
    required String type,
    required Map<String, dynamic> data,
  }) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/secrets/$secretId');
    final body = {'name': name, 'type': type, 'data': data};

    final response = await http.put(uri, headers: _getHeaders(), body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to update secret. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    // The server returns {} on success, so no need to parse.
  }

  /// Corresponds to: DELETE /accounts/projects/{project_id}/secrets/{secret_id}
  /// Returns {} or 204 No Content on success.
  Future<void> deleteProjectSecret({required String projectId, required String secretId}) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/secrets/$secretId');
    final response = await http.delete(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to delete secret. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    // Server might return {} or 204.
  }

  /// Corresponds to: POST /accounts/projects/:project_id/services
  /// Body: { "name", "image", "pull_secret", "runtime_secrets", "environment_secrets", "environment" : \<settings\> }
  /// Returns JSON like { "id" } on success.
  Future<String> createService({required String projectId, required Service service}) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/services');

    final response = await http.post(uri, headers: _getHeaders(), body: jsonEncode(service.toJson()));

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to create share. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return jsonDecode(response.body)["id"];
  }

  /// Corresponds to: POST /projects/:project_id/storage/upload
  Future<void> upload({required String projectId, required String path, required Uint8List data}) async {
    final uri = Uri.parse('$baseUrl/projects/$projectId/storage/upload').replace(queryParameters: {"path": path});

    final response = await http.post(uri, headers: _getHeaders(), body: data);

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to create share. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  /// Corresponds to: POST /projects/:project_id/storage/download
  Future<Uint8List> download({required String projectId, required String path}) async {
    final uri = Uri.parse('$baseUrl/projects/$projectId/storage/download').replace(queryParameters: {"path": path});

    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode == 404) {
      throw NotFoundException("file was not found");
    }
    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to create share. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return response.bodyBytes;
  }

  /// Corresponds to: POST /accounts/projects/:project_id/
  /// Body: { "environment" : \<settings\> }
  /// Returns JSON like { "id" } on success.
  Future<void> updateService({required String projectId, required String serviceId, required Service service}) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/services/$serviceId');

    final response = await http.put(uri, headers: _getHeaders(), body: jsonEncode(service.toJson()));

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to create share. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  /// Corresponds to: GET /accounts/projects/{project_id}/services
  /// Returns a JSON dict like: { "tokens": [ { ... }, ... ] }.
  Future<List<Service>> getProjectService({required String projectId, required String serviceId}) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/services/$serviceId');
    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to list project services keys. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    return jsonDecode(response.body);
  }

  /// Corresponds to: GET /accounts/projects/{project_id}/services
  /// Returns a JSON dict like: { "tokens": [ { ... }, ... ] }.
  Future<List<Service>> listProjectServices(String projectId) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/services');
    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to list project services keys. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    return (jsonDecode(response.body)["services"] as List).whereType<Map<String, dynamic>>().map((a) => Service.fromJson(a)).toList();
  }

  /// Corresponds to: DELETE /accounts/projects/{project_id}/services/{token_id}
  /// Returns 204 No Content on success (no JSON body).
  Future<void> deleteProjectService({required String projectId, required String serviceId}) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/services/$serviceId');
    final response = await http.delete(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to delete project service'
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
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/shares');

    final response = await http.post(uri, headers: _getHeaders(), body: jsonEncode({'settings': settings ?? {}}));

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to create share. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Corresponds to: DELETE /accounts/projects/:project_id/shares/:share_id
  /// No JSON response on success.
  Future<void> deleteShare(String projectId, String shareId) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/shares/$shareId');

    final response = await http.delete(uri, headers: _getHeaders());
    if (response.statusCode >= 400) {
      throw AccountsClientException(
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
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/shares/$shareId');

    final response = await http.put(uri, headers: _getHeaders(), body: jsonEncode({'settings': settings ?? {}}));

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to update share. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    // 200 or 204 on success, no body to parse
  }

  /// Corresponds to: GET /accounts/projects/:project_id/shares
  /// Returns JSON like { "shares": [ { "id", "settings" } ] } on success.
  Future<List<Map<String, dynamic>>> listShares(String projectId) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/shares');

    final response = await http.get(uri, headers: _getHeaders());
    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to list shares. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final sharesList = data['shares'] as List<dynamic>? ?? [];
    // Convert each item to Map<String, dynamic>
    return sharesList.whereType<Map<String, dynamic>>().toList();
  }

  /// Corresponds to: POST /shares/:share_id/connect
  /// Body: {}
  /// Returns JSON dict with { "jwt", "room_url" } on success.
  Future<RoomShareConnectionInfo> connectShare(String shareId) async {
    final uri = Uri.parse('$baseUrl/shares/$shareId/connect');

    final response = await http.post(uri, headers: _getHeaders(), body: jsonEncode({}));

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to connect share. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return RoomShareConnectionInfo.fromJson(jsonDecode(response.body));
  }

  /// Corresponds to: POST /accounts/projects
  /// Body: { "name": "\<name\>" }
  /// Returns JSON like { "id", "owner_user_id", "name" } on success.
  Future<Map<String, dynamic>> createProject(String name) async {
    final uri = Uri.parse('$baseUrl/accounts/projects');
    final response = await http.post(uri, headers: _getHeaders(), body: jsonEncode({'name': name}));

    if (response.statusCode >= 400) {
      throw AccountsClientException('Failed to create project. Status code: ${response.statusCode}, body: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Corresponds to: DELETE /accounts/projects/:project_id
  Future<void> deleteProject(String projectId) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId');

    final request = http.Request('DELETE', uri)..headers.addAll(_getHeaders());

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode >= 400) {
      throw AccountsClientException('Failed to remove user from project. Status code: ${response.statusCode}, body: ${response.body}');
    }
  }

  /// Corresponds to: POST /accounts/projects/:project_id/users
  /// Body: { "project_id", "user_id" }
  /// Returns JSON like { "ok": true } on success.
  Future<Map<String, dynamic>> addUserToProject(String projectId, String userId) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/users');
    final body = {'project_id': projectId, 'user_id': userId};

    final response = await http.post(uri, headers: _getHeaders(), body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw AccountsClientException('Failed to add user to project. Status code: ${response.statusCode}, body: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<bool> getStatus(String projectId) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/status');
    final response = await http.get(uri, headers: _getHeaders());

    final data = (jsonDecode(response.body) as Map<String, dynamic>);
    return data["enabled"] == true;
  }

  Future<Balance> getBalance(String projectId) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/balance');
    final response = await http.get(uri, headers: _getHeaders());

    final data = (jsonDecode(response.body) as Map<String, dynamic>);

    final lastRechargeStr = (data["last_recharge"] as String?);
    return Balance(
      balance: (data["balance"] as num).toDouble(),
      autoRechargeAmount: (data["auto_recharge_amount"] as num?)?.toDouble(),
      autoRechargeThreshhold: (data["auto_recharge_threshold"] as num?)?.toDouble(),
      lastRecharge: lastRechargeStr == null ? null : DateTime.parse(lastRechargeStr),
    );
  }

  Future<List<Transaction>> getRecentTransactions(String projectId) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/transactions');
    final response = await http.get(uri, headers: _getHeaders());

    final data = (jsonDecode(response.body) as Map<String, dynamic>);

    List<Transaction> transactions = [];

    for (var transaction in data["transactions"]) {
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
  }) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/recharge');
    final resp = await http.post(
      uri,
      headers: _getHeaders(),
      body: jsonEncode({"enabled": enabled, "amount": amount, "threshold": threshold}),
    );
    if (resp.statusCode != 200) {
      throw Exception("Unable to update autorecharge");
    }
  }

  Future<List<Map<String, dynamic>>> getUsage(String projectId, {DateTime? start, DateTime? end, String? interval, String? report}) async {
    var uri = Uri.parse('$baseUrl/accounts/projects/$projectId/usage');

    if (start != null) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, "start": start.toIso8601String()});
    }

    if (end != null) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, "end": end.toIso8601String()});
    }

    if (interval != null) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, "interval": interval});
    }

    if (report != null) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, "report": report});
    }

    final response = await http.get(uri, headers: _getHeaders());

    List<Map<String, dynamic>> results = [];

    for (final map in (jsonDecode(response.body) as Map<String, dynamic>)["usage"]) {
      results.add(map);
    }

    return results;
  }

  /// Corresponds to: POST /accounts/projects/:project_id/users/:user_id
  /// Body: { "is_admin" }
  /// Returns JSON like { "ok": true } on success.
  Future<void> updateUser({required String projectId, required String userId, required bool isAdmin, required bool isDeveloper}) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/users/$userId');
    final body = {'is_admin': isAdmin, "is_developer": isDeveloper};

    final response = await http.put(uri, headers: _getHeaders(), body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw AccountsClientException('Failed to add user to project. Status code: ${response.statusCode}, body: ${response.body}');
    }
  }

  /// Corresponds to: POST /accounts/projects/:project_id/users
  /// Body: { "project_id", "user_id" }
  /// Returns JSON like { "ok": true } on success.
  Future<Map<String, dynamic>> addUserToProjectByEmail(String projectId, String email) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/users');
    final body = {'project_id': projectId, 'email': email};

    final response = await http.post(uri, headers: _getHeaders(), body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw AccountsClientException('Failed to add user to project. Status code: ${response.statusCode}, body: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Corresponds to: DELETE /accounts/projects/:project_id/users
  /// Body: { "project_id", "user_id" }
  /// Returns JSON like { "ok": true } on success.
  Future<Map<String, dynamic>> removeUserFromProject(String projectId, String userId) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/users/$userId');

    final request = http.Request('DELETE', uri)..headers.addAll(_getHeaders());

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode >= 400) {
      throw AccountsClientException('Failed to remove user from project. Status code: ${response.statusCode}, body: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Corresponds to: GET /accounts/projects/:project_id/users
  /// Returns JSON like { "users": [...] } on success.
  Future<List<Map<String, dynamic>>> getUsersInProject(String projectId) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/users');
    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException('Failed to get users in project. Status code: ${response.statusCode}, body: ${response.body}');
    }
    return (jsonDecode(response.body)["users"] as List).whereType<Map<String, dynamic>>().toList();
  }

  /// Corresponds to: GET /accounts/profiles/:user_id
  /// Returns user profile JSON, e.g. { "id", "first_name", "last_name", "email" } on success
  /// or throws an error if not found.
  Future<Map<String, dynamic>> getUserProfile(String userId) async {
    final uri = Uri.parse('$baseUrl/accounts/profiles/$userId');
    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException('Failed to get user profile. Status code: ${response.statusCode}, body: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Corresponds to: PUT /accounts/profiles/:user_id
  /// Body: { "first_name", "last_name" }
  /// Returns JSON like { "ok": true } on success.
  Future<Map<String, dynamic>> updateUserProfile(String userId, String firstName, String lastName) async {
    final uri = Uri.parse('$baseUrl/accounts/profiles/$userId');
    final body = {'first_name': firstName, 'last_name': lastName};

    final response = await http.put(uri, headers: _getHeaders(), body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw AccountsClientException('Failed to update user profile. Status code: ${response.statusCode}, body: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Corresponds to: GET /accounts/projects
  /// Returns JSON like { "projects": [...] } on success.
  Future<List<Map<String, dynamic>>> listProjects() async {
    final uri = Uri.parse('$baseUrl/accounts/projects');
    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException('Failed to list projects. Status code: ${response.statusCode}, body: ${response.body}');
    }
    return (jsonDecode(response.body)["projects"] as List).whereType<Map<String, dynamic>>().toList();
  }

  /// Corresponds to: GET /accounts/projects/{project_id}
  /// Returns a role
  Future<ProjectRole> getProjectRole(String projectId) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/role');
    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException('Failed to list projects. Status code: ${response.statusCode}, body: ${response.body}');
    }
    final role = (jsonDecode(response.body) as Map<String, dynamic>)["role"];

    return switch (role) {
      "admin" => ProjectRole.admin,
      "developer" => ProjectRole.developer,
      _ => ProjectRole.member,
    };
  }

  /// Corresponds to: GET /accounts/projects
  /// Returns JSON like { "projects": [...] } on success.
  Future<Map<String, dynamic>> getProject(String projectId) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId');
    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException('Failed to list projects. Status code: ${response.statusCode}, body: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Corresponds to: POST /accounts/projects/{project_id}/api-keys
  /// Body: { "name": "", "description": "" }
  /// Returns a JSON dict with { "id", "name", "description", "token" }.
  Future<Map<String, dynamic>> createProjectApiKey(String projectId, String name, String description) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/api-keys');
    final body = {'name': name, 'description': description};

    final response = await http.post(uri, headers: _getHeaders(), body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to create project API key. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Corresponds to: DELETE /accounts/projects/{project_id}/api-keys/{token_id}
  /// Returns 204 No Content on success (no JSON body).
  Future<void> deleteProjectApiKey(String projectId, String tokenId) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/api-keys/$tokenId');
    final response = await http.delete(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to delete project API key. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    // 204 No Content -> no need to parse response body.
    return;
  }

  /// Corresponds to: GET /accounts/projects/{project_id}/api-keys
  /// Returns a JSON dict like: { "tokens": [ { ... }, ... ] }.
  Future<List<Map<String, dynamic>>> listProjectApiKeys(String projectId) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/api-keys');
    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to list project API keys. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    return (jsonDecode(response.body)["keys"] as List).whereType<Map<String, dynamic>>().toList();
  }

  /// Corresponds to: GET /accounts/projects/{project_id}/api-keys/{token_id}/decrypt
  Future<String> decryptProjectApiKey(String projectId, String tokenId) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/api-keys/$tokenId/decrypt');
    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to decrypt project API key. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    return (jsonDecode(response.body) as Map<String, dynamic>)["token"];
  }

  // In AccountsClient
  /// GET /accounts/projects/{project_id}/sessions
  /// Returns JSON: { "sessions": [ { "room_name", "started_at", "is_active" }, ... ] }
  Future<List<RoomSession>> listActiveSessions(String projectId) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/sessions/active');
    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
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
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/sessions');
    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to list recent sessions. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['sessions'] as List<dynamic>? ?? [];
    return list.whereType<Map<String, dynamic>>().map(RoomSession.fromJson).toList();
  }

  Future<String> getCreditsCheckoutUrl(String projectId, String successUrl, String cancelUrl, double quantity) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/credits');
    final response = await http.post(
      uri,
      headers: _getHeaders(),
      body: jsonEncode({"quantity": quantity, "success_url": successUrl, "cancel_url": cancelUrl}),
    );

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to get session. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    return jsonDecode(response.body)["checkout_url"];
  }

  Future<String> getCheckoutUrl(String projectId, String successUrl, String cancelUrl) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/subscription');
    final response = await http.post(uri, headers: _getHeaders(), body: jsonEncode({"success_url": successUrl, "cancel_url": cancelUrl}));

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to get session. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    return jsonDecode(response.body)["checkout_url"];
  }

  /// Corresponds to: GET /accounts/projects/{project_id}/sessions/{session_id}
  /// Returns a JSON dict: {"id","room_name","created_at"}
  Future<Map<String, dynamic>> getSession(String projectId, String sessionId) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/sessions/$sessionId');
    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to get session. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    return jsonDecode(response.body);
  }

  /// Corresponds to: POST /accounts/projects/{project_id}/sessions/{session_id}/terminate
  Future<void> terminate({required String projectId, required String sessionId}) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/sessions/$sessionId/terminate');
    final response = await http.post(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to terminate session. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  /// Corresponds to: GET /accounts/projects/{project_id}/sessions/{session_id}
  /// Returns a JSON dict: {"id","room_name","created_at"}
  Future<Map<String, dynamic>> getSubscription(String projectId) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/subscription');
    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to get session. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    return jsonDecode(response.body);
  }

  /// Corresponds to: GET /accounts/projects/{project_id}/sessions/{session_id}/events
  /// Returns a JSON dict: { "events": [...] }
  Future<List<Map<String, dynamic>>> listSessionEvents(String projectId, String sessionId) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/sessions/$sessionId/events');
    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to list session events. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    return (jsonDecode(response.body)["events"] as List).whereType<Map<String, dynamic>>().toList();
  }

  /// Corresponds to: GET /accounts/projects/{project_id}/sessions/{session_id}/spans
  /// Returns a JSON dict: { "spans": [...] }
  Future<List<Map<String, dynamic>>> listSessionSpans(String projectId, String sessionId) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/sessions/$sessionId/spans');
    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to list session spans. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    return (jsonDecode(response.body)["spans"] as List).whereType<Map<String, dynamic>>().toList();
  }

  /// Corresponds to: GET /accounts/projects/{project_id}/sessions/{session_id}/spans
  /// Returns a JSON dict: { "spans": [...] }
  Future<List<Map<String, dynamic>>> listSessionMetrics(String projectId, String sessionId) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/sessions/$sessionId/metrics');
    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to list session metrics. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    return (jsonDecode(response.body)["metrics"] as List).whereType<Map<String, dynamic>>().toList();
  }

  /// Corresponds to: POST /accounts/projects/{project_id}/webhooks
  /// Body: { "name", "description", "url", "events" }
  /// Returns the JSON object the server responds with (could be empty or the new resource data).
  Future<Map<String, dynamic>> createProjectWebhook(
    String projectId, {
    required String name,
    required String url,
    required List<String> events,
    String description = '',
    String? action,
    String? payload,
  }) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/webhooks');
    final body = {'name': name, 'description': description, 'url': url, 'events': events, 'payload': payload, 'action': action};

    final response = await http.post(uri, headers: _getHeaders(), body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to create project webhook. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Corresponds to: PUT /accounts/projects/{project_id}/webhooks/{webhook_id}
  /// Body: { "name", "description", "url", "events" }
  /// Returns the updated resource JSON or an empty object (depends on your server).
  Future<Map<String, dynamic>> updateProjectWebhook(
    String projectId,
    String webhookId, {
    required String name,
    required String url,
    required List<String> events,
    String description = '',
    String? action,
    String? payload,
  }) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/webhooks/$webhookId');
    final body = {'name': name, 'description': description, 'url': url, 'events': events, 'payload': payload, 'action': action};

    final response = await http.put(uri, headers: _getHeaders(), body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to update project webhook. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Corresponds to: GET /accounts/projects/{project_id}/webhooks
  /// Returns a JSON dict like { "webhooks": [ { ... }, ... ] }.
  Future<List<Map<String, dynamic>>> listProjectWebhooks(String projectId) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/webhooks');
    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to list project webhooks. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    return (jsonDecode(response.body)["webhooks"] as List).whereType<Map<String, dynamic>>().toList();
  }

  /// Corresponds to: DELETE /accounts/projects/{project_id}/webhooks/{webhook_id}
  /// Typically returns 200 or 204 on success (no JSON body).
  Future<void> deleteProjectWebhook(String projectId, String webhookId) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/webhooks/$webhookId');
    final response = await http.delete(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to delete project webhook. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    // 200 or 204 on success, no body to parse
    return;
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
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/room-grants');
    final body = {'room_id': roomId, 'user_id': userId, 'permissions': permissions.toJson()};

    final response = await http.post(uri, headers: _getHeaders(), body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw AccountsClientException(
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
  }) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/room-grants');
    final body = {'room_id': roomId, 'email': email, 'permissions': permissions.toJson()};

    final response = await http.post(uri, headers: _getHeaders(), body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw AccountsClientException(
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
    final gid = grantId ?? 'unused';
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/room-grants/$gid');

    final body = {'room_id': roomId, 'user_id': userId, 'permissions': permissions.toJson()};

    final response = await http.put(uri, headers: _getHeaders(), body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to update room grant. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  /// DELETE /accounts/projects/{project_id}/room-grants/{room_name}/{user_id}
  /// Returns {} on success.
  Future<void> deleteRoomGrant({required String projectId, required String roomId, required String userId}) async {
    final r = Uri.encodeComponent(roomId);
    final u = Uri.encodeComponent(userId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/room-grants/$r/$u');

    final response = await http.delete(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to delete room grant. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  /// GET /accounts/projects/{project_id}/room-grants/{room_name}/{user_id}
  /// Returns a ProjectRoomGrant.
  Future<ProjectRoomGrant> getRoomGrant({required String projectId, required String roomId, required String userId}) async {
    final r = Uri.encodeComponent(roomId);
    final u = Uri.encodeComponent(userId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/room-grants/$r/$u');

    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to get room grant. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return ProjectRoomGrant.fromJson(data);
  }

  /// GET /accounts/projects/{project_id}/rooms?limit=&offset=&order_by=
  Future<List<Room>> listRooms({required String projectId, int limit = 50, int offset = 0, String orderBy = 'room_name'}) async {
    var uri = Uri.parse('$baseUrl/accounts/projects/$projectId/rooms');
    uri = uri.replace(queryParameters: {'limit': '$limit', 'offset': '$offset', 'order_by': orderBy});

    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to list rooms. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['rooms'] as List<dynamic>? ?? [];
    return list.whereType<Map<String, dynamic>>().map(Room.fromJson).toList();
  }

  /// GET /accounts/projects/{project_id}/room-grants?limit=&offset=&order_by=
  Future<List<ProjectRoomGrant>> listRoomGrants({
    required String projectId,
    int limit = 50,
    int offset = 0,
    String orderBy = 'room_name',
  }) async {
    var uri = Uri.parse('$baseUrl/accounts/projects/$projectId/room-grants');
    uri = uri.replace(queryParameters: {'limit': '$limit', 'offset': '$offset', 'order_by': orderBy});

    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
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
    int limit = 50,
    int offset = 0,
    String orderBy = 'room_name',
  }) async {
    final u = Uri.encodeComponent(userId);
    var uri = Uri.parse(
      '$baseUrl/accounts/projects/$projectId/room-grants/by-user/$u',
    ).replace(queryParameters: {'limit': '$limit', 'offset': '$offset', 'order_by': orderBy});

    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to list room grants by user. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['room_grants'] as List<dynamic>? ?? [];
    return list.whereType<Map<String, dynamic>>().map(ProjectRoomGrant.fromJson).toList();
  }

  /// GET /accounts/projects/{project_id}/room-grants/by-room/{room_name}?limit=&offset=&order_by=
  Future<List<ProjectRoomGrant>> listRoomGrantsByRoom({
    required String projectId,
    required String roomName,
    int limit = 50,
    int offset = 0,
    String orderBy = 'user_id',
  }) async {
    final r = Uri.encodeComponent(roomName);
    var uri = Uri.parse(
      '$baseUrl/accounts/projects/$projectId/room-grants/by-room/$r',
    ).replace(queryParameters: {'limit': '$limit', 'offset': '$offset', 'order_by': orderBy});

    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
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
    var uri = Uri.parse(
      '$baseUrl/accounts/projects/$projectId/room-grants/by-room',
    ).replace(queryParameters: {'limit': '$limit', 'offset': '$offset'});

    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to list unique rooms with grants. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['rooms'] as List<dynamic>? ?? [];
    return list.whereType<Map<String, dynamic>>().map(ProjectRoomGrantCount.fromJson).toList();
  }

  /// GET /accounts/projects/{project_id}/room-grants/by-user?limit=&offset=
  Future<List<ProjectUserGrantCount>> listUniqueUsersWithGrants({required String projectId, int limit = 50, int offset = 0}) async {
    var uri = Uri.parse(
      '$baseUrl/accounts/projects/$projectId/room-grants/by-user',
    ).replace(queryParameters: {'limit': '$limit', 'offset': '$offset'});

    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to list unique users with grants. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['users'] as List<dynamic>? ?? [];
    return list.whereType<Map<String, dynamic>>().map(ProjectUserGrantCount.fromJson).toList();
  }

  /// --------------------------------
  /// Rooms
  /// --------------------------------

  /// POST /accounts/projects/{project_id}/rooms
  /// Body: { "name": "name", "if_not_exists": bool }
  /// Returns a Room on success.
  Future<Room> createRoom({required String projectId, required String name, bool ifNotExists = false}) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/rooms');
    final response = await http.post(uri, headers: _getHeaders(), body: jsonEncode({'name': name, 'if_not_exists': ifNotExists}));

    if (response.statusCode == 409) {
      throw NameInUseException("The room name is already in use");
    } else if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to create room. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return Room.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// GET /accounts/projects/{project_id}/rooms/{room_name}
  /// Returns a Room (404 -> NotFoundException).
  Future<Room> getRoom({required String projectId, required String name}) async {
    final r = Uri.encodeComponent(name);
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/rooms/$r');

    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode == 404) {
      throw NotFoundException('room not found');
    }
    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to get room. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return Room.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// PUT /accounts/projects/{project_id}/rooms/{room_id}
  /// Body: { "name": "new name" }
  Future<void> updateRoom({required String projectId, required String roomId, required String name}) async {
    final rid = Uri.encodeComponent(roomId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/rooms/$rid');

    final response = await http.put(uri, headers: _getHeaders(), body: jsonEncode({'name': name}));

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to update room. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  /// DELETE /accounts/projects/{project_id}/rooms/{room_id}
  Future<void> deleteRoom({required String projectId, required String roomId}) async {
    final rid = Uri.encodeComponent(roomId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/rooms/$rid');

    final response = await http.delete(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to delete room. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
  }

  /// POST /accounts/projects/{project_id}/rooms/{room_name}/connect
  /// Body: {}
  /// Returns { "jwt", "room_name", "project_id", "room_url" } on success.
  Future<RoomConnectionInfo> connectRoom({required String projectId, required String roomName}) async {
    final r = Uri.encodeComponent(roomName);
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/rooms/$r/connect');

    final response = await http.post(uri, headers: _getHeaders(), body: jsonEncode({}));

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to connect room. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return RoomConnectionInfo.fromJson(jsonDecode(response.body));
  }

  /// --------------------------------
  /// Services (single fetch)
  /// --------------------------------

  /// GET /accounts/projects/{project_id}/services/{service_id}
  /// Returns a single Service.
  ///
  /// Note: Some servers may return the JSON as a string payload.
  /// This method handles both a Map response and a stringified JSON.
  Future<Service> getService({required String projectId, required String serviceId}) async {
    final sid = Uri.encodeComponent(serviceId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/services/$sid');

    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to get service. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    final Map<String, dynamic> json = decoded is String ? jsonDecode(decoded) as Map<String, dynamic> : decoded as Map<String, dynamic>;

    return Service.fromJson(json);
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
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/oauth/clients');
    final body = <String, dynamic>{
      'grant_types': grantTypes,
      'response_types': responseTypes,
      'redirect_uris': redirectUris,
      'scope': scope,
      'metadata': metadata ?? <String, dynamic>{},
    };

    final response = await http.post(uri, headers: _getHeaders(), body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw AccountsClientException(
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
    final cid = Uri.encodeComponent(clientId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/oauth/clients/$cid');

    final body = <String, dynamic>{};
    if (grantTypes != null) body['grant_types'] = grantTypes;
    if (responseTypes != null) body['response_types'] = responseTypes;
    if (redirectUris != null) body['redirect_uris'] = redirectUris;
    if (scope != null) body['scope'] = scope;
    if (metadata != null) body['metadata'] = metadata;

    final response = await http.put(uri, headers: _getHeaders(), body: jsonEncode(body));

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to update OAuth client. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// GET /accounts/projects/{project_id}/oauth/clients
  /// Returns a list of OAuthClient (no secrets).
  Future<List<OAuthClient>> listOAuthClients(String projectId) async {
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/oauth/clients');
    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to list OAuth clients. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final list = decoded['clients'] as List<dynamic>? ?? const [];
    return list.whereType<Map<String, dynamic>>().map(OAuthClient.fromJson).toList();
  }

  /// GET /accounts/projects/{project_id}/oauth/clients/{client_id}
  /// Returns one OAuthClient (no secret). 404 -> NotFoundException.
  Future<OAuthClient> getOAuthClient(String projectId, String clientId) async {
    final cid = Uri.encodeComponent(clientId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/oauth/clients/$cid');

    final response = await http.get(uri, headers: _getHeaders());

    if (response.statusCode == 404) {
      throw NotFoundException('oauth client not found');
    }
    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to get OAuth client. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }

    return OAuthClient.fromJson(jsonDecode(response.body));
  }

  /// DELETE /accounts/projects/{project_id}/oauth/clients/{client_id}
  /// Returns 204 No Content on success.
  Future<void> deleteOAuthClient(String projectId, String clientId) async {
    final cid = Uri.encodeComponent(clientId);
    final uri = Uri.parse('$baseUrl/accounts/projects/$projectId/oauth/clients/$cid');

    final response = await http.delete(uri, headers: _getHeaders());

    if (response.statusCode >= 400) {
      throw AccountsClientException(
        'Failed to delete OAuth client. '
        'Status code: ${response.statusCode}, body: ${response.body}',
      );
    }
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

class Room {
  const Room({required this.name, required this.id});

  final String name;
  final String id;

  static Room fromJson(Map<String, dynamic> json) {
    return Room(id: json["id"], name: json["name"]);
  }

  Map<String, dynamic> toJson() => {"name": name, "id": id};
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

  Map<String, dynamic> toJson() => {'room': room.toJson(), 'user_id': userId, 'permissions': permissions};
}

class ProjectRoomGrantCount {
  final Room room;
  final int count;

  ProjectRoomGrantCount({required this.room, required this.count});

  factory ProjectRoomGrantCount.fromJson(Map<String, dynamic> json) {
    final dynamic c = json['count'];
    final int parsedCount =
        c is int
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
    final int parsedCount =
        c is int
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

/// A simple custom exception to denote HTTP errors.
class AccountsClientException implements Exception {
  final String message;
  AccountsClientException(this.message);

  @override
  String toString() => 'HttpException: $message';
}

class NotFoundException extends AccountsClientException {
  NotFoundException(super.message);
}

class NameInUseException extends AccountsClientException {
  NameInUseException(super.message);
}

class Endpoint {
  String? type; // "mcp.sse", "meshagent.callable", "http", "tcp"
  String? path;
  String? participantName;
  String? role; // "user", "tool", "agent"

  Endpoint({this.type, this.path, this.participantName, this.role});

  factory Endpoint.fromJson(Map<String, dynamic> json) => Endpoint(
    type: json['type'] as String?,
    path: json['path'] as String?,
    participantName: json['participant_name'] as String?,
    role: json['role'] as String?,
  );

  Map<String, dynamic> toJson() => {
    if (type != null) 'type': type,
    if (path != null) 'path': path,
    if (participantName != null) 'participant_name': participantName,
    if (role != null) 'role': role,
  };
}

class Port {
  String? livenessPath;
  String? participantName;

  String? type; // "mcp.sse", "meshagent.callable", "http", "tcp"
  String? path;

  List<Endpoint>? endpoints;

  Port({this.livenessPath, this.participantName, this.type, this.path, this.endpoints});

  factory Port.fromJson(Map<String, dynamic> json) => Port(
    livenessPath: json['liveness_path'] as String?,
    participantName: json['participant_name'] as String?,
    type: json['type'] as String?,
    path: json['path'] as String?,
    endpoints: (json['endpoints'] as List?)?.map((e) => Endpoint.fromJson(e as Map<String, dynamic>)).toList(),
  );

  Map<String, dynamic> toJson() => {
    if (livenessPath != null) 'liveness_path': livenessPath,
    if (participantName != null) 'participant_name': participantName,
    if (type != null) 'type': type,
    if (path != null) 'path': path,
    if (endpoints != null) 'endpoints': endpoints!.map((e) => e.toJson()).toList(),
  };
}

class RoomStorageMount {
  String path;
  String? subpath;
  bool readOnly;

  RoomStorageMount({required this.path, this.subpath, this.readOnly = false});

  factory RoomStorageMount.fromJson(Map<String, dynamic> json) =>
      RoomStorageMount(path: json['path'] as String, subpath: json['subpath'] as String?, readOnly: json['read_only'] as bool? ?? false);

  Map<String, dynamic> toJson() => {'path': path, if (subpath != null) 'subpath': subpath, 'read_only': readOnly};
}

class ProjectStorageMount {
  String path;
  String? subpath;
  bool readOnly;

  ProjectStorageMount({required this.path, this.subpath, this.readOnly = true});

  factory ProjectStorageMount.fromJson(Map<String, dynamic> json) =>
      ProjectStorageMount(path: json['path'] as String, subpath: json['subpath'] as String?, readOnly: json['read_only'] as bool? ?? true);

  Map<String, dynamic> toJson() => {'path': path, if (subpath != null) 'subpath': subpath, 'read_only': readOnly};
}

class ServiceStorageMounts {
  List<RoomStorageMount>? room;
  List<ProjectStorageMount>? project;

  ServiceStorageMounts({this.room, this.project});

  factory ServiceStorageMounts.fromJson(Map<String, dynamic> json) => ServiceStorageMounts(
    room: (json['room'] as List?)?.map((e) => RoomStorageMount.fromJson(e as Map<String, dynamic>)).toList(),
    project: (json['project'] as List?)?.map((e) => ProjectStorageMount.fromJson(e as Map<String, dynamic>)).toList(),
  );

  Map<String, dynamic> toJson() => {
    if (room != null) 'room': room!.map((e) => e.toJson()).toList(),
    if (project != null) 'project': project!.map((e) => e.toJson()).toList(),
  };
}

class Service {
  String? id;
  final String image;
  final String name;

  Map<String, String>? environment;
  String? command;
  String? roomStoragePath;
  String? roomStorageSubpath;
  String? pullSecret;
  Map<String, String>? runtimeSecrets;
  List<String>? environmentSecrets;
  String? createdAt;
  Map<String, Port>? ports;
  String? role; // "user", "tool", "agent"
  bool builtin;
  ServiceStorageMounts? storage;

  Service({
    this.id,
    required this.image,
    required this.name,
    this.environment,
    this.command,
    this.roomStoragePath,
    this.roomStorageSubpath,
    this.pullSecret,
    this.runtimeSecrets,
    this.environmentSecrets,
    this.createdAt,
    this.ports,
    this.role,
    this.builtin = false,
    this.storage,
  });

  factory Service.fromJson(Map<String, dynamic> json) => Service(
    id: json['id'] as String?,
    image: json['image'] as String,
    name: json['name'] as String,
    environment: (json['environment'] as Map?)?.cast<String, String>(),
    command: json['command'] as String?,
    roomStoragePath: json['room_storage_path'] as String?,
    roomStorageSubpath: json['room_storage_subpath'] as String?,
    pullSecret: json['pull_secret'] as String?,
    runtimeSecrets: (json['runtime_secrets'] as Map?)?.cast<String, String>(),
    environmentSecrets: (json['environment_secrets'] as List?)?.cast<String>(),
    createdAt: json['created_at'] as String?,
    ports: (json['ports'] as Map?)?.map((k, v) => MapEntry(k as String, Port.fromJson(v as Map<String, dynamic>))),
    role: json['role'] as String?,
    builtin: json['builtin'] as bool? ?? false,
    storage: json['storage'] != null ? ServiceStorageMounts.fromJson(json['storage'] as Map<String, dynamic>) : null,
  );

  Map<String, dynamic> toJson() => {
    'image': image,
    'name': name,
    if (id != null) 'id': id,
    if (environment != null) 'environment': environment,
    if (command != null) 'command': command,
    if (roomStoragePath != null) 'room_storage_path': roomStoragePath,
    if (roomStorageSubpath != null) 'room_storage_subpath': roomStorageSubpath,
    if (pullSecret != null) 'pull_secret': pullSecret,
    if (runtimeSecrets != null) 'runtime_secrets': runtimeSecrets,
    if (environmentSecrets != null) 'environment_secrets': environmentSecrets,
    if (createdAt != null) 'created_at': createdAt,
    if (ports != null) 'ports': ports!.map((k, v) => MapEntry(k, v.toJson())),
    if (role != null) 'role': role,
    'builtin': builtin,
    if (storage != null) 'storage': storage!.toJson(),
  };
}

class Services {
  final List<Service> services;

  Services({required this.services});

  factory Services.fromJson(Map<String, dynamic> json) =>
      Services(services: (json['services'] as List).map((e) => Service.fromJson(e as Map<String, dynamic>)).toList());

  Map<String, dynamic> toJson() => {'services': services.map((e) => e.toJson()).toList()};
}
