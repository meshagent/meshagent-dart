#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUP_SERVER=true
TEST_ARGS=()

for arg in "$@"; do
    case "$arg" in
        --skip-server-setup) SETUP_SERVER=false ;;
        *) TEST_ARGS+=("$arg") ;;
    esac
done

if $SETUP_SERVER; then
    if ! command -v cargo >/dev/null 2>&1; then
        echo "cargo must be available when running meshagent-dart tests with server setup enabled." >&2
        exit 1
    fi

    ROOM_INTERNAL_API_PORT="${ROOM_INTERNAL_API_PORT:-8078}"

    export MESHAGENT_API_URL="http://localhost:${ROOM_INTERNAL_API_PORT}"
    export MESHAGENT_SECRET="test-secret-secure-secret-sample2560binarykey"
    export MESHAGENT_PROJECT_ID="testproject"
    export MESHAGENT_KEY_ID="test-key-secure-key-sample2560binarykey"
    SERVER_STORAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/meshagent-dart-room-server.XXXXXX")"
    export MESHAGENT_SERVER_CLI_FILES_STORAGE_PATH="$SERVER_STORAGE_DIR"
    unset MESHAGENT_API_KEY

    cargo run --manifest-path "$ROOT_DIR/rust/Cargo.toml" -p room-server-cli &
    CLI_PID=$!
    trap 'kill $CLI_PID 2>/dev/null || true; rm -rf "$SERVER_STORAGE_DIR"' EXIT

    SERVER_READY=false
    for _ in $(seq 1 180); do
        if curl -fsS "$MESHAGENT_API_URL/" >/dev/null; then
            SERVER_READY=true
            break
        fi

        if ! kill -0 $CLI_PID 2>/dev/null; then
            wait $CLI_PID
            echo "MeshAgent test server exited during startup." >&2
            exit 1
        fi

        sleep 0.5
    done

    if ! $SERVER_READY; then
        echo "MeshAgent test server did not become ready at $MESHAGENT_API_URL." >&2
        exit 1
    fi
fi

cd "$ROOT_DIR"
if ! compgen -G "$ROOT_DIR/.dart_tool/pub/bin/test/test.dart-*.snapshot" >/dev/null; then
    dart pub get
fi
TEST_SNAPSHOT="$(find "$ROOT_DIR/.dart_tool/pub/bin/test" -name 'test.dart-*.snapshot' | sort | tail -n 1)"

if [ ${#TEST_ARGS[@]} -eq 0 ]; then
    dart "$TEST_SNAPSHOT" meshagent-sdk/meshagent-dart/test
else
    RESOLVED_TEST_ARGS=()
    for arg in "${TEST_ARGS[@]}"; do
        if [[ "$arg" == *_test.dart && "$arg" != */* ]]; then
            RESOLVED_TEST_ARGS+=("meshagent-sdk/meshagent-dart/test/$arg")
        else
            RESOLVED_TEST_ARGS+=("$arg")
        fi
    done
    dart "$TEST_SNAPSHOT" "${RESOLVED_TEST_ARGS[@]}"
fi
