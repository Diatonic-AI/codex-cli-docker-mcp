#!/usr/bin/env bash
# OpenAI Admin API: Certificates management helper
# Uses $OPENAI_ADMIN_KEY (never stored) and $OPENAI_ADMIN_BASE_URL (default https://api.openai.com)
# Requires: curl, jq
set -euo pipefail

: "${OPENAI_ADMIN_BASE_URL:=https://api.openai.com}"
: "${OPENAI_ADMIN_KEY:?Set OPENAI_ADMIN_KEY in your environment (do NOT store it in files)}"

_hdr_auth=("Authorization: Bearer ${OPENAI_ADMIN_KEY}")
_hdr_json=("Content-Type: application/json")

_api() {
  local method="$1"; shift
  local path="$1"; shift
  local url="${OPENAI_ADMIN_BASE_URL%/}${path}"
  curl -fsS -X "$method" -H "${_hdr_auth[@]}" -H "${_hdr_json[@]}" "$url" "$@"
}

usage() {
  cat <<'EOF'
Usage: openai-admin-certs.sh <command> [options]
Commands (organization scope):
  list                           List org certificates
  upload [--name NAME] [--pem-file FILE]  Upload a PEM certificate (use --pem-file or stdin)
  get <cert_id> [--include-content]       Get certificate (optionally include PEM content)
  rename <cert_id> <new_name>             Rename certificate
  delete <cert_id>                        Delete certificate (must be inactive)
  activate <cert_id> [<cert_id> ...]      Activate up to 10 certificates at org level
  deactivate <cert_id> [<cert_id> ...]    Deactivate up to 10 certificates at org level

Project scope:
  project-list <project_id>               List project certificates
  project-activate <project_id> <ids...>  Activate up to 10 certificates for the project
  project-deactivate <project_id> <ids...> Deactivate up to 10 certificates for the project

Environment:
  OPENAI_ADMIN_KEY (required), OPENAI_ADMIN_BASE_URL (optional)
EOF
}

cmd_list() {
  local after=""; local limit="${LIMIT:-20}"; local order="${ORDER:-desc}"
  _api GET "/v1/organization/certificates?limit=${limit}&order=${order}"
}

cmd_upload() {
  local name="" pem_file="" pem_content=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2;;
      --pem-file) pem_file="$2"; shift 2;;
      -h|--help) usage; exit 0;;
      *) echo "Unknown option: $1" >&2; usage; exit 2;;
    esac
  done
  if [[ -n "$pem_file" ]]; then
    pem_content=$(cat "$pem_file")
  else
    # Read from stdin (no echo)
    pem_content=$(cat)
  fi
  # Do not print pem_content
  local data
  if [[ -n "$name" ]]; then
    data=$(jq -n --arg c "$pem_content" --arg n "$name" '{certificate:$c, name:$n}')
  else
    data=$(jq -n --arg c "$pem_content" '{certificate:$c}')
  fi
  _api POST "/v1/organization/certificates" --data "$data"
}

cmd_get() {
  local cert_id="$1"; shift || true
  local include_content=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --include-content) include_content=true; shift;;
      *) echo "Unknown option: $1" >&2; usage; exit 2;;
    esac
  done
  if $include_content; then
    _api GET "/v1/organization/certificates/${cert_id}?include[]=content"
  else
    _api GET "/v1/organization/certificates/${cert_id}"
  fi
}

cmd_rename() {
  local cert_id="$1"; local new_name="$2"
  local body
  body=$(jq -n --arg n "$new_name" '{name:$n}')
  _api POST "/v1/organization/certificates/${cert_id}" --data "$body"
}

cmd_delete() {
  local cert_id="$1"
  _api DELETE "/v1/organization/certificates/${cert_id}"
}

cmd_activate() {
  if [[ $# -lt 1 ]]; then echo "Provide at least one cert_id" >&2; exit 2; fi
  local body
  body=$(jq -n --argjson arr "$(printf '%s\n' "$@" | jq -R . | jq -s .)" '{data:$arr}')
  _api POST "/v1/organization/certificates/activate" --data "$body"
}

cmd_deactivate() {
  if [[ $# -lt 1 ]]; then echo "Provide at least one cert_id" >&2; exit 2; fi
  local body
  body=$(jq -n --argjson arr "$(printf '%s\n' "$@" | jq -R . | jq -s .)" '{data:$arr}')
  _api POST "/v1/organization/certificates/deactivate" --data "$body"
}

cmd_project_list() {
  local project_id="$1"
  _api GET "/v1/organization/projects/${project_id}/certificates"
}

cmd_project_activate() {
  local project_id="$1"; shift
  if [[ $# -lt 1 ]]; then echo "Provide at least one cert_id" >&2; exit 2; fi
  local body
  body=$(jq -n --argjson arr "$(printf '%s\n' "$@" | jq -R . | jq -s .)" '{data:$arr}')
  _api POST "/v1/organization/projects/${project_id}/certificates/activate" --data "$body"
}

cmd_project_deactivate() {
  local project_id="$1"; shift
  if [[ $# -lt 1 ]]; then echo "Provide at least one cert_id" >&2; exit 2; fi
  local body
  body=$(jq -n --argjson arr "$(printf '%s\n' "$@" | jq -R . | jq -s .)" '{data:$arr}')
  _api POST "/v1/organization/projects/${project_id}/certificates/deactivate" --data "$body"
}

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    list) cmd_list "$@";;
    upload) cmd_upload "$@";;
    get) [[ $# -ge 1 ]] || { echo "cert_id required" >&2; exit 2; }; cmd_get "$@";;
    rename) [[ $# -ge 2 ]] || { echo "cert_id and new_name required" >&2; exit 2; }; cmd_rename "$@";;
    delete) [[ $# -ge 1 ]] || { echo "cert_id required" >&2; exit 2; }; cmd_delete "$@";;
    activate) [[ $# -ge 1 ]] || { echo "at least one cert_id required" >&2; exit 2; }; cmd_activate "$@";;
    deactivate) [[ $# -ge 1 ]] || { echo "at least one cert_id required" >&2; exit 2; }; cmd_deactivate "$@";;
    project-list) [[ $# -ge 1 ]] || { echo "project_id required" >&2; exit 2; }; cmd_project_list "$@";;
    project-activate) [[ $# -ge 2 ]] || { echo "project_id and cert_ids required" >&2; exit 2; }; cmd_project_activate "$@";;
    project-deactivate) [[ $# -ge 2 ]] || { echo "project_id and cert_ids required" >&2; exit 2; }; cmd_project_deactivate "$@";;
    -h|--help|help|"") usage;;
    *) echo "Unknown command: $cmd" >&2; usage; exit 2;;
  esac
}

main "$@"
