#!/bin/bash

# --- CONFIGURATION ---
AGENT_PROMPT="/snap-packager target an x86 runtime"

ENGINE=$1

if [[ -z "$ENGINE" ]]; then
    echo "ℹ️  No AI engine specified. Running in 'Cleanup Only' mode."
elif [[ "$ENGINE" != "copilot" && "$ENGINE" != "ollama" ]]; then
    echo "⚠️  Unknown engine '$ENGINE'. Defaulting to 'Cleanup Only' mode."
    ENGINE=""
else
    echo "🚀 Starting batch processing using: $ENGINE"
fi

echo "---"

for dir in */; do
    dir_name=${dir%/}

    echo "📂 Processing: $dir_name"

    if ! cd "$dir"; then
        echo "❌ Failed to enter $dir_name"
        continue
    fi

    # 1. THE NUCLEAR GIT RESET (Always runs)
    if [ -d ".git" ]; then
        echo "  🧹 Cleaning repository (nuclear)..."
        git reset --hard HEAD &>/dev/null
        git clean -fdx &>/dev/null
    else
        echo "  ⚠️  No .git found, skipping reset..."
    fi

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
