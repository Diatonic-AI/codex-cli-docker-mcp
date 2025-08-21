import os
import sys
import json
import time
import hashlib
from typing import List
import httpx

# Usage:
# python -m runner --model text-embedding-3-small --input /work/input.json --output /work/output.json

def parse_args(args: List[str]):
    model = os.environ.get("MODEL_NAME", "text-embedding-3-small")
    input_path = None
    output_path = None
    i = 0
    while i < len(args):
        if args[i] == "--model":
            model = args[i+1]
            i += 2
        elif args[i] == "--input":
            input_path = args[i+1]
            i += 2
        elif args[i] == "--output":
            output_path = args[i+1]
            i += 2
        else:
            i += 1
    return model, input_path, output_path


def embed(model: str, texts: List[str]):
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        print("OPENAI_API_KEY missing", file=sys.stderr)
        sys.exit(20)
    headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
    body = {"model": model, "input": texts}
    backoff = 1.0
    for attempt in range(5):
        try:
            r = httpx.post("https://api.openai.com/v1/embeddings", headers=headers, json=body, timeout=30.0)
            if r.status_code == 429:
                ra = r.headers.get("Retry-After")
                sleep_s = float(ra) if ra else min(8.0, backoff)
                time.sleep(sleep_s)
                backoff *= 2
                continue
            r.raise_for_status()
            data = r.json()["data"]
            return [d["embedding"] for d in data]
        except Exception as e:
            if attempt == 4:
                print(f"embedding error: {e}", file=sys.stderr)
                sys.exit(10)
            time.sleep(min(8.0, backoff))
            backoff *= 2


def main():
    model, input_path, output_path = parse_args(sys.argv[1:])
    if not input_path or not output_path:
        print("--input and --output required", file=sys.stderr)
        sys.exit(20)
    with open(input_path) as f:
        payload = json.load(f)
    texts = [c["text"] for c in payload["chunks"]]
    vecs = embed(model, texts)
    points = []
    for c, v in zip(payload["chunks"], vecs):
        points.append({
            "id": f"{payload['doc_id']}:{payload['version']}:{c['chunk_id']}",
            "vector": v,
            "payload": {
                "doc_id": payload["doc_id"],
                "version": payload["version"],
                "chunk_id": c["chunk_id"],
                "model": model,
                "hash_sha256": hashlib.sha256(c["text"].encode()).hexdigest(),
                "created_at_utc": payload.get("created_at_utc"),
                "metadata": payload.get("metadata", {}),
            }
        })
    with open(output_path, "w") as f:
        json.dump({"points": points}, f)
    print(json.dumps({"status": "ok", "count": len(points)}))

if __name__ == "__main__":
    main()

