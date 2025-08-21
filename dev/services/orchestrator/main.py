import os
import json
import time
import random
from typing import Optional

import redis

REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")
IN_STREAM = os.getenv("IN_STREAM", "embeddings.incoming")
OUT_STREAM = os.getenv("OUT_STREAM", "embeddings.claimed")
GROUP = os.getenv("GROUP", "orchestrators")
RPS_LIMIT = int(os.getenv("RPS_LIMIT", "60"))

r = redis.Redis.from_url(REDIS_URL, decode_responses=True)

# Create consumer group if not exists
try:
    r.xgroup_create(IN_STREAM, GROUP, id="0-0", mkstream=True)
except redis.ResponseError as e:
    if "BUSYGROUP" not in str(e):
        raise

last_tick = 0.0

while True:
    resp = r.xreadgroup(GROUP, "orchestrator-1", {IN_STREAM: ">"}, count=1, block=5000)
    if not resp:
        continue
    _, messages = resp[0]
    for msg_id, data in messages:
        envelope = json.loads(data["envelope"])  # type: ignore
        now = time.time()
        # simple rate limiting (RPS)
        wait = max(0.0, (1.0 / max(1, RPS_LIMIT)) - (now - last_tick))
        if wait > 0:
            time.sleep(wait)
        last_tick = time.time()

        # forward to OUT_STREAM with same envelope
        r.xadd(OUT_STREAM, {"envelope": json.dumps(envelope)}, maxlen=10000, approximate=True)
        r.xack(IN_STREAM, GROUP, msg_id)

