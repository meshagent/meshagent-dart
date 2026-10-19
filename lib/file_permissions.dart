String validateFilePath(String value) {
  if (value.contains(RegExp(r'[\\\x00-\x1f\x7f-\x9f]')) ||
      (value.isNotEmpty &&
          value
              .split('/')
              .any(
                (part) =>
                    part.isEmpty || part == '.' || part == '..' || part == '.meshagent-directory' || part.startsWith('.meshagent-upload-'),
              ))) {
    throw ArgumentError.value(value, 'path', 'Expected a canonical relative files path');
  }
  return value;
}

enum FileAction { list, read, write, delete, presign }

class FilePermissions {
  FilePermissions({required Set<FileAction> actions, required Set<FileAction> recursiveActions})
    : actions = Set.unmodifiable(actions),
      recursiveActions = Set.unmodifiable(recursiveActions);

  final Set<FileAction> actions;
  final Set<FileAction> recursiveActions;

  factory FilePermissions.fromJson(Map<String, dynamic> json) => FilePermissions(
    actions: (json['actions'] as List).map((value) => FileAction.values.byName(value as String)).toSet(),
    recursiveActions: (json['recursive_actions'] as List).map((value) => FileAction.values.byName(value as String)).toSet(),
  );
}

bool _descendant(String parent, String path) => parent.isEmpty || path.startsWith('$parent/');

class FilePathRule {
  FilePathRule({
    required String path,
    required this.recursive,
    required Iterable<FileAction> actions,
    Iterable<String> excludedPaths = const [],
  }) : path = validateFilePath(path),
       actions = Set.unmodifiable(actions),
       excludedPaths = List.unmodifiable(excludedPaths.map(validateFilePath)) {
    if (this.excludedPaths.length > 1000) throw ArgumentError('Too many file policy exclusions');
  }
  final String path;
  final bool recursive;
  final Set<FileAction> actions;
  final List<String> excludedPaths;
  bool allows(FileAction action, String value, {bool subtree = false}) {
    validateFilePath(value);
    return actions.contains(action) &&
        (!subtree || recursive) &&
        (value == path || recursive && _descendant(path, value)) &&
        !excludedPaths.any((excluded) => value == excluded || _descendant(excluded, value) || subtree && _descendant(value, excluded));
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'recursive': recursive,
    'actions': actions.map((action) => action.name).toList(),
    'excluded_paths': excludedPaths,
  };
  factory FilePathRule.fromJson(Map<String, dynamic> json) => FilePathRule(
    path: json['path'] as String,
    recursive: json['recursive'] as bool,
    actions: (json['actions'] as List).map((value) => FileAction.values.byName(value as String)),
    excludedPaths: ((json['excluded_paths'] as List?) ?? []).cast<String>(),
  );
}

class FilesPolicy {
  FilesPolicy({Iterable<FilePathRule> paths = const []}) : paths = List.unmodifiable(paths) {
    if (this.paths.length > 1000) throw ArgumentError('Too many file policy paths');
  }
  final List<FilePathRule> paths;
  bool allows(FileAction action, String path, {bool subtree = false}) {
    validateFilePath(path);
    return paths.any((rule) => rule.allows(action, path, subtree: subtree));
  }

  bool canListDirectory(String path) =>
      allows(FileAction.list, path) || paths.any((rule) => rule.allows(FileAction.list, rule.path) && _descendant(path, rule.path));
  Map<String, dynamic> toJson() => {'paths': paths.map((rule) => rule.toJson()).toList()};
  factory FilesPolicy.fromJson(Map<String, dynamic> json) =>
      FilesPolicy(paths: ((json['paths'] as List?) ?? []).map((value) => FilePathRule.fromJson((value as Map).cast<String, dynamic>())));
}

String storageRequestPath(String path) {
  while (path.startsWith('./')) {
    path = path.substring(2);
  }
  path = path.replaceAll(RegExp(r'^/+|/+$'), '');
  return validateFilePath(path == '.' ? '' : path);
}

FilesPolicy legacyStoragePolicy(Iterable<({String path, bool readOnly})>? paths) {
  if (paths == null) {
    return FilesPolicy(
      paths: [
        FilePathRule(path: '', recursive: true, actions: [FileAction.list, FileAction.read, FileAction.write, FileAction.delete]),
      ],
    );
  }
  final previous = <String>[];
  final rules = <FilePathRule>[];
  for (final grant in paths) {
    final path = grant.path.replaceAll(RegExp(r'^/+|/+$'), '');
    rules.add(
      FilePathRule(
        path: path,
        recursive: true,
        actions: grant.readOnly
            ? [FileAction.list, FileAction.read]
            : [FileAction.list, FileAction.read, FileAction.write, FileAction.delete],
        excludedPaths: previous,
      ),
    );
    previous.add(path);
  }
  return FilesPolicy(paths: rules);
}
