from __future__ import annotations
import os
import json
import uuid
import time
from typing import Any, Dict

import redis
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")
QUEUE_STREAM = os.getenv("QUEUE_STREAM", "embeddings.incoming")

r = redis.Redis.from_url(REDIS_URL, decode_responses=True)
app = FastAPI(title="Codex Embeddings API")

class IngestRequest(BaseModel):
    doc_id: str
    content: str | None = None
    uri: str | None = None
    model: str = Field(default="text-embedding-3-small")
    collection: str = Field(default="embeddings__demo__text-embedding-3-small__v1")
    metadata: Dict[str, Any] = Field(default_factory=dict)
    version: str = Field(default_factory=lambda: str(int(time.time())))
    repo_path: str | None = Field(default=None, description="Absolute host path to repo root for per-repo config/isolation")
    allowed_domains: str | None = Field(default="api.openai.com", description="Space-separated allowlist for network egress")

class IngestResponse(BaseModel):
    job_id: str
    stream: str

@app.post("/ingest", response_model=IngestResponse)
def ingest(req: IngestRequest):
    if not (req.content or req.uri):
        raise HTTPException(400, "Either content or uri must be provided")
    job_id = str(uuid.uuid4())
    envelope = {
        "job_id": job_id,
        "created_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "source": "api",
        "model": req.model,
        "collection": req.collection,
        "repo_path": req.repo_path,
        "allowed_domains": req.allowed_domains,
        "doc": {
            "doc_id": req.doc_id,
            "content": req.content,
            "uri": req.uri,
            "metadata": req.metadata,
            "version": req.version,
            "content_type": "text/plain",
        },
    }
    r.xadd(QUEUE_STREAM, {"envelope": json.dumps(envelope)}, maxlen=10000, approximate=True)
    return IngestResponse(job_id=job_id, stream=QUEUE_STREAM)

@app.get("/healthz")
def healthz():
    try:
        r.ping()
        return {"status": "ok"}
    except Exception as e:
        raise HTTPException(500, str(e))

