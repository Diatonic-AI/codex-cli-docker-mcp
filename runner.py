import json
import os
import time
from typing import Dict, List, Optional, Tuple

import docker
from docker.errors import APIError, NotFound


class CodexRunner:
    def __init__(
        self,
        image: str = "local/codex-cli:latest",
        workdir: str = "/workspace",
        default_env: Optional[Dict[str, str]] = None,
        remove: bool = True,
        network_mode: Optional[str] = None,
        mem_limit: str = "2g",
        nano_cpus: int = 2_000_000_000,  # 2 vCPU
        pids_limit: int = 512,
        user: str = "node",
        labels: Optional[Dict[str, str]] = None,
    ) -> None:
        self.client = docker.from_env()
        self.image = image
        self.workdir = workdir
        self.default_env = default_env or {}
        self.remove = remove
        self.network_mode = network_mode
        self.mem_limit = mem_limit
        self.nano_cpus = nano_cpus
        self.pids_limit = pids_limit
        self.user = user
        self.labels = labels or {"app": "codex-cli"}

    def run(
        self,
        args: List[str],
        host_job_dir: Optional[str] = None,
        extra_env: Optional[Dict[str, str]] = None,
        timeout_sec: int = 300,
        entrypoint: Optional[List[str]] = None,
        name: Optional[str] = None,
    ) -> Tuple[int, str]:
        """
        Run a codex job non-interactively. Returns (exit_code, logs).
        Args are passed to the container's command. If your image keeps
        ENTRYPOINT as entrypoint.sh, prefer entrypoint=["bash","-lc"] and a
        full command like ["entrypoint.sh", "run", "--flag", ...] or override
        entrypoint to run codex directly.
        """
        env = {**self.default_env, **(extra_env or {})}
        volumes = {}
        if host_job_dir:
            volumes[os.path.abspath(host_job_dir)] = {
                "bind": f"{self.workdir}/job",
                "mode": "rw",
            }

        cmd = args

        container = None
        start = time.time()
        try:
            container = self.client.containers.run(
                image=self.image,
                command=cmd,
                entrypoint=entrypoint,  # may be None to use image default
                working_dir=self.workdir,
                user=self.user,
                detach=True,
                remove=self.remove,
                network_mode=self.network_mode,
                volumes=volumes,
                environment=env,
                tty=False,
                stdin_open=False,
                mem_limit=self.mem_limit,
                nano_cpus=self.nano_cpus,
                pids_limit=self.pids_limit,
                security_opt=["no-new-privileges:true"],
                read_only=False,
                labels=self.labels,
                name=name,
            )

            while True:
                if (time.time() - start) > timeout_sec:
                    try:
                        container.kill()
                    except Exception:
                        pass
                    raise TimeoutError(f"codex job timed out after {timeout_sec}s")
                container.reload()
                if container.status in ("exited", "dead"):
                    break
                time.sleep(0.25)

            logs = container.logs(stdout=True, stderr=True, tail=10000)
            out = logs.decode("utf-8", errors="replace")
            code = container.wait().get("StatusCode", 1)
            return code, out
        except (APIError, NotFound) as e:
            return 1, f"docker API error: {e}"
        finally:
            if container is not None and not self.remove:
                try:
                    container.reload()
                except Exception:
                    pass

    @staticmethod
    def as_json(code: int, logs: str, meta: Optional[Dict[str, str]] = None) -> str:
        payload = {"exit_code": code, "logs": logs}
        if meta:
            payload["meta"] = meta
        return json.dumps(payload, ensure_ascii=False)


if __name__ == "__main__":
    # Example: run codex with the new non-interactive subcommand
    runner = CodexRunner(default_env={
        # Keep proxies empty unless needed at runtime
        "HTTP_PROXY": os.getenv("HTTP_PROXY", ""),
        "HTTPS_PROXY": os.getenv("HTTPS_PROXY", ""),
        "NO_PROXY": os.getenv("NO_PROXY", "127.0.0.1,localhost"),
    })

    # Invoke entrypoint.sh run --help inside the container
    code, logs = runner.run(
        args=["entrypoint.sh", "run", "--help"],
        host_job_dir=None,
        entrypoint=["bash", "-lc"],
        timeout_sec=60,
        name=None,
    )
    print(CodexRunner.as_json(code, logs))

