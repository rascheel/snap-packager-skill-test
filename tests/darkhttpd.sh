#!/usr/bin/env bash
# Tests for the darkhttpd snap.
#
# darkhttpd is a simple single-binary HTTP server.
# Usage: darkhttpd <rootdir> [--port PORT]
#
# The tests exercise upstream's documented usage: a command run on a directory of
# the user's choosing. A snap that only ships darkhttpd as a daemon exposes no
# command in /snap/bin and fails the first check.
#
# Override these via environment variables if the skill produces different values:
#   DARKHTTPD_PORT  - port to bind during tests (default: 18080)
#   DARKHTTPD_CMD   - snap command name for the darkhttpd app (default: darkhttpd)

DARKHTTPD_PORT="${DARKHTTPD_PORT:-18080}"
DARKHTTPD_CMD="${DARKHTTPD_CMD:-darkhttpd}"

run_tests() {
    local snap_file="$1"
    local snap_name
    snap_name=$(snap_name_from_meta "$snap_file")

    header "darkhttpd"

    install_snap "$snap_file" || return 1

    # Use $HOME for the temp dir — darkhttpd runs with strict confinement + home plug
    # and cannot access /tmp on the host system.
    local tmp_dir server_log
    tmp_dir=$(mktemp -d "$HOME/darkhttpd-test-XXXXXX")
    echo "Hello from darkhttpd snap test" > "$tmp_dir/test.txt"
    # The redirect is done by this (unconfined) shell, so the log can live in /tmp.
    server_log=$(mktemp /tmp/darkhttpd-test-log-XXXXXX)

    local server_pid=""

    # Cleanup on exit
    cleanup() {
        [[ -n "$server_pid" ]] && kill "$server_pid" 2>/dev/null || true
        rm -rf "$tmp_dir" "$server_log"
        remove_snap "$snap_name"
    }
    trap cleanup RETURN

    # Snap commands are exposed as '<snap-name>.<app-name>' when the app name
    # differs from the snap name. Daemon-only apps get no command at all.
    local cmd
    if command -v "$DARKHTTPD_CMD" &>/dev/null; then
        cmd="$DARKHTTPD_CMD"
    elif command -v "${snap_name}.${DARKHTTPD_CMD}" &>/dev/null; then
        cmd="${snap_name}.${DARKHTTPD_CMD}"
    else
        fail "snap exposes no '$DARKHTTPD_CMD' command (is darkhttpd packaged only as a daemon?)"
        return
    fi

    # Start the server in the background
    info "Starting $cmd on port $DARKHTTPD_PORT..."
    "$cmd" "$tmp_dir" --port "$DARKHTTPD_PORT" >"$server_log" 2>&1 &
    server_pid=$!

    if ! wait_for_port "$DARKHTTPD_PORT" 10; then
        if kill -0 "$server_pid" 2>/dev/null; then
            fail "server did not start within 10 seconds"
        else
            fail "server exited before listening on port $DARKHTTPD_PORT"
        fi
        tail -n 10 "$server_log" | sed 's/^/    /'
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
