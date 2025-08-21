#!/usr/bin/env bash
# Resolve an OpenAI project id by name using Admin API (prints id or empty)
set -euo pipefail
: "${OPENAI_ADMIN_KEY:?Set OPENAI_ADMIN_KEY in your environment}"
: "${PROJECT_NAME:?Set PROJECT_NAME to the project name}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=bin/openai-admin.sh
OPENAI_ADMIN_KEY="$OPENAI_ADMIN_KEY" source "$SCRIPT_DIR/openai-admin.sh"
admin_project_id_by_name "$PROJECT_NAME" || true
