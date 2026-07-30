# snap-packager test harness

This repo contains a test harness for evaluating the `snap-packager` Copilot skill. It uses real open-source projects as subjects, runs the skill against each one to produce a snap, and then validates the resulting snap with a dedicated test suite.

Supported AI engines: Copilot, Ollama, and Claude Code (Sonnet).

## Repository layout

```
.
├── test-snap-packager.sh   # Drive the snap-packager skill across all (or selected) apps
├── run-snap-tests.sh       # Run the snap test suite against built snaps
├── tests/                  # Per-app test scripts and shared helpers (tests/lib.sh)
├── darkhttpd/              # submodule — https://github.com/emikulic/darkhttpd
├── dufs/                   # submodule — https://github.com/sigoden/dufs
├── helix/                  # submodule — https://github.com/helix-editor/helix
├── htop/                   # submodule — https://github.com/htop-dev/htop
├── ollama/                 # submodule — https://github.com/ollama/ollama
└── simple-server/          # submodule — https://github.com/rascheel/simple-server
```

## Getting started

Clone with submodules:

```bash
git clone --recurse-submodules <repo-url>
```

If you already cloned without `--recurse-submodules`:

```bash
git submodule update --init --recursive
```

## `test-snap-packager.sh`

Iterates over every app subdirectory (or a specified subset), resets it to a clean state, and optionally invokes a Copilot, Ollama, or Claude Code agent to run the `/snap-packager` skill inside each app's directory.

**Usage:**

```bash
./test-snap-packager.sh [--engine copilot|ollama|claude] [app ...]
```

| Argument | Description |
|---|---|
| `--engine copilot` | Use the GitHub Copilot CLI agent |
| `--engine ollama` | Use a local Ollama agent (qwen3-coder-next model) |
| `--engine claude` | Use the Claude Code CLI agent (Sonnet model) |
| *(no `--engine`)* | Cleanup-only mode — resets repos without invoking any AI |
| `app ...` | One or more app names to process; omit to process all |

**Examples:**

```bash
# Reset all app repos to a clean state (no AI)
./test-snap-packager.sh

# Run the snap-packager skill via Copilot on all apps
./test-snap-packager.sh --engine copilot

# Run only on darkhttpd and htop using Ollama
./test-snap-packager.sh --engine ollama darkhttpd htop

# Run the snap-packager skill via Claude Code (Sonnet) on all apps
./test-snap-packager.sh --engine claude
```

For each app the script:
1. Performs a hard `git reset` and `git clean` to remove any previously generated files.
2. (If an engine is specified) Spawns the AI agent with the `/snap-packager` prompt, which produces a `snap/snapcraft.yaml` and supporting files inside the app directory.

## `run-snap-tests.sh`

Validates the snaps that were built by the packager step. For each app it locates the `.snap` file produced inside the app's directory, installs it with `snap install --dangerous`, runs a set of functional checks, then removes the snap regardless of outcome.

**Requires:** `sudo` (for `snap install` / `snap remove`).

**Usage:**

```bash
./run-snap-tests.sh [app ...]
```

| Argument | Description |
|---|---|
| *(none)* | Test all apps |
| `app ...` | Test only the named apps |

**Examples:**

```bash
# Test all apps
./run-snap-tests.sh

# Test only dufs and simple-server
./run-snap-tests.sh dufs simple-server
```

Test scripts live in `tests/<app>.sh`. Each script defines a `run_tests()` function that uses the shared helpers in `tests/lib.sh` (HTTP assertions, service state checks, port-readiness waits, etc.). Results are summarised at the end:

```
━━━ Summary ━━━
  Passed : 12
  Failed : 0
  Skipped: 1
```

The script exits with code `1` if any test fails.

## Typical workflow

```bash
# 1. Run the packager skill to generate snaps
./test-snap-packager.sh --engine copilot

# 2. Build each snap (snapcraft must be available in each app dir)
for d in darkhttpd dufs helix htop ollama simple-server; do
    (cd "$d" && snapcraft)
done

# 3. Validate the built snaps
./run-snap-tests.sh
```
