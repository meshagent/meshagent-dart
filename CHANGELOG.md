## [0.44.1]
- Stability

## [0.44.0]
- Added thread watch/unwatch messages plus multiple thread-storage support to the Dart agent client API.
- Chat session state now preserves created timestamps and resets replay state correctly when reopening threads, improving message ordering and pending-input handling.
- Updated agent message modeling to carry richer thread metadata for live assistant, mail, and storage-aware workflows.

## [0.43.4]
- `AgentMessage` now serializes `created_at` and restores it from incoming payloads so Dart agents keep message timestamps across round trips.
- `AgentMessageEvent` now carries its own timestamp, supports listeners, and keeps merged payloads aligned with the original event time.
- `MessagingChatClient` now routes participantless thread lifecycle updates and preserves room message timestamps when turning messages into session events.
- UI helpers now support an injectable reference time for relative labels, show seconds for recent timestamps, and expose more resilient dataset row timestamp resolution.

## [0.43.3]
- Stability

## [0.43.2]
- Added optional backend fields throughout `meshagent-agents-dart` messages and chat session methods, enabling multi-backend conversations and model changes.
- Added IAP-aware websocket helpers in `meshagent-api`, including `WebSocketClientProtocol.withIAP()` and Authorization-header based room connections instead of token query parameters.
- Breaking: websocket room auth now uses `meshagent-agent.<token>` instead of `bearer.<token>`.
- Expanded `meshagent_flutter_desktop_updater` with update-check dialog, controller-scope, and menu-copy exports for desktop apps.

## [0.43.1]
- Added IAP room websocket support to the Dart agent chat client.
- Reworked the Flutter chat and thread components to load thread lists through `MessagingChatClient` and `AgentThreadStorageRepository` instead of direct document mutation.
- Added the desktop update bridge APIs used by Flutter apps for update checks on macOS and Windows.

## [0.43.0]
- Room websocket clients now support IAP connections through `withIAP()` helpers, nullable tokens, and the new auth flow that avoids query-string token handling.
- Agent and chat payloads now carry backend metadata through thread starts, turn starts, model changes, and realtime audio commits.
- The shared Dart UI/tooling packages now understand backend-aware model lists, unified diff previews, and Codex diff tool calls, and the desktop updater exports reusable dialog and scope helpers.

## [0.42.2]
- Added container and build model fields for image IDs, runtime stats, exit status details, and published build image metadata.
- Added `waitForExitStatus` alongside `waitForExit`, preserving the existing exit-code convenience while exposing richer exit information.
- Updated container list parsing to consume the new metadata fields in responses without breaking existing callers.

## [0.42.1]
- Stability

## [0.42.0]
- Added project lookup by key.
- Container and room APIs now model ports as structured `containerPort`/`hostPort` pairs, which is a breaking response-shape change for container listings.
- `RoutePath` and `PortSpec` now support `stripPrefix` and `hostPort`, and room service MCP URL resolution uses `hostPort` when present.
- Room creation now serializes permissions correctly and preserves annotations.
- Container creation now accepts a `template` option.

## [0.41.10]
- Stability

## [0.41.9]
- Stability

## [0.41.8]
- Stability

## [0.41.7]
- Stability

## [0.41.6]
- Extended the Dart storage client `downloadUrl` API with an optional `download` flag for inline versus attachment links.

## [0.41.5]
- Stability

## [0.41.4]
- Stability

## [0.41.3]
- Stability

## [0.41.2]
- The Dart backend-agent sample now exposes a hosted local toolkit with `ping`, `status`, and `echo`, verifies the toolkit through room tool calls, and persists a small proof payload once validation succeeds.

## [0.41.1]
- Dart feed subscription models and create/update methods now carry an optional `filenameDatetimeFormat` through the client.

## [0.41.0]
- Route APIs now use `RouteSpec`, support room or agent backends, and still parse legacy route payloads.
- Managed-agent chat/session APIs now support thread listing, thread lifecycle events, and attachment names.
- `AgentsClient.invoke` no longer accepts `callerContext`, and `ToolStreamOutput` now carries `inputClosed`.
- Toolkit metadata serialization no longer includes `thumbnailUrl` or `pricing`.
- The SDK's Dart bridge packages were refreshed to align the generated models and interop helpers with the new route and managed-agent shapes.

