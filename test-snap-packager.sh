#!/bin/bash

# --- CONFIGURATION ---
SKILL_PROMPT="/snap-builder"

# Appended to the prompt of every engine. These are unattended batch runs, so the
# agent must never stop to ask the user a question -- several skills in the pipeline
# (notably snap-analyzer, for classic confinement) otherwise halt and wait for input.
NONINTERACTIVE_DIRECTIVE=$(cat <<'EOF'
OPERATING MODE: NON-INTERACTIVE, UNATTENDED BATCH RUN.

No human is available. Nobody will read or answer a question you ask, so asking one
does not pause the run for input -- it ends the run early and counts as a failure.
Do not use AskUserQuestion. Do not end your turn to wait for confirmation, approval,
or a decision. Pursue the objective autonomously until the pipeline is complete.

Whenever a skill step says to ask, prompt, or confirm with the user, decide it
yourself using that skill's own stated criteria, record the decision and its
rationale in your output, and continue. Specifically:

- Confinement: use whatever the analysis concludes is technically required -- strict
  whenever the app can work under strict plus interfaces, classic only when the
  analysis determines strict is unworkable for that app type. Do not ask which to
  use. Write the classic Store-review and Ubuntu Core caveats into the analysis
  notes and the final report instead of asking.
- Input type: if input-type detection is ambiguous, treat the working directory as a
  source-code project (source path, snap-analyzer).
- Pre-existing analysis files or other intermediate artifacts: regenerate them rather
  than asking whether to reuse them.
- If a step is genuinely blocked, exhaust the skill's documented fallbacks, then
  record the blocker in the final report and carry on with the remaining phases.
- Long-running work: never end your turn while a build, a sub-agent, or any other
  background task is still running. In this mode, ending your turn can end the run
  and kill that work. Run builds such as `snapcraft pack` in the foreground with a
  generous timeout (single commands may run for up to 60 minutes). If you do start
  something in the background, stay in the same turn and keep checking on it until it
  has finished and you have its result. When you delegate a phase to a sub-agent, wait
  for its final result before ending your turn. Do not use ScheduleWakeup or cron
  tools.

This directive applies to every sub-agent as well. When you delegate a phase, include
these non-interactive instructions verbatim in the sub-agent's prompt so it does not
stop to ask a question either.

Stop only when all phases have completed, or when a skill's documented iteration or
error limit is reached. Finish with the final report.
EOF
)

AGENT_PROMPT="$SKILL_PROMPT

$NONINTERACTIVE_DIRECTIVE"

# Claude Code settings for unattended `-p` runs (claude and ollama engines).
#   CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0  keep waiting for background tasks
#     (sub-agents, monitors) instead of terminating the run after 600 seconds.
#   BASH_MAX_TIMEOUT_MS  let a single foreground command run for up to 60 minutes,
#     so long builds (e.g. helix's Rust compile) don't need to be backgrounded.
CLAUDE_ENV=(CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 BASH_MAX_TIMEOUT_MS=3600000)

# Scheduling tools only make sense in interactive sessions; in a `-p` run they
# lead the agent to end its turn and wait for a wakeup that never comes.
DISALLOWED_TOOLS="ScheduleWakeup,CronCreate"

# Usage: ./test-snap-packager.sh [--engine copilot|ollama|claude] [app ...]
#   --engine  AI engine to use (optional; omit for cleanup-only mode)
#   app ...   One or more app directory names to process (optional; omit for all)

ENGINE=""
FILTER_APPS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --engine)
            ENGINE="$2"
            shift 2
            ;;
        *)
            FILTER_APPS+=("$1")
            shift
            ;;
    esac
done

if [[ -z "$ENGINE" ]]; then
    echo "ℹ️  No AI engine specified. Running in 'Cleanup Only' mode."
elif [[ "$ENGINE" != "copilot" && "$ENGINE" != "ollama" && "$ENGINE" != "claude" ]]; then
    echo "⚠️  Unknown engine '$ENGINE'. Defaulting to 'Cleanup Only' mode."
    ENGINE=""
else
    echo "🚀 Starting batch processing using: $ENGINE"
fi

