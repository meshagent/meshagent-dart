/// Room-owned external storage locations. Credentials are never returned by CRUD APIs.
sealed class StorageConnectionConfig {
  const StorageConnectionConfig({this.prefix = ''});
  final String prefix;
  String get provider;
  String get location;
  Map<String, dynamic> toJson();

  factory StorageConnectionConfig.fromJson(Map<String, dynamic> json) => switch (json['provider']) {
    's3' => S3StorageConfig(bucket: json['bucket'] as String, region: json['region'] as String, prefix: json['prefix'] as String? ?? ''),
    'gcs' => GCSStorageConfig(bucket: json['bucket'] as String, prefix: json['prefix'] as String? ?? ''),
    'azure' => AzureStorageConfig(
      account: json['account'] as String,
      container: json['container'] as String,
      prefix: json['prefix'] as String? ?? '',
    ),
    _ => throw const FormatException('Unknown storage provider'),
  };
}

class S3StorageConfig extends StorageConnectionConfig {
  const S3StorageConfig({required this.bucket, required this.region, super.prefix});
  final String bucket;
  final String region;
  @override
  String get provider => 's3';
  @override
  String get location => 's3://$bucket${prefix.isEmpty ? '' : '/$prefix'}';
  @override
  Map<String, dynamic> toJson() => {'provider': provider, 'bucket': bucket, 'region': region, 'prefix': prefix};
}

class GCSStorageConfig extends StorageConnectionConfig {
  const GCSStorageConfig({required this.bucket, super.prefix});
  final String bucket;
  @override
  String get provider => 'gcs';
  @override
  String get location => 'gs://$bucket${prefix.isEmpty ? '' : '/$prefix'}';
  @override
  Map<String, dynamic> toJson() => {'provider': provider, 'bucket': bucket, 'prefix': prefix};
}

class AzureStorageConfig extends StorageConnectionConfig {
  const AzureStorageConfig({required this.account, required this.container, super.prefix});
  final String account;
  final String container;
  @override
  String get provider => 'azure';
  @override
  String get location => 'https://$account.blob.core.windows.net/$container${prefix.isEmpty ? '' : '/$prefix'}';
  @override
  Map<String, dynamic> toJson() => {'provider': provider, 'account': account, 'container': container, 'prefix': prefix};
}

sealed class StorageConnectionCredentials {
  const StorageConnectionCredentials();
  String get provider;
  Map<String, dynamic> toJson();
}

class S3StorageCredentials extends StorageConnectionCredentials {
  const S3StorageCredentials({required this.accessKeyId, required this.secretAccessKey, this.sessionToken});
  final String accessKeyId;
  final String secretAccessKey;
  final String? sessionToken;
  @override
  String get provider => 's3';
  @override
  Map<String, dynamic> toJson() => {
    'provider': provider,
    'access_key_id': accessKeyId,
    'secret_access_key': secretAccessKey,
    'session_token': sessionToken,
  };
}

class GCSStorageCredentials extends StorageConnectionCredentials {
  const GCSStorageCredentials({required this.serviceAccountJson});
  final Map<String, dynamic> serviceAccountJson;
  @override
  String get provider => 'gcs';
  @override
  Map<String, dynamic> toJson() => {'provider': provider, 'service_account_json': serviceAccountJson};
}

class AzureStorageCredentials extends StorageConnectionCredentials {
  const AzureStorageCredentials.accountKey(String value) : accountKey = value, sasToken = null;
  const AzureStorageCredentials.sasToken(String value) : sasToken = value, accountKey = null;
  final String? accountKey;
  final String? sasToken;
  @override
  String get provider => 'azure';
  @override
  Map<String, dynamic> toJson() => {'provider': provider, 'account_key': accountKey, 'sas_token': sasToken};
}

class StorageConnection {
  const StorageConnection({
    required this.id,
    required this.roomId,
    required this.name,
    required this.config,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id;
  final String roomId;
  final String name;
  final StorageConnectionConfig config;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory StorageConnection.fromJson(Map<String, dynamic> json) => StorageConnection(
    id: json['id'] as String,
    roomId: json['room_id'] as String,
    name: json['name'] as String,
    config: StorageConnectionConfig.fromJson(json['config'] as Map<String, dynamic>),
    revision: json['revision'] as int,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );
}
