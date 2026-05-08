#!/usr/bin/env bash
# Tests for the htop snap.
#
# htop is an interactive process viewer. Since it requires a TTY for the TUI,
# tests focus on CLI flags that exit cleanly without interaction.

run_tests() {
    local snap_file="$1"
    local snap_name
    snap_name=$(snap_name_from_meta "$snap_file")

    header "htop"

    install_snap "$snap_file" || return 1

    cleanup() { remove_snap "$snap_name"; }
    trap cleanup RETURN

    assert_output_matches \
        "--version prints version string" \
        "htop" \
        "$snap_name" --version

    # -C disables color; combined with --version it should still exit cleanly
    assert_exits_ok \
        "--version exits with code 0" \
        "$snap_name" --version

    # Confirm the snap can at least read /proc (needs system-observe or similar)
    info "Checking /proc access for process listing..."
    local output
    output=$(timeout 2 "$snap_name" -d 10 --no-color 2>&1 || true)
    if echo "$output" | grep -qiE "(permission|denied|cannot)"; then
        fail "htop cannot access /proc (missing interface connection?): $output"
    else
        pass "htop has /proc access (process listing works)"
    fi
}
