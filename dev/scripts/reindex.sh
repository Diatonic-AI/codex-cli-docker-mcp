#!/usr/bin/env bash
set -euo pipefail
# Placeholder for future corpus reindexing logic
# Usage: ./reindex.sh <dir>

dir=${1:-}
if [[ -z "$dir" ]]; then
  echo "Usage: $0 <dir>" >&2
  exit 2
fi
find "$dir" -type f -name '*.md' -o -name '*.txt' | while read -r f; do
  doc_id=$(basename "$f")
  content=$(tr -d '\r' < "$f" | sed 's/"/\"/g')
  curl -s http://localhost:8000/ingest \
    -H 'Content-Type: application/json' \
    -d "{\"doc_id\":\"$doc_id\",\"content\":\"$content\"}" | jq .
  sleep 0.1
done

