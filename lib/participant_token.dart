import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

class ParticipantGrant {
  final String name;
  final String? scope;

  ParticipantGrant({
    required this.name,
    this.scope,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'scope': scope,
    };
  }

  factory ParticipantGrant.fromJson(Map<String, dynamic> json) {
    return ParticipantGrant(
      name: json['name'] as String,
      scope: json['scope'] as String?,
    );
  }
}

class ParticipantToken {
  final String name;
  final String? projectId;
  final String? apiKeyId;

  final List<ParticipantGrant> grants;

  final Map<String, dynamic>? extra;

  ParticipantToken({
    required this.name,
    required String projectId,
    required String apiKeyId,
    this.extra,
    List<ParticipantGrant>? grants,
  })  : grants = grants ?? [],
        projectId = projectId,
        apiKeyId = apiKeyId;

  bool get isAgent {
    for (final grant in grants) {
      if (grant.name == "role" && grant.scope == "agent") {
        return true;
      }
    }
    return false;
  }

  void addRoleGrant(String role) {
    grants.add(ParticipantGrant(name: "role", scope: role));
  }

  /// Adds a 'room' grant to the participant token.
  void addRoomGrant(String roomName) {
    grants.add(ParticipantGrant(name: 'room', scope: roomName));
  }

  /// Converts this object to a JSON-compatible Map.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (projectId != null) 'sub': projectId,
      if (apiKeyId != null) 'kid': apiKeyId,
      'grants': grants.map((g) => g.toJson()).toList(),
    };
  }

  /// Encodes this object as a JWT string.
  /// If [token] is not provided, tries to read from ENV ['MESHAGENT_SECRET'].
  /// [extraPayload] merges additional data into the JWT payload.
  String toJwt({String? token}) {
    // Fallback to environment variable if not provided
    token ??= const String.fromEnvironment('MESHAGENT_SECRET');

    final payload = <String, dynamic>{
      ...toJson(),
      ...?extra,
    };

    final jwt = JWT(payload);
    return jwt.sign(
      SecretKey(token),
      algorithm: JWTAlgorithm.HS256,
    );
  }

  /// Creates a [ParticipantToken] from a JSON Map.
  factory ParticipantToken.fromJson(Map<String, dynamic> json) {
    var extra = Map<String, dynamic>();
    for (final key in json.keys) {
      if (key != 'name' && key != 'sub' && key != 'grants' && key != 'kid') {
        extra[key] = json[key];
      }
    }

    return ParticipantToken(
        name: json['name'] as String,
        projectId: json['sub'],
        apiKeyId: json['kid'],
        grants: (json['grants'] as List<dynamic>)
            .map((g) => ParticipantGrant.fromJson(g as Map<String, dynamic>))
            .toList(),
        extra: extra);
  }

  /// Decodes a JWT string to create a [ParticipantToken].
  /// If [token] is not provided, tries to read from ENV ['MESHAGENT_SECRET'].
  factory ParticipantToken.fromJwt(String jwtStr,
      {String? token, bool verify = true}) {
    // Fallback to environment variable if not provided
    if (verify) {
      token ??= const String.fromEnvironment('MESHAGENT_SECRET');
      final jwt = JWT.verify(
        jwtStr,
        SecretKey(token),
        checkHeaderType: false,
      );

      final payload = jwt.payload as Map<String, dynamic>;
      return ParticipantToken.fromJson(payload);
    } else {
      final jwt = JWT.decode(
        jwtStr,
      );

      final payload = jwt.payload as Map<String, dynamic>;
      return ParticipantToken.fromJson(payload);
    }
  }
}
