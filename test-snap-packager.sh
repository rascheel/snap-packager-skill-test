#!/bin/bash

# --- CONFIGURATION ---
SKILL_PROMPT="/snap-orchestrator"

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

This directive applies to every sub-agent as well. When you delegate a phase, include
these non-interactive instructions verbatim in the sub-agent's prompt so it does not
stop to ask a question either.

Stop only when all phases have completed, or when a skill's documented iteration or
error limit is reached. Finish with the final report.
EOF
)

AGENT_PROMPT="$SKILL_PROMPT

$NONINTERACTIVE_DIRECTIVE"

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

    # Skip directories that are not application repositories
    if [ ! -e ".git" ]; then
        echo "  ⏩ No .git found, not an application directory. Skipping."
        cd ..
        continue
    fi

    # 1. THE NUCLEAR GIT RESET (Always runs)
    echo "  🧹 Cleaning repository (nuclear)..."
    git reset --hard HEAD &>/dev/null
    git clean -fdx &>/dev/null

    # Remove previous analysis file to avoid NOP runs asking if the analysis
    # should be kept or regenerated
    analysis_file="/tmp/snap-analysis-$dir_name.json"
    if [ -e "$analysis_file" ] ; then
	rm "$analysis_file"
    fi

    # 2. CONDITIONAL AI ENGINE STEP
    if [[ "$ENGINE" == "copilot" ]]; then
        echo "  🤖 Spawning Copilot..."
        copilot -p "$AGENT_PROMPT" --allow-all
    elif [[ "$ENGINE" == "ollama" ]]; then
        echo "  🤖 Spawning Ollama (Claude)..."
        ollama launch claude --model qwen3-coder-next --yes -- -p "$AGENT_PROMPT" --dangerously-skip-permissions --append-system-prompt "$NONINTERACTIVE_DIRECTIVE"
    elif [[ "$ENGINE" == "claude" ]]; then
        echo "  🤖 Spawning Claude (Sonnet)..."
        claude -p "$AGENT_PROMPT" --model sonnet --dangerously-skip-permissions --append-system-prompt "$NONINTERACTIVE_DIRECTIVE"
    else
        echo "  ⏩ Skipping AI step."
    fi

    cd ..
    echo "✅ Finished $dir_name"
    echo ""
done

echo "---"
echo "✨ All directories processed."
