#!/usr/bin/env bash
# Shared helpers for snap test scripts.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

pass() { echo -e "  ${GREEN}✓${NC} $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "  ${RED}✗${NC} $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip() { echo -e "  ${YELLOW}~${NC} $1"; SKIP_COUNT=$((SKIP_COUNT + 1)); }
info() { echo -e "  ${CYAN}→${NC} $1"; }
header() { echo -e "\n${BOLD}[ $1 ]${NC}"; }

# Find the first .snap file in a directory.
find_snap_file() {
    local dir="$1"
    # Depth is 2 as for OCI applications the "project folder" is sometimes
    # nested inside the main one (e.g. `redis/redis-snap`)
    find "$dir" -maxdepth 2 -name "*.snap" 2>/dev/null | sort | head -1
}

# Parse the snap name from a .snap filename: <name>_<version>_<arch>.snap
snap_name_from_file() {
    basename "$1" | cut -d_ -f1
}

# Return the snap name from embedded meta/snap.yaml (more authoritative).
# Falls back to filename parsing if unsquashfs is unavailable.
snap_name_from_meta() {
    local snap_file="$1"
    local name
    if command -v unsquashfs &>/dev/null; then
        name=$(unsquashfs -cat "$snap_file" meta/snap.yaml 2>/dev/null \
               | grep "^name:" | head -1 | sed 's/^name:[[:space:]]*//')
    fi
    if [[ -z "$name" ]]; then
        name=$(snap_name_from_file "$snap_file")
    fi
    echo "$name"
}

# Install a snap with --dangerous (unsigned local build).
# Pass --classic as a second argument for classic snaps.
install_snap() {
    local snap_file="$1"
    local extra_flags="${2:-}"
    info "Installing: $(basename "$snap_file")"
    # shellcheck disable=SC2086
    if ! sudo snap install --dangerous $extra_flags "$snap_file" 2>&1 | sed 's/^/    /'; then
        fail "snap install failed"
        return 1
    fi
}

# Remove a snap by name, ignoring errors if it's already gone.
remove_snap() {
    local snap_name="$1"
    info "Removing: $snap_name"
    sudo snap remove "$snap_name" 2>&1 | sed 's/^/    /' || true
}

# Wait until a TCP port is accepting connections (or timeout).
wait_for_port() {
    local port="$1"
    local timeout="${2:-15}"
    local elapsed=0
    while ! bash -c "echo >/dev/tcp/127.0.0.1/$port" 2>/dev/null; do
        sleep 0.5
        elapsed=$(echo "$elapsed + 0.5" | bc)
        if (( $(echo "$elapsed >= $timeout" | bc -l) )); then
            return 1
        fi
    done
}

# Return the HTTP status code for a URL.
http_status() {
    curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$1" 2>/dev/null
}

# Return the HTTP response body for a URL.
http_body() {
    curl -s --max-time 5 "$1" 2>/dev/null
}

# Assert that a command produces output matching a pattern.
assert_output_matches() {
    local label="$1"
    local pattern="$2"
    shift 2
    local output
    output=$("$@" 2>&1)
    if echo "$output" | grep -qE "$pattern"; then
        pass "$label"
    else
        fail "$label (output: $(echo "$output" | head -3))"
    fi
}

# Assert a command exits with code 0.
assert_exits_ok() {
    local label="$1"
    shift
    if "$@" &>/dev/null; then
        pass "$label"
    else
        fail "$label"
    fi
}

# Assert an HTTP URL returns a given status code.
assert_http_status() {
    local label="$1"
    local expected_status="$2"
    local url="$3"
    local actual_status
    actual_status=$(http_status "$url")
    if [[ "$actual_status" == "$expected_status" ]]; then
        pass "$label (HTTP $actual_status)"
    else
        fail "$label (expected HTTP $expected_status, got HTTP $actual_status)"
    fi
}

# Assert an HTTP URL body contains a string.
assert_http_body_contains() {
    local label="$1"
    local pattern="$2"
    local url="$3"
    local body
    body=$(http_body "$url")
    if echo "$body" | grep -qE "$pattern"; then
        pass "$label"
    else
        fail "$label (body did not match '$pattern')"
    fi
}

# Assert a snap service is in a given state (active/inactive/...).
assert_snap_service() {
    local label="$1"
    local snap_name="$2"
    local svc="$3"
    local expected_state="${4:-active}"
    local actual_state
    actual_state=$(snap services "${snap_name}.${svc}" 2>/dev/null \
                   | awk 'NR>1 {print $3}' | head -1)
    if [[ "$actual_state" == "$expected_state" ]]; then
        pass "$label (service $svc is $actual_state)"
    else
        fail "$label (service $svc: expected $expected_state, got '$actual_state')"
    fi
}