## [0.40.3]
- Added `meshagent-agents-dart`, a websocket-backed agent chat package with rich agent message types, thread storage, and pending-input/session management.
- Expanded the core Dart client with route-spec CRUD/listing, agent sessions, managed-agent secret APIs, and agent route queries.
- Added the reusable Flutter desktop updater package.
- Added third-party dependencies `msgpack_dart ^1.0.1`, `uuid ^4.5.1`, and `web_socket_channel ^3.0.3`.

## [0.40.2]
- Adjusted chat input trailing controls so they render directly when no footer is present, preserving the expected layout without the extra expansion wrapper.

## [0.40.1]
- Stability

## [0.40.0]
- Added a platform-specific websocket connector so the Dart SDK uses native I/O websocket handling where available.
- Extended the Dart protocol and room-server client to cover the updated realtime flow, including audio/WAV content support.
- Refreshed Dart Arrow helpers and protocol tests to match the revised thread and event schema.

## [0.39.9]
- Updated Dart SDK chat components to omit context rendering when no context is available.
- Added dataset table rename support to Dart dataset/chat flows.
- Improved dataset path restoration support in Dart dataset chat threads.
- Added dataset thread storage support to Dart SDK chat/dataset wiring.
- Enhanced Dart SDK usage graph/reporting UI for hour-level usage breakdown and additional usage reports.

## [0.39.8]
- Added `renameTable` to `DatasetsClient`, invoking the server `rename_table` operation with `name`, `newName`, optional `namespace`, and optional `branch`

## [0.39.7]
- Added `getSysadminUsage` to the Dart SDK client to fetch sysadmin usage reports with filters (start/end, interval, report, project/provider/model/usage type/client, and annotations).
- Added a Dart test validating request query parameters and the parsed response shape.
- Updated the Dart SDK package dependency alignment (including `meshagent_dart_arrow`) to the new SDK version.

## [0.39.6]
- `FileDropArea` now supports an optional `multiple` parameter to stop after the first dropped file when set to `false`.
- Table cell alignment rendering no longer treats boolean values as a special-case alignment path.
- File browser selection behavior was updated (clears previous selection before adding a new one, and centers the layout vertically).

## [0.39.5]
- Extended table status to track `loadedByteCount` and include formatted byte counts in the loading/secondary status labels

## [0.39.4]
- Breaking: Dart scheduled-task client models and requests now use `ScheduledTaskSpec`-based structures (queue vs container targeting) instead of separate payload/queue/schedule fields.
- Added Dart scheduled task run models and run-page support so consumers can list scheduled-task executions with status, attempt count, and timestamp fields.
- Updated Dart scheduled-task serialization to align with the server contract (including required `roomId` handling).
- Code editor integration updated to the new `code_forge` / `code_forge_web`-based editor widgets, including platform-specific selection.
- Terminal UI updated with a shared themed terminal view wrapper for consistent font/cursor/padding behavior.
- Dependency updates in the Dart SDK packages: `shadcn_ui` bumped to `^0.54.0`, `web` bumped to `^1.1.1`, `code_forge` added as `^9.9.0`, `code_forge_web` added as `^2.4.0`, and `re_editor` removed.

## [0.39.3]
- Added `UsageGraph`/`UsageGraphPoint` to the Flutter Shadcn package for interval-based usage visualization (including periodStart-aware hover labeling and reference/average calculations).
- Updated the Shadcn data grid clipboard behavior to better support single-cell selection (more direct clipboard writes and raw value handling).
- Dart client now supports paginated “page” models for repositories, project secrets (plus legacy secret paging), services (including room-scoped services), API keys, and webhooks, with `count`/`offset` inputs and `total` outputs.
- Dart client list parsing is more robust (typed map casting and safer handling of `total`/list fields from API responses).
- Exported the new usage graph components from the Flutter Shadcn SDK entrypoint.

## [0.39.2]
- Updated Dart/Flutter SDK package versions and internal dependency constraints to `0.39.1` (from `0.39.0`) across the `meshagent` Flutter-related packages (e.g. `meshagent_flutter`, `meshagent_flutter_auth`, `meshagent_flutter_shadcn`, `meshagent_super_editor`, `meshagent_flutter_dev`, and related SDK packages).

