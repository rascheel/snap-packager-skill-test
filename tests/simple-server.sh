#!/usr/bin/env bash
# Tests for the simple-server snap.
#
# simple-server is a daemon that uses ncat to serve a configurable message
# over TCP. Configuration is managed via snap config keys:
#   daemon.host  - bind address (default: 127.0.0.1)
#   daemon.port  - TCP port     (default: 18083)
#   daemon.msg   - message text (default: "Hello from simple-server!")
#
# Override these via environment variables:
#   SIMPLE_SERVER_PORT  - port to use during tests (default: 18083)
#   SIMPLE_SERVER_SVC   - snap service name (default: simple-server)
#   SIMPLE_SERVER_MSG   - expected message text

SIMPLE_SERVER_PORT="${SIMPLE_SERVER_PORT:-18083}"
SIMPLE_SERVER_SVC="${SIMPLE_SERVER_SVC:-simple-server}"
SIMPLE_SERVER_MSG="${SIMPLE_SERVER_MSG:-Hello from simple-server!}"

run_tests() {
    local snap_file="$1"
    local snap_name
    snap_name=$(snap_name_from_meta "$snap_file")

    header "simple-server"

    install_snap "$snap_file" || return 1

    cleanup() { remove_snap "$snap_name"; }
    trap cleanup RETURN

    # Apply snap config so the server binds to our chosen port/address/message.
    info "Configuring snap (port=$SIMPLE_SERVER_PORT, msg='$SIMPLE_SERVER_MSG')..."
    sudo snap set "$snap_name" \
        daemon.host=127.0.0.1 \
        daemon.port="$SIMPLE_SERVER_PORT" \
        daemon.msg="$SIMPLE_SERVER_MSG"

    # Restart the service so the new config takes effect.
    sudo snap restart "${snap_name}.${SIMPLE_SERVER_SVC}" 2>&1 | sed 's/^/    /' || true

    assert_snap_service \
        "simple-server daemon is active" \
        "$snap_name" "$SIMPLE_SERVER_SVC" "active"

    info "Waiting for simple-server to listen on port $SIMPLE_SERVER_PORT..."
    if ! wait_for_port "$SIMPLE_SERVER_PORT" 15; then
        fail "simple-server did not listen on port $SIMPLE_SERVER_PORT within 15 seconds"
        return
    fi
    pass "simple-server is listening on port $SIMPLE_SERVER_PORT"

    # Read the message via netcat (ncat or nc).
    local nc_cmd
    if command -v ncat &>/dev/null; then
        nc_cmd="ncat"
    elif command -v nc &>/dev/null; then
        nc_cmd="nc"
    else
        skip "cannot test TCP response: ncat/nc not found on host"
        return
    fi

    local response
    response=$(timeout 5 "$nc_cmd" 127.0.0.1 "$SIMPLE_SERVER_PORT" 2>/dev/null || true)

    if echo "$response" | grep -qF "$SIMPLE_SERVER_MSG"; then
        pass "TCP response contains configured message"
    else
        fail "TCP response did not contain '$SIMPLE_SERVER_MSG' (got: $(echo "$response" | head -1))"
    fi

    # Reconfigure with a different message and verify the change is reflected.
    local new_msg="Updated snap config message"
    info "Updating message to '$new_msg'..."
    sudo snap set "$snap_name" daemon.msg="$new_msg"
    # The configure hook restarts the service; give snapd a moment to begin the
    # restart, then wait for the port to come back up.
    sleep 0.5
    if ! wait_for_port "$SIMPLE_SERVER_PORT" 15; then
        fail "simple-server did not come back up after config change"
        return
    fi

    local new_response
    new_response=$(timeout 5 "$nc_cmd" 127.0.0.1 "$SIMPLE_SERVER_PORT" 2>/dev/null || true)
    if echo "$new_response" | grep -qF "$new_msg"; then
        pass "snap config change is reflected in TCP response"
    else
        fail "TCP response did not reflect updated message (got: $(echo "$new_response" | head -1))"
    fi
}
