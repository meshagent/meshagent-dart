## [0.25.8]
- Stability

## [0.25.7]
- Stability

## [0.25.6]
- Stability

## [0.25.5]
- Stability

## [0.25.4]
- Stability

## [0.25.3]
- Stability

## [0.25.2]
- Stability

## [0.25.1]
- Stability

## [0.25.0]
- Added OAuth session management and a refreshable access token provider for Flutter auth; the Dart client now supports token providers.
- Dart client now URI-encodes path segments for account, room, and service endpoints.
- Added SQL query support in the Dart database client with TableRef and typed params.
- Added `published`/`public` port fields and `for_identity` support for secrets in the Dart room client.
- Flutter Shadcn file viewer adds a syntax-highlighted code editor preview; added `flutter_highlight` 0.7.0.

## [0.24.5]
- Stability

## [0.24.4]
- Stability

## [0.24.3]
- Stability

## [0.24.2]
- Stability

## [0.24.1]
- Stability

## [0.24.0]
- Breaking: removed `AgentsClient.ask` and `listAgents` from the Dart SDK.
- Breaking: `AgentCallContext` renamed to `TaskContext` for task runner/service APIs.
- Breaking: removed Luau `agents.ask`/`agents.askWithAttachment` and the AI code editor tab from Flutter widgets.

## [0.23.0]
- Breaking: create/update service from template APIs now accept YAML template strings instead of ServiceTemplateSpec, and a renderTemplate helper is added
- Added template-specific model support (agent templates and template environment variables) including token roles
- Added file storage mounts in container specs
- Added secrets listing in the room server client
- Project roles now include none
- Dependency updates: add collection ^1.19.1, source_span ^1.10.1, string_scanner ^1.4.1

## [0.22.2]
- Stability

## [0.22.1]
- Stability

## [0.22.0]
- Breaking: Livekit client removed from meshagent-dart and moved to meshagent-flutter with livekit_client ^2.4.0 and a Livekit protocol channel helper.
- Breaking: createService/updateService now return ServiceSpec objects; service template create/update APIs added for project and room services.
- Added room mailbox listing plus secret request/response APIs (request/provide/get/set/delete/delete-requested) with SecretRequestHandler support in RoomClient and Flutter RoomConnectionScope.
- Added meshagent_git_credentials helper for Git credential lookup via room secrets (crypto ^3.0.6).
- Dependency updates across SDK Flutter packages: shadcn_ui ^0.43.2 and super_clipboard ^0.9.1.

## [0.21.0]
- Add token-backed environment variables in service specs so Dart clients can inject participant tokens instead of static values.
- Expose `on_demand` and `writable_root_fs` flags on container specs to control per-request services and filesystem mutability.

## [0.20.6]
- Stability

## [0.20.5]
- Stability

## [0.20.4]
- Stability

## [0.20.3]
- Stability

## [0.20.2]
- Stability

## [0.20.1]
- Stability

## [0.20.0]
- Breaking: mailbox models now include a required `public` field in serialization/deserialization
- Mailbox create/update APIs accept a `public` flag (defaulting to false) and send it in requests
- Service template variables include optional `annotations` metadata
- External service specs allow an optional base URL
- Flutter shadcn chat widgets add message context menu actions (copy, save-as, delete) and folder-selection support in the file browser

## [0.19.5]
- Stability

## [0.19.4]
- Stability

## [0.19.3]
- Stability

## [0.19.2]
- Add boolean data type support in Dart schema types.
- Dart schema JSON now includes `nullable` and `metadata` for type round-tripping.
- BREAKING: MCP server config parsing now requires snake_case keys and no longer accepts camelCase fallbacks.

## [0.19.1]
- Add `host_port` support to the Dart room server client port specification JSON model (`host_port`) so clients can represent host-side port mappings

## [0.19.0]
- Add optional transcription support for voice calls, including sending a transcript path in the voice session request
- Add a localization toolkit with a “get local time” tool that returns current time and timezone
- Add dependency `flutter_timezone` ^5.0.1 (resolved to 5.0.1)

