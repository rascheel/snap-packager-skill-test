#!/bin/bash

# --- CONFIGURATION ---
AGENT_PROMPT="/snap-orchestrator"

# Usage: ./test-snap-packager.sh [--engine copilot|ollama] [app ...]
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
elif [[ "$ENGINE" != "copilot" && "$ENGINE" != "ollama" ]]; then
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

    # 2. CONDITIONAL AI ENGINE STEP
    if [[ "$ENGINE" == "copilot" ]]; then
        echo "  🤖 Spawning Copilot..."
        copilot -p "$AGENT_PROMPT" --allow-all
    elif [[ "$ENGINE" == "ollama" ]]; then
        echo "  🤖 Spawning Ollama (Claude)..."
        ollama launch claude --model qwen3-coder-next --yes -- -p "$AGENT_PROMPT" --dangerously-skip-permissions
    else
        echo "  ⏩ Skipping AI step."
    fi

    cd ..
    echo "✅ Finished $dir_name"
    echo ""
done

echo "---"
echo "✨ All directories processed."
