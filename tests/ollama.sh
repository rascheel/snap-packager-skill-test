#!/usr/bin/env bash
# Tests for the ollama snap.
#
# ollama bundles and runs large language models. A full model inference test
# is impractical in CI, so these tests verify:
#   1. The binary is functional and reports a version.
#   2. The server starts and responds to its health endpoint.
#
# Override these via environment variables:
#   OLLAMA_PORT  - API port ollama listens on (default: 11434)
#   OLLAMA_SVC   - snap service name if packaged as a daemon (default: ollama)

OLLAMA_PORT="${OLLAMA_PORT:-11434}"
OLLAMA_SVC="${OLLAMA_SVC:-ollama}"

run_tests() {
    local snap_file="$1"
    local snap_name
    snap_name=$(snap_name_from_meta "$snap_file")

    header "ollama"

    install_snap "$snap_file" || return 1

    local server_pid=""

    cleanup() {
        [[ -n "$server_pid" ]] && kill "$server_pid" 2>/dev/null || true
        remove_snap "$snap_name"
    }
    trap cleanup RETURN

    assert_output_matches \
        "--version prints version string" \
        "[0-9]+\.[0-9]+" \
        "$snap_name" --version

    # Check if this is a daemon snap (auto-started) or a CLI app
    local svc_state
    svc_state=$(snap services "${snap_name}.${OLLAMA_SVC}" 2>/dev/null \
                | awk 'NR>1 {print $3}' | head -1)

    if [[ -z "$svc_state" ]]; then
        # Not a daemon snap — start the server manually
        info "Starting ollama server on port $OLLAMA_PORT..."
        OLLAMA_HOST="127.0.0.1:${OLLAMA_PORT}" "$snap_name" serve &>/dev/null &
        server_pid=$!
    else
        info "ollama packaged as daemon (state: $svc_state)"
        assert_snap_service "ollama daemon is active" "$snap_name" "$OLLAMA_SVC" "active"
    fi

    if wait_for_port "$OLLAMA_PORT" 15; then
        pass "ollama is listening on port $OLLAMA_PORT"
    else
        fail "ollama server did not start within 15 seconds"
        return
    fi

    assert_http_status "health endpoint returns HTTP 200" \
        "200" "http://127.0.0.1:${OLLAMA_PORT}/"

    # The /api/tags endpoint lists available models (should return valid JSON)
    local tags_status
    tags_status=$(http_status "http://127.0.0.1:${OLLAMA_PORT}/api/tags")
    if [[ "$tags_status" == "200" ]]; then
        pass "API /api/tags returns HTTP 200"
        assert_http_body_contains "API response is JSON" \
            '"models"' "http://127.0.0.1:${OLLAMA_PORT}/api/tags"
    else
        skip "API /api/tags returned HTTP $tags_status (may need interface connections)"
    fi
}