## [0.18.2]
- Stability

## [0.18.1]
- Stability

## [0.18.0]
- Added `ApiScope.tunnels` (with allowed `ports`) to participant tokens for tunnel authorization
- Added `writableRootFs` support to container run requests
- Fixed service mount-spec JSON parsing for `images`
- Service template commands now support variable formatting/substitution

## [0.17.1]
- Clarified the scheduled-task creation response shape in the Dart client documentation.

## [0.17.0]
- Added scheduled tasks API client support (models + create/update/list/delete helpers)
- Added `RequiredTable` requirement type and `installTable` helper to create tables, indexes, and optimize
- Added `replace` option for database index creation APIs (scalar/full-text/vector) to support idempotent index updates
- Breaking: removed `AgentDescription.requires` from Dart room client models/JSON serialization
- Updated Dart dependency: `http` to `^1.6.0`

## [0.16.0]
- Add optional `namespace` support across database client operations (list/inspect/create/drop/index/etc.) to target namespaced tables

## [0.15.0]
- Added a Dart client helper to query whether a user can create rooms for a given project.
- Added `tabs`/`tab` UI components (including initial tab selection, active styling, and visibility control) and expanded editing support to handle boolean properties.
- Added per-script Luau environments (optional `envIndex`) and per-function globals, with updated native/WASM bindings and APIs to support metatable/fenv operations.
- Updated the web Luau runtime asset hosting path to use versioned artifacts (`.../luau/0.15.0/`).

## [0.14.0]
- Breaking change: `AgentsClient.ask` now accepts optional attachment bytes and returns a `Response` (`TextResponse`/`JsonResponse`) instead of a raw `Map`
- Agent descriptions now surface `annotations` metadata for capability hints (e.g., attachment format)
- Breaking change: `MeshDocument.encode()` now returns raw JSON instead of base64-encoded JSON
- Luau/Flutter widgets can now create tar attachments from in-app file picks and pass them through `agents.ask`, plus expose a `LuauConsoleScope` for console output
- Improved Luau error/console reporting (script/line metadata) and added a `Uint8List` → Luau buffer convenience conversion

## [0.13.0]
- Added support for sending binary attachments when invoking agent tools from the Dart client API
- Breaking change: updated the Luau scripting surface from method-style calls and a `room` module to function-style calls and an `agents` module (e.g., `agents.ask`, `agents.invokeTool`, `log.info`)
- Improved Luau table support across native/FFI/web bindings (create/set/get operations) for richer interop with Dart maps and tables
- Improved Luau runtime documentation generation to list module functions distinctly from methods
- Added/expanded Luau unit tests covering table behaviors

## [0.12.0]
- Add `schema` and `initialJson` options to `SyncClient.open`, and include them in `room.connect` requests to support document bootstrapping on first connect
- Add `MeshDocument.encode()` to serialize schema + initial JSON for sharing/transport
- Add Luau `Buffer` and callback-function reference support across native (FFI) and web (WASM) runtimes, including safe copy-in/copy-out APIs
- Breaking change: Luau `ui:pickFiles` now uses a callback function and returns buffers rather than base64 strings
- Breaking change: Luau `room:ask` signature changed to accept arguments and a callback
- Add image widget support for setting image content from an in-memory buffer, plus small UI sizing/layout improvements
- Update `shadcn_ui` to `^0.42.0` across Flutter packages and add `image_picker` `^1.0.7` to enable media picking in the chat UI
- Add a minimal Flutter example app demonstrating room connection

## [0.11.0]
- Stability

## [0.10.1]
- Stability

## [0.10.0]
- Stability

## [0.9.3]
- Stability

## [0.9.2]
- Stability

## [0.9.1]
- Stability

## [0.9.0]
- Stability

## [0.8.4]
- Stability

## [0.8.3]
- Stability

## [0.8.2]
- Stability

## [0.8.1]
- Stability

## [0.8.0]
- Stability

## [0.7.1]
- Stability
