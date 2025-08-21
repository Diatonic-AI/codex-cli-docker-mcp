# Orchestration for Codex MCP tool calls and quality gates

This is a minimal, extensible scaffold to coordinate Codex CLI (via the Docker container) with a set of deterministic quality gates. The intent is to run:

- Lint/format (ruff/black)
- Type-check (mypy or pyright)
- Unit tests + coverage (pytest)
- Docs build check (sphinx/mkdocs)
- Security checks (bandit, pip-audit)
- Optional: container build, trivy scan

On failures, the orchestrator will summarize evidence and ask Codex to propose targeted patches, then re-validate.

Directory
- chains/python_quality.yaml — ordered steps and commands (extensible)
- codex_mcp.py — wrapper to invoke codex via the container (uses runner.py)
- pipelines.py — loads a chain, executes steps, and loops with Codex fixes on failure

Safety & notes
- No secrets are embedded. If Codex needs credentials, provide them via Docker secrets or env variables.
- Steps are intended to be deterministic and run locally; adjust tools/commands to your project.
- This scaffold is a starting point; expand per your repo’s language/stack.

