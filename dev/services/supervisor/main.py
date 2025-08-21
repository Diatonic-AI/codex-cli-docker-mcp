import os
import json
import tempfile
import subprocess
import sys
import time
from typing import List, Dict

import redis
import httpx

REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")
IN_STREAM = os.getenv("IN_STREAM", "embeddings.claimed")
GROUP = os.getenv("GROUP", "supervisors")
QDRANT_URL = os.getenv("QDRANT_URL", "http://localhost:6333")
DEFAULT_COLLECTION = os.getenv("DEFAULT_COLLECTION", "embeddings__demo__text-embedding-3-small__v1")
MODEL_NAME = os.getenv("MODEL_NAME", "text-embedding-3-small")
RUNNER_IMAGE = os.getenv("RUNNER_IMAGE", "codex-runner:latest")
DEFAULT_ALLOWED_DOMAINS = os.getenv("DEFAULT_ALLOWED_DOMAINS", "api.openai.com")

r = redis.Redis.from_url(REDIS_URL, decode_responses=True)

# Create consumer group if not exists
try:
    r.xgroup_create(IN_STREAM, GROUP, id="0-0", mkstream=True)
except redis.ResponseError as e:
    if "BUSYGROUP" not in str(e):
        raise


def docker_run_runner(input_path: str, output_path: str, allowed_domains: str | None = None, repo_path: str | None = None) -> int:
    env = {"OPENAI_API_KEY": os.getenv("OPENAI_API_KEY", "")}
    if not env["OPENAI_API_KEY"]:
        print("ERROR: OPENAI_API_KEY not set in supervisor environment", flush=True)
        return 20
    # Pass-through allowed domains hint (runner image may ignore; codex image would enforce)
    env_list = ["-e", "OPENAI_API_KEY", "-e", f"MODEL_NAME={MODEL_NAME}"]
    if allowed_domains:
        env_list += ["-e", f"OPENAI_ALLOWED_DOMAINS={allowed_domains}"]
    # Optional: mount repo_path read-only to allow per-repo config reads (not required by current runner)
    volume_args = ["-v", f"{input_path}:/work/input.json:ro", "-v", f"{output_path}:/work/output.json"]
    if repo_path:
        volume_args += ["-v", f"{repo_path}:{repo_path}:ro"]
    cmd = [
        "docker", "run", "--rm",
        *env_list,
        *volume_args,
        RUNNER_IMAGE,
        "python", "-m", "runner", "--model", MODEL_NAME, "--input", "/work/input.json", "--output", "/work/output.json"
    ]
    env_vars = os.environ.copy()
    env_vars.update(env)
    try:
        proc = subprocess.run(cmd, env=env_vars, capture_output=True, text=True, timeout=120)
        print(proc.stdout)
        if proc.returncode != 0:
            print(proc.stderr, file=sys.stderr)
        return proc.returncode
    except subprocess.TimeoutExpired:
        print("Runner timed out", file=sys.stderr)
        return 10


def ensure_collection(name: str, vector_size: int = 1536, distance: str = "Cosine") -> None:
    with httpx.Client(timeout=15.0) as client:
        r1 = client.get(f"{QDRANT_URL}/collections/{name}")
        if r1.status_code == 200:
            return
        payload = {
            "vectors": {"size": vector_size, "distance": distance}
        }
        r2 = client.put(f"{QDRANT_URL}/collections/{name}", json=payload)
        r2.raise_for_status()


def upsert_points(collection: str, points: List[Dict]) -> None:
    body = {
        "points": [{"id": p["id"], "vector": p["vector"], "payload": p["payload"]} for p in points]
    }
    with httpx.Client(timeout=30.0) as client:
        r3 = client.put(f"{QDRANT_URL}/collections/{collection}/points", json=body)
        r3.raise_for_status()


while True:
    resp = r.xreadgroup(GROUP, "supervisor-1", {IN_STREAM: ">"}, count=1, block=5000)
    if not resp:
        continue
    _, messages = resp[0]
    for msg_id, data in messages:
        envelope = json.loads(data["envelope"])  # type: ignore
        doc = envelope["doc"]
        text = doc.get("content") or f"URI:{doc.get('uri')}"
        job_id = envelope["job_id"]
        model = envelope.get("model", MODEL_NAME)
        collection = envelope.get("collection", DEFAULT_COLLECTION)
        repo_path = envelope.get("repo_path")
        allowed_domains = envelope.get("allowed_domains") or DEFAULT_ALLOWED_DOMAINS

        # Prepare runner IO files
        with tempfile.TemporaryDirectory() as tmpd:
            in_path = os.path.join(tmpd, "input.json")
            out_path = os.path.join(tmpd, "output.json")
            chunks = [{"chunk_id": 0, "text": text}]
            payload = {
                "doc_id": doc["doc_id"],
                "version": doc.get("version", str(int(time.time()))),
                "chunks": chunks,
                "metadata": doc.get("metadata", {}),
                "created_at_utc": envelope["created_at_utc"],
            }
            with open(in_path, "w") as f:
                json.dump(payload, f)

            rc = docker_run_runner(in_path, out_path, allowed_domains=allowed_domains, repo_path=repo_path)
            if rc != 0:
                r.xack(IN_STREAM, GROUP, msg_id)
                print(f"job {job_id} failed rc={rc}")
                continue

            with open(out_path) as f:
                result = json.load(f)
            points = result.get("points", [])

            # Ensure collection and upsert
            ensure_collection(collection, vector_size=3072 if model.endswith("large") else 1536)
            upsert_points(collection, points)
            print(f"job {job_id} upserted {len(points)} points into {collection}")
            r.xack(IN_STREAM, GROUP, msg_id)

