#!/usr/bin/env bash
# Tests for the darkhttpd snap.
#
# darkhttpd is a simple single-binary HTTP server.
# Usage: darkhttpd <rootdir> [--port PORT]
#
# Override these via environment variables if the skill produces different values:
#   DARKHTTPD_PORT  - port to bind during tests (default: 18080)

DARKHTTPD_PORT="${DARKHTTPD_PORT:-18080}"

run_tests() {
    local snap_file="$1"
    local snap_name
    snap_name=$(snap_name_from_meta "$snap_file")

    header "darkhttpd"

    install_snap "$snap_file" || return 1

    # Use $HOME for the temp dir — darkhttpd runs with strict confinement + home plug
    # and cannot access /tmp on the host system.
    local tmp_dir
    tmp_dir=$(mktemp -d "$HOME/darkhttpd-test-XXXXXX")
    echo "Hello from darkhttpd snap test" > "$tmp_dir/test.txt"

    local server_pid=""

    # Cleanup on exit
    cleanup() {
        [[ -n "$server_pid" ]] && kill "$server_pid" 2>/dev/null || true
        rm -rf "$tmp_dir"
        remove_snap "$snap_name"
    }
    trap cleanup RETURN

    # Start the server in the background
    info "Starting darkhttpd on port $DARKHTTPD_PORT..."
    "$snap_name" "$tmp_dir" --port "$DARKHTTPD_PORT" &>/dev/null &
    server_pid=$!

    if ! wait_for_port "$DARKHTTPD_PORT" 10; then
        fail "server did not start within 10 seconds"
        return
    fi

    assert_http_status "root directory listing returns HTTP 200" \
        "200" "http://127.0.0.1:${DARKHTTPD_PORT}/"

    assert_http_body_contains "directory listing shows test file" \
        "test\.txt" "http://127.0.0.1:${DARKHTTPD_PORT}/"

    assert_http_status "static file returns HTTP 200" \
        "200" "http://127.0.0.1:${DARKHTTPD_PORT}/test.txt"

    assert_http_body_contains "static file has correct content" \
        "Hello from darkhttpd snap test" "http://127.0.0.1:${DARKHTTPD_PORT}/test.txt"

    assert_http_status "missing file returns HTTP 404" \
        "404" "http://127.0.0.1:${DARKHTTPD_PORT}/nonexistent.txt"
}
