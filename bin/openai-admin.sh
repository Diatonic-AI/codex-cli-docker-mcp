#!/usr/bin/env bash
# Minimal OpenAI Admin API client (uses $OPENAI_ADMIN_KEY)
# Provides helpers to list/create projects and create a service account key.
# Never prints secret values. Requires: curl, jq
set -euo pipefail

: "${OPENAI_ADMIN_BASE_URL:=https://api.openai.com}"
: "${OPENAI_ADMIN_KEY:?Set OPENAI_ADMIN_KEY in your environment (do not store in files)}"

hdr_auth=(-H "Authorization: Bearer ${OPENAI_ADMIN_KEY}")
hdr_json=(-H "Content-Type: application/json")
# Optional org scoping
if [[ -n "${OPENAI_ORG:-}" ]]; then
  hdr_org=(-H "OpenAI-Organization: ${OPENAI_ORG}")
else
  hdr_org=()
fi

_api() {
  local method="$1"; shift
  local path="$1"; shift
  local url="${OPENAI_ADMIN_BASE_URL%/}${path}"
  curl -fsS -X "$method" "${hdr_auth[@]}" "${hdr_json[@]}" "${hdr_org[@]}" "$url" "$@"
}

# Return project id by exact name match; prints id or empty
admin_project_id_by_name() {
  local name="$1"
  local after="" page
  while :; do
    if [[ -n "$after" ]]; then
      page=$(_api GET "/v1/organization/projects?limit=100&after=${after}")
    else
      page=$(_api GET "/v1/organization/projects?limit=100")
    fi
    # Search for project name
    local id
    id=$(printf '%s' "$page" | jq -r --arg n "$name" '.data[] | select(.name == $n) | .id' | head -n1)
    if [[ -n "$id" && "$id" != "null" ]]; then
      printf '%s' "$id"
      return 0
    fi
    # Pagination
    after=$(printf '%s' "$page" | jq -r '.last_id // ""')
    [[ $(printf '%s' "$page" | jq -r '.has_more') == "true" ]] || break
  done
  return 0
}

# Create a project with given name; prints id
admin_create_project() {
  local name="$1"
  local resp
  resp=$(_api POST "/v1/organization/projects" --data "{\"name\":$(jq -Rn --arg n "$name" '$n')}")
  printf '%s' "$resp" | jq -r '.id'
}

# Create a service account under the project; prints api_key.value
admin_create_service_account_key() {
  local project_id="$1"; shift
  local name="$1"
  local resp key
  resp=$(_api POST "/v1/organization/projects/${project_id}/service_accounts" --data "{\"name\":$(jq -Rn --arg n "$name" '$n')}")
  key=$(printf '%s' "$resp" | jq -r '.api_key.value // empty')
  if [[ -z "$key" ]]; then
    echo "ERROR: Admin API did not return api_key.value" >&2
    return 2
  fi
  printf '%s' "$key"
}