## [0.39.1]
- Added paged response model types (e.g., `MailboxesPage`, `RoutesPage`, `FeedsPage`, `ScheduledTasksPage`, plus related paging models for users/rooms/grants/OAuth clients).
- Added `Meshagent` Dart client methods for paged listing (e.g., `listMailboxesPage`, `listRoutesPage`, `listFeedsPage`, `listRoomsPage`, `listRoomGrantsByUserPage`, `listUniqueUsersWithGrantsPage`, `listOAuthClientsPage`, `listScheduledTasksPage`) with `count`/`offset`/`filter` support and `total`.
- Updated existing Dart list methods to route through paging and accept `count`/`offset`/`filter` options, with default page-size behavior updated (default page size changed from the prior smaller default behavior).

## [0.39.0]
- Added expanded dataset index management support to the Dart datasets client, including index configuration/remapping and richer index metadata.
- Added dataset SQL cancellation support to Dart datasets client operations, including typed cancel status/results.
- Applied “database” -> “datasets” terminology and API/tooling updates across Dart clients (breaking for prior database-named usage).
- Updated Dart clients to support improved usage/cost reporting plumbing (usage export/annotations) and enhanced LLM proxy “pipes” plus custom LLM usage tracking.
- Added/updated the Dart Arrow package for Arrow body compression with VM/web support and interop coverage.
- Updated Dart SDK pricing-related surfaces to include gpt-5.5 model release pricing.

## [0.38.4]
- Added `delete({projectId, path})` to the Dart `Meshagent` client for project storage deletion (`/projects/:project_id/storage/delete`), throwing `NotFoundException` on 404.

## [0.38.3]
- Breaking: `ContainerImage` now exposes `references`/`preferredRef` plus timestamps/media type instead of `tags`/`size`, and `inspectImage` returns manifests/layers with content size.
- Meshagent client adds `canUseLlmProxy` and current-user LLM proxy usage, plus usage filters (users/room/provider/model/usage type).
- Participant models now emit change notifications on attribute and online status updates for reactive UI binding.
- Flutter dev containers UI adds image inspection sheets and updated summary columns (reference and updated time).
- Flutter shadcn adds email parsing with multi-select autocomplete/select-users dialog, and thread list views now react to participant changes.

## [0.38.2]
- RoomContainer now includes a `ports` list parsed from server responses.
- Flutter dev container table displays container ports using the updated container model.

## [0.38.1]
- Breaking: `updateUser` now requires `canUseLlmProxy`, and user-management calls accept the new permission flag.
- Flutter meeting connections now enable camera and microphone in parallel to improve join behavior and keep pending media state accurate.
- Dart examples were refreshed to use the `websocketProtocol` helper for room connections, add `SimpleValue` types and richer element descriptions in schema examples, and remove the schema-registry example.

## [0.38.0]
- Added `llm_proxy` to the full OAuth scope set.
- Breaking: `LoginScope` now defaults to the full OAuth scope rather than `profile` only.

## [0.37.2]
- Stability

## [0.37.1]
- Meeting controls now detect camera and microphone availability, track unavailable state, and reflect it in toggle styling and device settings.
- Added shared theme colors (custom green and foreground) and exported them from the Flutter package.
- Voice transcript paths now use human-friendly local timestamp filenames with helpers to format legacy transcript names.
- Transcript viewer now shows a header with date/time/duration, participant avatars, and per-segment timecodes using participant roles.
- Breaking: `TranscriptSegment` now requires a transcript start time parameter to render timecodes.

## [0.37.0]
- Breaking: Datasets client now supports `json`, `uuid`, `list`, and `struct` types with typed wrappers (DatasetJson/DatasetStruct/DatasetExpression/DatasetDate/UuidValue); list/struct values must be wrapped and SQL params use the new encoding.
- Breaking: Containers build now streams build contexts (start/data chunks) with `mountPath`/`chunks` and removes `startBuild`.
- Breaking: Toolkit/hosting refactor replaces RemoteToolkit with HostedToolkit/startHostedToolkit, removes ToolkitConfig and `supports_context`, and introduces room-bound toolkits with validationMode.
- Added MCP connector discovery helpers and chat UI capability negotiation (tool-choice and MCP selection) in Flutter Shadcn components.
- Participant tokens now support LLM grants, preserve extra payload fields, and ApiScope defaults include LLM.

