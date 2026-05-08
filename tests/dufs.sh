#!/usr/bin/env bash
# Tests for the dufs snap.
#
# dufs is a utility file server supporting static serving, uploads, WebDAV, etc.
# Usage: dufs [OPTIONS] [serving-path]
#
# Override these via environment variables if the skill produces different values:
#   DUFS_PORT  - port to bind during tests (default: 18081)

DUFS_PORT="${DUFS_PORT:-18081}"

run_tests() {
    local snap_file="$1"
    local snap_name
    snap_name=$(snap_name_from_meta "$snap_file")

    header "dufs"

    install_snap "$snap_file" || return 1

    # Use $HOME for the temp dir — dufs runs with strict confinement + home plug
    # and cannot access /tmp on the host system.
    local tmp_dir
    tmp_dir=$(mktemp -d "$HOME/dufs-test-XXXXXX")
    echo "Hello from dufs snap test" > "$tmp_dir/test.txt"

    local server_pid=""

    cleanup() {
        [[ -n "$server_pid" ]] && kill "$server_pid" 2>/dev/null || true
        rm -rf "$tmp_dir"
        remove_snap "$snap_name"
    }
    trap cleanup RETURN

    info "Starting dufs on port $DUFS_PORT..."
    "$snap_name" --port "$DUFS_PORT" --allow-upload "$tmp_dir" &>/dev/null &
    server_pid=$!

    if ! wait_for_port "$DUFS_PORT" 10; then
        fail "server did not start within 10 seconds"
        return
    fi

    assert_http_status "root path returns HTTP 200" \
        "200" "http://127.0.0.1:${DUFS_PORT}/"

    assert_http_body_contains "directory listing shows test file" \
        "test\.txt" "http://127.0.0.1:${DUFS_PORT}/"

    assert_http_status "static file returns HTTP 200" \
        "200" "http://127.0.0.1:${DUFS_PORT}/test.txt"

    assert_http_body_contains "static file has correct content" \
        "Hello from dufs snap test" "http://127.0.0.1:${DUFS_PORT}/test.txt"

    assert_http_status "missing file returns HTTP 404" \
        "404" "http://127.0.0.1:${DUFS_PORT}/nonexistent.txt"

    # Test upload via PUT (dufs supports this by default)
    info "Testing file upload..."
    local upload_status
    upload_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
        -X PUT "http://127.0.0.1:${DUFS_PORT}/uploaded.txt" \
        --data "Uploaded content" 2>/dev/null)
    if [[ "$upload_status" == "201" || "$upload_status" == "204" ]]; then
        pass "file upload returns HTTP $upload_status"
        assert_http_body_contains "uploaded file is retrievable" \
            "Uploaded content" "http://127.0.0.1:${DUFS_PORT}/uploaded.txt"
    else
        fail "file upload returned HTTP $upload_status (expected 201 or 204)"
    fi
}
