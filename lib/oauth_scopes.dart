const List<String> fullOAuthScopes = <String>[
  'profile',
  'project/*',
  'room/*',
  'create_users',
  'create_rooms',
  'create_agents',
  'managed_agents',
  'llm_proxy',
  'admin',
  'developer',
  'connect_room',
  'delete_room',
  'update_room',
  'delete_agent',
  'update_agent',
];

const String fullOAuthScope =
    'profile project/* room/* create_users create_rooms create_agents '
    'managed_agents llm_proxy admin developer connect_room delete_room '
    'update_room delete_agent update_agent';
