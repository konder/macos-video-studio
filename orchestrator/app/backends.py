"""后端注册表 + 路由（architecture §3 / open-questions A6）。

两层本地算力 + 云(预留)：Orchestrator 按「能力 + 显存 + 延迟」把任务路由到合适后端。
- 交互式图像 / edit / i2v 草稿 → 优先 fast(5090)。
- 训练 / 放不进 32G 的大模型 / 批处理 → DGX(大显存)。
- 本地不具备 → 云(M6)。

每个 comfy 后端持有一个 ComfyClient(各自 HTTP 端点)。
"""
from __future__ import annotations

from .comfy import ComfyClient
from .config import BACKENDS


class Backend:
    def __init__(self, spec: dict):
        self.name = spec["name"]
        self.kind = spec["kind"]
        self.url = spec["url"]
        self.vram_gb = spec.get("vram_gb", 0)
        self.latency = spec.get("latency", "slow")
        self.caps = set(spec.get("caps", []))
        self.client: ComfyClient | None = (
            ComfyClient(base_url=self.url) if self.kind == "comfy" else None
        )

    def reachable(self) -> bool:
        if self.kind != "comfy" or self.client is None:
            return False
        try:
            self.client.system_stats()
            return True
        except Exception:
            return False

    def info(self) -> dict:
        return {
            "name": self.name, "kind": self.kind, "url": self.url,
            "vram_gb": self.vram_gb, "latency": self.latency, "caps": sorted(self.caps),
        }


class NoBackendError(RuntimeError):
    pass


class BackendRegistry:
    def __init__(self, specs: list[dict] | None = None):
        self.backends = [Backend(s) for s in (specs or BACKENDS)]

    def get(self, name: str) -> Backend:
        for b in self.backends:
            if b.name == name:
                return b
        raise NoBackendError(f"未知后端: {name}")

    def list(self) -> list[dict]:
        return [b.info() for b in self.backends]

    def route(
        self, capability: str, min_vram_gb: int = 0, prefer_latency: str = "fast"
    ) -> Backend:
        """挑一个满足 能力 + 显存 的后端；同等条件下按 prefer_latency 优先。

        prefer_latency='fast' → 交互任务优先 5090；训练/大模型传 'slow' 或靠 min_vram 自然落 DGX。
        """
        cand = [
            b for b in self.backends
            if b.kind == "comfy" and capability in b.caps and b.vram_gb >= min_vram_gb
        ]
        if not cand:
            raise NoBackendError(
                f"无后端满足 capability={capability} vram>={min_vram_gb}"
            )
        # fast 优先级：fast=0, slow=1；prefer_latency='slow' 则反过来
        def key(b: Backend):
            fast_first = 0 if b.latency == "fast" else 1
            if prefer_latency == "slow":
                fast_first = 1 - fast_first
            return (fast_first, -b.vram_gb)
        cand.sort(key=key)
        return cand[0]
