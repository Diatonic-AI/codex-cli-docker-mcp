#!/usr/bin/env bash
set -euo pipefail

# Ensure CODEX_HOME exists and has sane defaults for 'node' user
: "${CODEX_HOME:=/home/node/.codex}"
mkdir -p "$CODEX_HOME/log" "$CODEX_HOME" || true

# If no config exists, seed a minimal config (non-destructive)
CONFIG_TOML="$CODEX_HOME/config.toml"
if [[ ! -f "$CONFIG_TOML" ]]; then
  cat > "$CONFIG_TOML" <<'EOF'
# ~/.codex/config.toml — seeded by Docker entrypoint (safe defaults)
# Approval + sandbox defaults align with OpenAI docs
approval_policy = "on-request"           # ask before protected actions
sandbox_mode    = "workspace-write"      # write within /workspace, ask for outside

disable_response_storage = true          # ZDR-friendly default

[sandbox_workspace_write]
network_access = true                    # allow network within guardrails

# Auth method will be set to apikey below if a secret is present
preferred_auth_method = "chatgpt"

# Example MCP server definitions (disabled until you fill in)
# [mcp_servers.example]
# command = "npx"
# args = ["-y", "mcp-server"]
# env = { "API_KEY" = "{{YOUR_KEY}}" }
EOF
fi

# Load API key securely from Docker secret if present, but do NOT persist it
if [[ -f /run/secrets/openai_api_key ]]; then
  export OPENAI_API_KEY="$(head -c 8192 /run/secrets/openai_api_key | tr -d '\r\n')"
  # If we have an API key, switch preferred_auth_method to apikey in-place
  if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    # Normalize any previous api_key -> apikey
    if grep -q 'preferred_auth_method\s*=\s*"api_key"' "$CONFIG_TOML" 2>/dev/null; then
      sed -i 's/preferred_auth_method\s*=\s*"api_key"/preferred_auth_method = "apikey"/' "$CONFIG_TOML" || true
    fi
    if grep -q '^preferred_auth_method\s*=\s*"chatgpt"' "$CONFIG_TOML" 2>/dev/null; then
      sed -i 's/^preferred_auth_method\s*=\s*"chatgpt"/preferred_auth_method = "apikey"/' "$CONFIG_TOML" || true
    fi
  fi
fi

# Non-interactive subcommands for automation
usage() {
  cat <<USAGE
Usage: entrypoint.sh [run|codex|shell|COMMAND ...]
  run [args...]     Run codex non-interactively with provided args
  codex [args...]   Run codex with provided args
  shell             Start an interactive login shell (bash -l)
  COMMAND [...]     Execute arbitrary command
USAGE
}

if [[ $# -eq 0 ]]; then
  # Default to interactive shell when no args are given
  exec bash -l
fi

subcmd="$1"; shift || true
case "$subcmd" in
  -h|--help|help)
    usage; exit 0;;
  run)
    # Non-interactive: run codex with given args
    exec codex "$@";;
  codex)
    exec codex "$@";;
  shell)
    exec bash -l;;
  *)
    exec "$subcmd" "$@";;
esac
