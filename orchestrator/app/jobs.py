"""异步作业登记表(api-contract:run 返回 job_id,断线用 GET /jobs/{id} 拉回)。

后端在后台线程跑生成,作业状态写进内存登记表;客户端轮询 /jobs/{id} 或经 WS /events 收快照。
单用户自用,内存态足够(进程重启即失,符合 MVP)。
"""
from __future__ import annotations

import threading
import time
import uuid


class JobRegistry:
    def __init__(self) -> None:
        self._jobs: dict[str, dict] = {}
        self._lock = threading.Lock()

    def create(self, kind: str, project: str, total: int = 0, message: str = "排队中") -> str:
        jid = "job_" + uuid.uuid4().hex[:8]
        with self._lock:
            self._jobs[jid] = {
                "id": jid, "kind": kind, "project": project, "status": "queued",
                "progress": {"step": 0, "total": total}, "message": message,
                "events": [], "result": None, "error": None, "cost": 0.0,
                "created": time.time(), "updated": time.time(),
            }
        return jid

    def update(self, jid: str, **kw) -> None:
        with self._lock:
            j = self._jobs.get(jid)
            if j:
                j.update(kw)
                j["updated"] = time.time()

    def step(self, jid: str, message: str = "", inc: int = 1) -> None:
        with self._lock:
            j = self._jobs.get(jid)
            if j:
                j["progress"]["step"] = j["progress"].get("step", 0) + inc
                if message:
                    j["message"] = message
                    j["events"].append(message)
                j["updated"] = time.time()

    def event(self, jid: str, message: str) -> None:
        with self._lock:
            j = self._jobs.get(jid)
            if j:
                j["events"].append(message)
                j["message"] = message
                j["updated"] = time.time()

    def add_cost(self, jid: str, amount: float) -> None:
        with self._lock:
            j = self._jobs.get(jid)
            if j:
                j["cost"] = round(j.get("cost", 0.0) + amount, 4)
                j["updated"] = time.time()

    def get(self, jid: str) -> dict | None:
        with self._lock:
            j = self._jobs.get(jid)
            return dict(j) if j else None

    def list(self, project: str | None = None) -> list[dict]:
        with self._lock:
            return [dict(j) for j in self._jobs.values()
                    if not project or j["project"] == project]


JOBS = JobRegistry()
