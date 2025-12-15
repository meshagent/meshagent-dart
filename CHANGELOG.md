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
