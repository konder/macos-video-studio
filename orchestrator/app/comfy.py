"""ComfyUI HTTP 客户端。Orchestrator 只经 HTTP 与 ComfyUI 交互(容器隔离,
不直读其文件系统 —— 见 docs/architecture.md §3)。"""
from __future__ import annotations

import time
import uuid
from urllib.parse import urlencode

import httpx

from .config import settings


class ComfyClient:
    def __init__(self, base_url: str | None = None):
        self.base_url = (base_url or settings.comfy_url).rstrip("/")
        self.client_id = uuid.uuid4().hex
        self._http = httpx.Client(timeout=60.0)
        self._object_info: dict | None = None

    def object_info(self, refresh: bool = False) -> dict:
        """全部节点 schema(缓存)。validate 的事实依据。"""
        if self._object_info is None or refresh:
            r = self._http.get(f"{self.base_url}/object_info")
            r.raise_for_status()
            self._object_info = r.json()
        return self._object_info

    def system_stats(self) -> dict:
        r = self._http.get(f"{self.base_url}/system_stats")
        r.raise_for_status()
        return r.json()

    def submit(self, prompt: dict) -> str:
        r = self._http.post(
            f"{self.base_url}/prompt",
            json={"prompt": prompt, "client_id": self.client_id},
        )
        r.raise_for_status()
        return r.json()["prompt_id"]

    def wait(self, prompt_id: str, timeout: float = 600.0, poll: float = 1.5) -> dict:
        """轮询 /history 直到该 prompt 完成,返回其历史记录。"""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            h = self._http.get(f"{self.base_url}/history/{prompt_id}").json()
            if prompt_id in h:
                return h[prompt_id]
            time.sleep(poll)
        raise TimeoutError(f"ComfyUI 执行超时: {prompt_id}")

    def view_url(self, image: dict) -> str:
        # image: {"filename", "subfolder", "type"}
        return f"{self.base_url}/view?" + urlencode(image)

    def download(self, image: dict) -> bytes:
        r = self._http.get(self.view_url(image))
        r.raise_for_status()
        return r.content
