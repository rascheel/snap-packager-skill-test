#!/usr/bin/env bash
# Tests for the Redis server snap.
#
# The test installs the snap, waits for the Redis daemon to listen, and verifies
# basic Redis operations (ping, set, get) through the confined network stack.
# Commands are sent as plain-text RESP "inline commands" over a raw /dev/tcp
# socket, so no redis-cli or other client tooling is required.
#
# Override these via environment variables:
#   REDIS_APP        - snap service name (default: entrypoint)
#   REDIS_TEST_PORT  - Redis server port (default: 6379)

REDIS_APP="${REDIS_APP:-redis}"
REDIS_TEST_PORT="${REDIS_TEST_PORT:-6379}"

# Send one RESP inline command on fd 3 and print its reply's payload.
# Simple strings/integers print without their type prefix; bulk strings print
# their data (empty for a nil reply); errors print the raw line and fail.
redis_cmd() {
    local cmd="$1"
    local line
    printf '%s\r\n' "$cmd" >&3
    IFS= read -r line <&3 || return 1
    line="${line%$'\r'}"

    case "$line" in
        '$'*)
            local len="${line#\$}"
            if (( len < 0 )); then
                return 0
            fi
            local data=""
            if (( len > 0 )); then
                IFS= read -r -N "$len" data <&3 || return 1
            fi
            IFS= read -r -N 2 _ <&3 || true  # discard the bulk string's trailing CRLF
            printf '%s' "$data"
            ;;
        '+'*|':'*)
            printf '%s' "${line:1}"
            ;;
        '-'*)
            printf '%s' "$line"
            return 1
            ;;
        *)
            printf '%s' "$line"
            ;;
    esac
}

run_tests() {
    local snap_file="$1"
    local snap_name
    snap_name=$(snap_name_from_meta "$snap_file")

    header "redis"

    cleanup() {
        exec 3<&- 2>/dev/null || true
        exec 3>&- 2>/dev/null || true
        remove_snap "$snap_name"
    }
    trap cleanup RETURN

    install_snap "$snap_file" || return 1

    if ! wait_for_port "$REDIS_TEST_PORT" 30; then
        fail "Redis did not listen on port $REDIS_TEST_PORT"
        return 1
    fi

    if snap services "$snap_name.$REDIS_APP" 2>/dev/null | awk 'NR > 1 { print $3 }' | grep -qx active; then
        pass "Redis snap service is active"
    else
        fail "Redis snap service is not active"
        return 1
    fi

    if ! exec 3<>"/dev/tcp/127.0.0.1/$REDIS_TEST_PORT"; then
        fail "could not open a raw TCP connection to Redis"
        return 1
    fi

    local reply
    reply=$(redis_cmd "PING") || true
    if [[ "$reply" == "PONG" ]]; then
        pass "Redis accepted a PING command"
    else
        fail "Redis did not respond to PING (got: $reply)"
        return 1
    fi

    reply=$(redis_cmd "SET snap-packager-test-key snap-packager-test-value") || true
    if [[ "$reply" == "OK" ]]; then
        pass "SET command stored a value in Redis"
    else
        fail "SET command did not succeed (got: $reply)"
        return 1
    fi

    reply=$(redis_cmd "GET snap-packager-test-key") || true
    if [[ "$reply" == "snap-packager-test-value" ]]; then
        pass "GET command read the value through the confined network stack"
    else
        fail "GET command did not return the expected value (got: $reply)"
        return 1
    fi
}
