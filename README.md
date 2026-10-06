# snap-packager test harness

This repo contains a test harness for evaluating the `snap-builder` Copilot skill. It uses real open-source projects as subjects, runs the skill against each one to produce a snap, and then validates the resulting snap with a dedicated test suite.

Supported AI engines: Copilot, Ollama, and Claude Code (Sonnet).

## Repository layout

```
.
├── test-snap-packager.sh   # Drive the snap-builder skill across all (or selected) apps
├── run-snap-tests.sh       # Run the snap test suite against built snaps
├── tests/                  # Per-app test scripts and shared helpers (tests/lib.sh)
├── darkhttpd/              # submodule — https://github.com/emikulic/darkhttpd
├── dufs/                   # submodule — https://github.com/sigoden/dufs
├── helix/                  # submodule — https://github.com/helix-editor/helix
├── htop/                   # submodule — https://github.com/htop-dev/htop
├── ollama/                 # submodule — https://github.com/ollama/ollama
├── redis/                  # OCI fixture — pinned redis image manifest
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

Iterates over every app subdirectory (or a specified subset), resets generated state, and optionally invokes a Copilot, Ollama, or Claude Code agent to run the `/snap-builder` skill inside each fixture directory.

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

# Run the snap-builder skill via Copilot on all apps
./test-snap-packager.sh --engine copilot

# Package only the pinned Redis OCI fixture using Ollama
./test-snap-packager.sh --engine ollama redis

# Run the snap-builder skill via Claude Code (Sonnet) on all apps
./test-snap-packager.sh --engine claude
```

For each app the script:
1. Performs a hard `git reset` and `git clean` for source submodules. OCI fixtures retain their tracked metadata and remove only generated extraction and packaging artifacts.
2. (If an engine is specified) spawns the AI agent with `/snap-builder`. An OCI fixture provides a pinned image reference to the agent rather than being treated as a source-code project.

### OCI fixtures

`redis/image-ref.txt` identifies the exact image used by the Redis fixture:

```text
docker://docker.io/library/redis@sha256:76961cd2a0f40ef6fdd334b6b1b3a76a2bad1848d89f3030ca30a7521d4a9493
```

The image archive, extracted root filesystem, generated Snapcraft project, and
snap artifact are intentionally ignored. The digest is the supplied
`linux/amd64` manifest, so OCI builds must use `--build-for amd64`.

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

# Test only the Redis snap (requires redis-cli)
./run-snap-tests.sh redis
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
# 1. Run the snap-builder skill to generate snaps
./test-snap-packager.sh --engine copilot

# 2. Build source snaps (snapcraft must be available in each app dir)
for d in darkhttpd dufs helix htop ollama simple-server; do
    (cd "$d" && snapcraft)
done

# Build the OCI fixture for its pinned architecture
(cd redis && snapcraft --use-lxd --build-for amd64)

# 3. Validate the built snaps
./run-snap-tests.sh
```
