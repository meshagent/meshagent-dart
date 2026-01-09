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
