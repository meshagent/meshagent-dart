const List<String> fullOAuthScopes = <String>[
  'profile',
  'project/*',
  'room/*',
  'create_users',
  'create_rooms',
  'admin',
  'developer',
  'connect_room',
  'delete_room',
  'update_room',
];

final String fullOAuthScope = fullOAuthScopes.join(' ');