## [0.36.3]
- Storage client now supports move operations and emits file moved events.
- Secrets client now supports existence checks.
- Project user add calls now omit permission fields unless explicitly set.
- Flutter shadcn file preview now loads markdown/PDF/code directly from room storage and surfaces download URL errors.

## [0.36.2]
- Breaking: Removed share-connect API from the Dart client (`connectShare` / RoomShareConnectionInfo).
- Added full OAuth scope constants and exported them from the main `meshagent` library.
- Auth defaults changed to `profile`; the Dart client now raises `ForbiddenException` on 403 profile access and Flutter auth signs out/restarts login (sign-out clears cached user).

## [0.36.1]
- File preview/viewer now recognizes `.thread` files as chat threads and renders them with the thread viewer rather than custom viewers.

## [0.36.0]
- Added room registry APIs and Flutter developer console UI for listing, retagging, and deleting registry images.
- Dart service models now include config mounts and agent email/heartbeat settings with typed prompt content.
- Breaking: container API key provisioning was removed from Dart container specs.
- Service template container mounts now round-trip project, image, file, empty-dir, and config mounts.
- Flutter chat threads now keep attachment-only messages visible and filter unsupported event kinds consistently.
- Service template editor now defaults enum variables to valid values and normalizes invalid selections.
- Added `visibility_detector` ^0.4.0+2 as a Flutter Shadcn dev dependency.

## [0.35.8]
- Live trace viewer and developer console now support trace search filtering across span metadata while preserving parent/child context.
- File preview components now reload code from room/url/text with error handling, load PDFs from room storage, improve image loading/error states, and recognize plaintext files as code.
- Context menus can optionally center within boundaries and refresh anchors on viewport changes.
- Dart SDK examples updated to use storage upload and decode bytes, with cleanup of empty example stubs.

## [0.35.7]
- Added container build lifecycle support in the Dart SDK (start/build returning `build_id`, list/cancel/delete builds, build logs, image load) plus exec stderr streaming and stricter status decoding.
- Breaking: container build APIs now return build IDs and BuildInfo fields changed; container stop defaults to non-forced.
- Added storage upgrades: `stat`, upload MIME-type inference, storage entries now include created/updated timestamps, and stricter download metadata validation.
- Added secrets client enhancements: async OAuth/secret request handlers, optional client ID, flexible get/set secret by id/type/name, and requestOAuthToken returns null when no token is provided.
- Added database version metadata (TableVersion now includes metadata) and improved where-clause encoding.
- Added RoomClient helpers to inspect participant tokens and API grants.
- Breaking: messaging stream APIs removed (stream callbacks and MessageStream types); use streaming toolkits instead.

## [0.35.6]
- Dart StorageClient now honors server-provided `chunk_size` pull headers when streaming uploads.
- Flutter developer tools now sort containers by name/image/starter for stable ordering, and the trace viewer deduplicates span updates with improved timeline layout and timestamp formatting.
- New coordinated context-menu system adds adaptive anchoring and shared controller coordination across chat, attachments, and file previews.
- Chat UI refinements improve reaction/attachment menus, action visibility timing, and context-menu boundaries for cleaner interactions.
- Meeting controls are redesigned with pending mic/camera states, error toasts, responsive layouts, and a unified device settings dialog.
- Participant tiles now use camera publications and updated overlays, while voice agent calling adds start-session error handling and responsive waveform/controls.

## [0.35.5]
- Chat threads now keep a dedicated scroll controller and auto-scroll to the latest message after send.
- Chat bubble context menus now coordinate a single active menu and close on outside taps, with improved controller cleanup.

## [0.35.4]
- Stability

## [0.35.3]
- Stability

## [0.35.2]
- Stability

## [0.35.1]
- Flutter dev tooling now provides a mount-aware terminal launch dialog for image/container sessions (room/image mounts) and integrates it into the developer console, with improved image list sorting/labels.
- Flutter ShadCN attachment previews now key by file path and surface upload failures with toast + destructive styling.