if [[ ${#FILTER_APPS[@]} -gt 0 ]]; then
    echo "🔍 Limiting to apps: ${FILTER_APPS[*]}"
fi

echo "---"

FAILED_APPS=()
UNCLEAN_APPS=()

# Check that an agent run left the expected pipeline outputs in the current
# directory. OCI projects may be nested one level down (e.g. postgresql/postgresql-snap).
# Usage: check_pipeline_result <app> <engine exit status>
check_pipeline_result() {
    local app="$1"
    local rc="$2"
    local problems=()

    [[ "$rc" -eq 0 ]] || problems+=("engine exited with status $rc")

    local manifest snap_file results
    if [[ -f snap/snapcraft.yaml ]]; then
        manifest="snap/snapcraft.yaml"
    else
        manifest=$(find . -maxdepth 3 -name snapcraft.yaml -not -path "*/rootfs/*" 2>/dev/null | sort | head -1)
    fi
    snap_file=$(find . -maxdepth 2 -name "*.snap" 2>/dev/null | sort | head -1)
    results=$(find . -maxdepth 2 -name snap-validation-results.json 2>/dev/null | sort | head -1)

    [[ -n "$manifest" ]] || problems+=("no snapcraft.yaml")
    [[ -n "$snap_file" ]] || problems+=("no .snap built")

    # snap-validator hard-stops for classic snaps, so no results file is expected.
    if [[ -n "$manifest" ]] && grep -qE '^confinement:[[:space:]]*classic' "$manifest"; then
        echo "  ℹ️  Classic confinement: validation is skipped by design."
    elif [[ -z "$results" ]]; then
        problems+=("no snap-validation-results.json")
    elif ! python3 -c 'import json, sys; sys.exit(0 if json.load(open(sys.argv[1])).get("clean") is True else 1)' "$results" 2>/dev/null; then
        echo "  ⚠️  Validation results are not clean: $results"
        UNCLEAN_APPS+=("$app")
    fi

    if [[ ${#problems[@]} -gt 0 ]]; then
        local IFS=";"
        echo "  ❌ Pipeline incomplete:${problems[*]/#/ }"
        FAILED_APPS+=("$app")
        return 1
    fi
}

for dir in */; do
    dir_name=${dir%/}

    # If specific apps were requested, skip anything not in the list
    if [[ ${#FILTER_APPS[@]} -gt 0 ]]; then
        match=0
        for app in "${FILTER_APPS[@]}"; do
            [[ "$app" == "$dir_name" ]] && match=1 && break
        done
        if [[ $match -eq 0 ]]; then
            continue
        fi
    fi

    echo "📂 Processing: $dir_name"

    if ! cd "$dir"; then
        echo "❌ Failed to enter $dir_name"
        continue
    fi

    app_prompt="$AGENT_PROMPT"
    if [ -e ".git" ]; then
        # Source fixtures are submodules, so reset them before every agent run.
        echo "  🧹 Cleaning repository (nuclear)..."
        git reset --hard HEAD &>/dev/null
        git clean -fdx &>/dev/null
    elif [ -f "image-ref.txt" ]; then
        # OCI fixtures are tracked metadata, not nested Git repositories. Remove
        # everything the top-level .gitignore marks as generated (extraction,
        # nested project folders such as postgresql-snap/, OCI layouts, builds),
        # keeping only the tracked README.md and image-ref.txt.
        echo "  🧹 Cleaning generated OCI packaging artifacts..."
        git clean -fdXq -- .

        image_ref=$(<image-ref.txt)
        if [[ -z "$image_ref" ]]; then
            echo "  ❌ OCI fixture image-ref.txt is empty"
            cd ..
            continue
        fi
        app_prompt+="

OCI FIXTURE INPUT:
Package this exact Docker/OCI image, not the current directory as a source project:
$image_ref

Build for amd64 and retain strict confinement."
    else
        echo "  ⏩ No .git or image-ref.txt found, not an application fixture. Skipping."
        cd ..
        continue
    fi

    # Remove previous analysis file to avoid NOP runs asking if the analysis
    # should be kept or regenerated
    analysis_file="/tmp/snap-analysis-$dir_name.json"
    if [ -e "$analysis_file" ] ; then
	rm "$analysis_file"
    fi

    # 2. CONDITIONAL AI ENGINE STEP
    engine_rc=0
    if [[ "$ENGINE" == "copilot" ]]; then
        echo "  🤖 Spawning Copilot..."
        copilot -p "$app_prompt" --allow-all
        engine_rc=$?
    elif [[ "$ENGINE" == "ollama" ]]; then
        echo "  🤖 Spawning Ollama (Claude)..."
        env "${CLAUDE_ENV[@]}" ollama launch claude --model qwen3-coder-next --yes -- -p "$app_prompt" --dangerously-skip-permissions --disallowedTools "$DISALLOWED_TOOLS" --append-system-prompt "$NONINTERACTIVE_DIRECTIVE"
        engine_rc=$?
    elif [[ "$ENGINE" == "claude" ]]; then
        echo "  🤖 Spawning Claude (Sonnet)..."
        env "${CLAUDE_ENV[@]}" claude -p "$app_prompt" --model sonnet --dangerously-skip-permissions --disallowedTools "$DISALLOWED_TOOLS" --append-system-prompt "$NONINTERACTIVE_DIRECTIVE"
        engine_rc=$?
    else
        echo "  ⏩ Skipping AI step."
    fi

    status="✅ Finished"
    if [[ -n "$ENGINE" ]] && ! check_pipeline_result "$dir_name" "$engine_rc"; then
        status="❌ Finished (pipeline incomplete)"
    fi

    cd ..
    echo "$status $dir_name"
    echo ""
done

echo "---"
echo "✨ All directories processed."

if [[ ${#UNCLEAN_APPS[@]} -gt 0 ]]; then
    echo "⚠️  Validation not clean: ${UNCLEAN_APPS[*]}"
fi
if [[ ${#FAILED_APPS[@]} -gt 0 ]]; then
    echo "❌ Pipeline incomplete: ${FAILED_APPS[*]}"
    exit 1
fi
