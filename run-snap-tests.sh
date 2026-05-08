#!/usr/bin/env bash
# run-snap-tests.sh — Run the snap test suite for all (or selected) apps.
#
# Usage:
#   ./run-snap-tests.sh [app ...]
#
# Examples:
#   ./run-snap-tests.sh                  # test all apps
#   ./run-snap-tests.sh darkhttpd dufs   # test specific apps
#   ./run-snap-tests.sh htop             # test a single app
#
# Each app's .snap file is discovered automatically inside its subdirectory.
# The tests require sudo for snap install/remove. Snaps are removed after each
# test regardless of pass/fail.
#
# Environment variables in each test script can be used to override defaults
# (ports, service names, etc.) if the snap-packager produces non-standard values.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$SCRIPT_DIR/tests"

# Source shared helpers (sets up PASS_COUNT, FAIL_COUNT, SKIP_COUNT)
# shellcheck source=tests/lib.sh
source "$TESTS_DIR/lib.sh"

# Apps and the directory that contains their source + built .snap file.
declare -A APP_DIRS=(
    [darkhttpd]="$SCRIPT_DIR/darkhttpd"
    [dufs]="$SCRIPT_DIR/dufs"
    [helix]="$SCRIPT_DIR/helix"
    [htop]="$SCRIPT_DIR/htop"
    [ollama]="$SCRIPT_DIR/ollama"
    [simple-server]="$SCRIPT_DIR/simple-server"
)

# Determine which apps to test
if [[ $# -gt 0 ]]; then
    APPS_TO_TEST=("$@")
else
    APPS_TO_TEST=("${!APP_DIRS[@]}")
fi

# Validate requested apps
for app in "${APPS_TO_TEST[@]}"; do
    if [[ -z "${APP_DIRS[$app]+_}" ]]; then
        echo "ERROR: Unknown app '$app'. Known apps: ${!APP_DIRS[*]}" >&2
        exit 1
    fi
done

echo -e "\n${BOLD}━━━ Snap Test Suite ━━━${NC}"
echo "Apps: ${APPS_TO_TEST[*]}"
echo "Running as: $(id -un)  (sudo required for snap install/remove)"
echo ""

# Overall counters (accumulate across all apps)
TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0

run_app_tests() {
    local app="$1"
    local app_dir="${APP_DIRS[$app]}"
    local test_script="$TESTS_DIR/${app}.sh"

    if [[ ! -f "$test_script" ]]; then
        echo -e "${YELLOW}⚠  No test script for '$app' ($test_script)${NC}"
        return
    fi

    # Reset per-app counters
    PASS_COUNT=0
    FAIL_COUNT=0
    SKIP_COUNT=0

    local snap_file
    snap_file=$(find_snap_file "$app_dir")

    if [[ -z "$snap_file" ]]; then
        echo -e "\n${BOLD}[ $app ]${NC}"
        echo -e "  ${YELLOW}~${NC} No .snap file found in $app_dir — skipping"
        TOTAL_SKIP=$((TOTAL_SKIP + 1))
        return
    fi

    # Source the test script to load its run_tests() function
    # shellcheck source=/dev/null
    source "$test_script"

    # Run tests; capture any unexpected errors
    if ! run_tests "$snap_file"; then
        [[ $FAIL_COUNT -eq 0 ]] && ((FAIL_COUNT++))
    fi
    trap - RETURN  # Clear any RETURN trap set by run_tests

    local status_line=""
    [[ $PASS_COUNT -gt 0 ]] && status_line+="${GREEN}${PASS_COUNT} passed${NC}  "
    [[ $FAIL_COUNT -gt 0 ]] && status_line+="${RED}${FAIL_COUNT} failed${NC}  "
    [[ $SKIP_COUNT -gt 0 ]] && status_line+="${YELLOW}${SKIP_COUNT} skipped${NC}"
    echo -e "  ${BOLD}Result:${NC} $status_line"

    TOTAL_PASS=$((TOTAL_PASS + PASS_COUNT))
    TOTAL_FAIL=$((TOTAL_FAIL + FAIL_COUNT))
    TOTAL_SKIP=$((TOTAL_SKIP + SKIP_COUNT))
}

for app in "${APPS_TO_TEST[@]}"; do
    run_app_tests "$app"
done

# Summary
echo -e "\n${BOLD}━━━ Summary ━━━${NC}"
echo -e "  ${GREEN}Passed : $TOTAL_PASS${NC}"
echo -e "  ${RED}Failed : $TOTAL_FAIL${NC}"
echo -e "  ${YELLOW}Skipped: $TOTAL_SKIP${NC}"
echo ""

if [[ $TOTAL_FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