## [0.35.0]
- Managed secret APIs were added with project/room CRUD, base64 payloads, managed secret models, and external OAuth registration CRUD for project and room scopes.
- Meshagent client now accepts an optional custom HTTP client, and legacy secret helpers now wrap the managed secret APIs.
- Room memory client now provides typed models and operations for inspect/query/upsert/ingest/recall/delete/optimize, including decoding of row-based results and binary values.
- Breaking: chat thread widgets now support toggling completed tool-call events, and `ChatThreadMessages` requires a `showCompletedToolCalls` flag (with `initialShowCompletedToolCalls` on `ChatThread`).

## [0.34.0]
- WebSocket protocol now surfaces close codes/reasons via a dedicated exception, and RoomServerException includes a retryable flag for Try-Again-Later closes.
- RoomConnectionScope adds retry/backoff for retryable connection errors, supports custom RoomClient factories, and exposes a retrying builder.
- Web runtime entrypoint injection is idempotent to avoid duplicate script loads.
- Shadcn chat widgets now allow cross-room file attachments/importing and sorted file browsing, with agent-aware input placeholders.
- Shadcn chat/event rendering filters completed tool-call noise, adds empty-state customization and visibility hooks, and refines empty states for transcript and voice views.

## [0.33.3]
- Stability

## [0.33.2]
- Stability

## [0.33.1]
- Stability

## [0.33.0]
- Stability

## [0.32.0]
- Stability

## [0.31.4]
- Stability

## [0.31.3]
- Stability

## [0.31.2]
- Stability

## [0.31.1]
- Stability

## [0.31.0]
- Stability

## [0.30.1]
- Stability

## [0.30.0]
- Breaking: tool invocation moved to toolkit-based `room.invoke` with `room.*` tool-call events and streaming tool-call chunks.
- Added containers and services clients to the Dart RoomClient, with container exec/log streaming and service list/restart support.
- Storage and database clients now support streaming upload/download and streaming query/insert/search with chunked inputs; Sync client uses streaming open/update.
- Dependency update: added `async ^2.13.0`.

## [0.29.4]
- Stability

## [0.29.3]
- Stability

## [0.29.2]
- Stability

## [0.29.1]
- Stability

## [0.29.0]
- Stability

## [0.28.16]
- Stability

## [0.28.15]
- Stability

## [0.28.14]
- Stability

## [0.28.13]
- Stability

## [0.28.12]
- Stability

## [0.28.11]
- Stability

## [0.28.10]
- Stability

## [0.28.9]
- Stability

## [0.28.8]
- Stability

## [0.28.7]
- Stability

## [0.28.6]
- Stability

## [0.28.5]
- Stability

## [0.28.4]
- Stability

## [0.28.3]
- Stability

## [0.28.2]
- Stability

## [0.28.1]
- Stability

## [0.28.0]
- BREAKING: ToolOutput was renamed to ToolCallOutput, ContentTool.execute now returns ToolCallOutput, and AgentsClient.toolCallResponseContents was removed.
- Tool-call streaming now uses ControlContent close status codes/messages with RoomServerException.statusCode; InvalidToolDataException signals validation failures and closes streams with status 1007.
- Flutter chat UI now reads thread status text/mode attributes, supports steerable threads (sends "steer" messages), and exposes cancel while processing.

## [0.28.0]
- Stability

## [0.27.2]
- Stability

## [0.27.1]
- Stability

## [0.27.0]
- Added `Route` support to the Dart client, including create/update/get/list/delete APIs for project and room routes.
- Added mailbox annotations to Dart mailbox models and mailbox create/update API payloads.
- Added endpoint/port annotation support in Dart service spec models for routing/request metadata round-tripping.
- Added secret-backed environment variable modeling in Dart service specs via `SecretValue` and `EnvironmentVariable.secret`.
- Added structured event and approval handling support in Flutter chat components, including thread status attribute integration.
- Added git credentials helper fallback to room secrets for username/password using configurable secret IDs.
- Breaking change: Dart `Mailbox` construction now requires `annotations`.

## [0.26.0]
- Stability

## [0.25.9]
- Stability

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
- Breaking change: `AgentsClient.ask` now accepts optional attachment bytes and returns a `Response` (`TextChunk`/`JsonChunk`) instead of a raw `Map`
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
