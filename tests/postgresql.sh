#!/usr/bin/env bash
# Tests for the PostgreSQL OCI snap.
#
# The test installs the snap, waits for the PostgreSQL daemon to listen, and
# uses the snap's bundled pg_isready client to verify that the server accepts
# PostgreSQL requests through the confined network stack.
#
# Override these via environment variables:
#   POSTGRESQL_APP       - snap app/service name (default: postgres)
#   POSTGRESQL_TEST_PORT - PostgreSQL server port (default: 5432)

POSTGRESQL_APP="${POSTGRESQL_APP:-postgres}"
POSTGRESQL_TEST_PORT="${POSTGRESQL_TEST_PORT:-5432}"

run_tests() {
    local snap_file="$1"
    local snap_name
    snap_name=$(snap_name_from_meta "$snap_file")

    header "postgresql"

    cleanup() {
        remove_snap "$snap_name"
    }
    trap cleanup RETURN

    install_snap "$snap_file" || return 1

    if wait_for_port "$POSTGRESQL_TEST_PORT" 30; then
        pass "PostgreSQL is listening on port $POSTGRESQL_TEST_PORT"
    else
        fail "PostgreSQL did not listen on port $POSTGRESQL_TEST_PORT"
        return 1
    fi

    if snap services "$snap_name.$POSTGRESQL_APP" 2>/dev/null | awk 'NR > 1 { print $3 }' | grep -qx active; then
        pass "PostgreSQL snap service is active"
    else
        fail "PostgreSQL snap service is not active"
        return 1
    fi

    if sudo snap run --shell "$snap_name.$POSTGRESQL_APP" -c \
        'exec "$SNAP/usr/lib/postgresql/18/bin/pg_isready" --host 127.0.0.1 --port "$1" --username postgres --dbname postgres' \
        -- "$POSTGRESQL_TEST_PORT" &>/dev/null; then
        pass "PostgreSQL accepted a readiness request through the confined network stack"
    else
        fail "PostgreSQL did not accept a readiness request"
        return 1
    fi
}
