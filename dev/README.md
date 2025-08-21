# OpenAI Codex Embeddings Orchestration (dev scaffold)

This dev/ workspace provides a runnable, local microservice scaffold to orchestrate:
- Accepting ingest requests (API)
- Enqueuing jobs (Redis Streams)
- Orchestrating and dispatching work (orchestrator)
- Spawning one-shot Codex runner containers to call OpenAI embeddings (supervisor)
- Upserting vectors to Qdrant

Services (docker-compose):
- api-gateway (FastAPI) → POST /ingest
- ingestion-router (placeholder for future normalization; not required in MVP)
- orchestrator → moves jobs from `embeddings.incoming` → `embeddings.claimed`
- supervisor → consumes `embeddings.claimed`, launches one-shot `codex-runner` containers, writes to Qdrant
- redis: Redis Streams broker
- qdrant: vector DB

Quick start (local compose)
1) Export secrets (do not commit):
   - OPENAI_API_KEY
   - Optionally QDRANT_API_KEY (if you enable Qdrant auth)

2) Launch
   make up

3) Ingest a sample
   curl -s http://localhost:8000/ingest \
     -H 'Content-Type: application/json' \
     -d '{
       "doc_id":"doc-001",
       "content":"Hello world, embeddings!",
       "model":"text-embedding-3-small",
       "collection":"embeddings__demo__text-embedding-3-small__v1",
       "metadata":{"source":"inline"}
     }' | jq

4) Observe logs
   make logs

5) Tear down
   make down

Notes
- The supervisor will attempt to run a one-shot container from the local image `codex-runner:latest`. Compose builds it from dev/runners/codex-runner/.
- For production, move to Kubernetes Jobs and add rate-limiting/backpressure.
- This is a scaffold for iteration: basic error handling and DLQ streams are prepared for extension.

