import argparse
import json
import os
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

import yaml

from orchestration.codex_mcp import propose_fix, apply_patch


@dataclass
class Step:
    id: str
    desc: str
    command: str
    transient: bool = False  # optional: retry with backoff on failure


def run_local(command: str, cwd: Path) -> Dict[str, str]:
    proc = subprocess.run(
        ["bash", "-lc", command],
        cwd=str(cwd),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env=os.environ.copy(),
        text=True,
    )
    return {"output": proc.stdout, "rc": str(proc.returncode)}


def summarize_failure(step: Step, output: str) -> str:
    head = output[-4000:]
    return (
        f"Step '{step.id}' failed: {step.desc}\n"
        f"Command: {step.command}\n"
        f"Last output (tail):\n{head}\n"
    )


def persist(run_dir: Path, step_id: str, suffix: str, content: str) -> None:
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / f"{step_id}.{suffix}").write_text(content, encoding="utf-8", errors="ignore")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Run quality chain with Codex-assisted fixes")
    p.add_argument("--chain", default="orchestration/chains/python_quality.yaml")
    p.add_argument("--repo", default=os.getcwd())
    p.add_argument("--dry-run", action="store_true", help="Only ask Codex for diff; do not apply")
    p.add_argument("--max-attempts", type=int, default=3, help="Retries for transient steps")
    p.add_argument("--backoff", type=float, default=2.0, help="Base backoff seconds (exponential)")
    p.add_argument("--runs-dir", default="runs", help="Directory to persist artifacts")
    return p.parse_args()


def main():
    args = parse_args()
    repo = Path(args.repo)
    chain_file = Path(args.chain)
    runs_root = Path(args.runs_dir)
    run_stamp = datetime.utcnow().strftime("%Y%m%d-%H%M%S")
    run_dir = runs_root / run_stamp

    if not chain_file.exists():
        print(f"Chain file not found: {chain_file}", file=sys.stderr)
        sys.exit(2)

    with open(chain_file, "r", encoding="utf-8") as f:
        cfg = yaml.safe_load(f)

    steps: List[Step] = []
    for s in cfg.get("steps", []):
        steps.append(Step(
            id=s["id"],
            desc=s.get("desc", s["id"]),
            command=s["command"],
            transient=bool(s.get("transient", False)),
        ))

    for idx, step in enumerate(steps, 1):
        print(f"\n== [{idx}/{len(steps)}] {step.id}: {step.desc} ==")

        attempt = 1
        while True:
            res = run_local(step.command, cwd=repo)
            rc = int(res["rc"])
            print(res["output"])  # stream for user visibility
            persist(run_dir, step.id + f".attempt{attempt}", "log", res["output"])

            if rc == 0:
                break

            # Retry transient steps
            if step.transient and attempt < args.max_attempts:
                sleep_s = args.backoff ** attempt
                print(f"Transient failure, retrying in {sleep_s:.1f}s (attempt {attempt+1}/{args.max_attempts})")
                time.sleep(sleep_s)
                attempt += 1
                continue

            # Non-transient or retries exhausted → ask Codex for patch
            fail_summary = summarize_failure(step, res["output"])
            print("-- Failure summary --\n" + fail_summary)
            persist(run_dir, step.id, "summary.txt", fail_summary)

            print("-- Asking Codex for a fix (diff) --")
            codex = propose_fix(repo_path=str(repo), failure_summary=fail_summary)
            persist(run_dir, step.id, "codex.out", codex["logs"])
            print(codex["logs"])  # show proposed diff or error

            if codex["exit_code"] == 0 and codex["logs"].strip().startswith("diff"):
                if args.dry_run:
                    print("Dry-run mode: not applying diff. Aborting after printing proposal.")
                    sys.exit(3)
                print("-- Applying proposed diff --")
                apply_rc = apply_patch(str(repo), codex["logs"])
                print(f"git apply rc={apply_rc}")
                if apply_rc == 0:
                    persist(run_dir, step.id, "applied.diff", codex["logs"])
                    print("-- Re-running failed step after patch --")
                    # loop continues; reset attempt for same step
                    attempt = 1
                    continue
                else:
                    print("Patch could not be applied. Aborting.")
                    sys.exit(1)
            else:
                print("Codex did not return a valid diff. Aborting.")
                sys.exit(1)

    print(f"\nAll steps passed. Artifacts in {run_dir}")


if __name__ == "__main__":
    main()

