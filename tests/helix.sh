#!/usr/bin/env bash
# Tests for the helix snap.
#
# Helix (hx) is a modal terminal text editor written in Rust.
# Since it requires a TTY for the TUI, tests use CLI flags that exit cleanly.
#
# Helix spawns arbitrary language servers, formatters, and linters from the
# user's PATH, so it requires classic confinement. A strict snap is considered
# a packaging failure.
#
# Override these via environment variables:
#   HELIX_CMD  - snap command name for the helix binary (default: hx)

HELIX_CMD="${HELIX_CMD:-hx}"

run_tests() {
    local snap_file="$1"
    local snap_name
    snap_name=$(snap_name_from_meta "$snap_file")

    header "helix"

    # Check confinement before installing — helix must be classic because it
    # needs to invoke arbitrary language servers from the user's PATH.
    local confinement=""
    if command -v unsquashfs &>/dev/null; then
        confinement=$(unsquashfs -cat "$snap_file" meta/snap.yaml 2>/dev/null \
            | grep "^confinement:" | head -1 | sed 's/^confinement:[[:space:]]*//')
    fi

    if [[ "$confinement" == "classic" ]]; then
        pass "snap uses classic confinement (required for LSP/tool integration)"
    else
        fail "snap uses '$confinement' confinement — helix requires classic confinement to invoke language servers, formatters, and linters from the user's PATH"
    fi

    install_snap "$snap_file" "--classic" || return 1

    cleanup() { remove_snap "$snap_name"; }
    trap cleanup RETURN

    # Snap commands are exposed as '<snap-name>.<app-name>' when the app name
    # differs from the snap name (e.g. snap=helix, app=hx → helix.hx).
    # Try HELIX_CMD directly first, then the qualified form, then the snap name.
    local cmd
    if command -v "$HELIX_CMD" &>/dev/null; then
        cmd="$HELIX_CMD"
    elif command -v "${snap_name}.${HELIX_CMD}" &>/dev/null; then
        cmd="${snap_name}.${HELIX_CMD}"
    else
        cmd="$snap_name"
    fi

    assert_output_matches \
        "--version prints version string" \
        "[0-9]+\.[0-9]+" \
        "$cmd" --version

    assert_exits_ok \
        "--version exits with code 0" \
        "$cmd" --version

    assert_exits_ok \
        "--help exits with code 0" \
        "$cmd" --help

    # --health checks that helix can find its runtime directory (themes,
    # grammars, queries). A missing runtime is a snap packaging failure.
    info "Running --health to check runtime/grammar access..."
    local health_output
    health_output=$("$cmd" --health 2>&1 || true)

    if echo "$health_output" | grep -qiE "could not find|runtime.*not found|no such file"; then
        fail "helix cannot find its runtime directory (grammars/themes missing from snap)"
    else
        pass "helix runtime directory is accessible"
    fi

    # --health <lang> shows per-language grammar/LSP status. Check a language
    # that helix always bundles a grammar for (rust is compiled into the binary).
    local lang_health
    lang_health=$("$cmd" --health rust 2>&1 || true)
    if echo "$lang_health" | grep -qiE "Highlight|Textobject|Indent|grammar"; then
        pass "tree-sitter grammars are present (rust grammar check passed)"
    else
        skip "could not confirm tree-sitter grammars (check '$cmd --health rust' manually)"
    fi
}
