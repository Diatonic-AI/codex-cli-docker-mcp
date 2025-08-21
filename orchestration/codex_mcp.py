import os
import subprocess
import textwrap
from typing import Dict, Any

from runner import CodexRunner

# Minimal wrapper to prepare Codex prompts and dispatch work to the containerized CLI.
# This avoids embedding secrets and keeps runs ephemeral.

def propose_fix(repo_path: str, failure_summary: str, files_hint: str = "") -> Dict[str, Any]:
    """Ask Codex to propose a minimal diff to fix the described failure.
    Returns a dict with keys: {exit_code, logs} and lets the caller decide how to apply.
    """
    runner = CodexRunner()

    # Compose a prompt that is explicit and bounded.
    prompt = textwrap.dedent(f"""
    You are an assistant that proposes minimal, test-driven patches.
    Repository path (mounted at /workspace): {repo_path}

    Failure summary:
    {failure_summary}

    Relevant files (hints, may be partial):
    {files_hint}

    Task:
    - Propose a minimal set of changes to resolve the failure.
    - Respond with a machine-readable unified diff (git diff -U0 style) ONLY.
    - No prose. No comments. Diff must apply cleanly from repo root.
    """)

    # We assume codex CLI supports a 'prompt' subcommand that prints an answer to stdout.
    args = [
        "entrypoint.sh", "run",
        "prompt",
        "--format", "diff",
        "--stdin"
    ]

    # Write prompt to a temp file bound into /workspace/job if you want; here we pipe via bash -lc
    # For portability, we pass via STDIN using bash -lc -c.
    code, logs = runner.run(
        args=["bash", "-lc", "cat <<'EOF' | entrypoint.sh run prompt --format diff --stdin\n" + prompt + "\nEOF"],
        host_job_dir=repo_path,
        entrypoint=None,
        timeout_sec=180,
    )
    return {"exit_code": code, "logs": logs}


def apply_patch(repo_path: str, diff_text: str) -> int:
    """Apply a unified diff in the host repo using 'git apply --index'. Returns exit code."""
    env = os.environ.copy()
    proc = subprocess.run(
        ["bash", "-lc", "git -C "$REPO" apply --index -"],
        input=diff_text.encode("utf-8"),
        env={**env, "REPO": repo_path},
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    return proc.returncode

