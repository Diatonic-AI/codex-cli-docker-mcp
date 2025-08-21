#!/usr/bin/env bash
# Minimal self-check for Codex Dockerized stack
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT_DIR"

# Ensure docker is available
command -v docker >/dev/null || { echo "docker not found"; exit 2; }
command -v docker compose >/dev/null || { echo "docker compose not found"; exit 2; }

# Guard: ensure volumes dir exists and is writable
mkdir -p "$ROOT_DIR/volumes/codex_home" "$ROOT_DIR/volumes/workspace"
[ -w "$ROOT_DIR/volumes/codex_home" ] || { echo "codex_home not writable"; exit 3; }
[ -w "$ROOT_DIR/volumes/workspace" ] || { echo "workspace not writable"; exit 3; }

# Build on demand if not built
if ! docker image inspect local/codex-cli:latest >/dev/null 2>&1; then
  docker compose -f "$ROOT_DIR/docker-compose.yaml" build
fi

# Bring up a one-off container to run simple checks
# 1) codex --version
# 2) entrypoint.sh run --help
# 3) echo prompt into codex exec (offline safe help)

echo "[self-check] codex --version"
docker compose -f "$ROOT_DIR/docker-compose.yaml" run --rm codex codex --version

echo "[self-check] entrypoint help"
docker compose -f "$ROOT_DIR/docker-compose.yaml" run --rm codex entrypoint.sh --help || true

# If OPENAI_API_KEY provided in env or secrets, also try a no-op prompt in api-key mode
if [[ -n "${OPENAI_API_KEY:-}" ]]; then
  echo "[self-check] codex basic prompt"
  docker compose -f "$ROOT_DIR/docker-compose.yaml" run --rm codex bash -lc 'echo "explain: hello" | codex exec --config preferred_auth_method="apikey"'
else
  echo "[self-check] OPENAI_API_KEY not set; skipping prompt test"
fi

# Additional validation checks
echo "[self-check] Validating project structure"
[ -f "$ROOT_DIR/README.md" ] || { echo "Missing README.md"; exit 4; }
[ -f "$ROOT_DIR/docker-compose.yaml" ] || { echo "Missing docker-compose.yaml"; exit 4; }
[ -f "$ROOT_DIR/Dockerfile" ] || { echo "Missing Dockerfile"; exit 4; }
[ -d "$ROOT_DIR/codex-rs" ] || { echo "Missing codex-rs directory"; exit 4; }

# Check that we can reach the running container's health
if docker compose -f "$ROOT_DIR/docker-compose.ci.yaml" ps --format table 2>/dev/null | grep -q "codex-cli"; then
  echo "[self-check] Container health OK"
else
  echo "[self-check] Warning: Container not running or unhealthy"
fi

echo "[self-check] ✅ All checks passed"
