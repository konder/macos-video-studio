import os
from dataclasses import dataclass


@dataclass
class Settings:
    comfy_url: str = os.environ.get("COMFY_URL", "http://10.10.10.2:8188")
    projects_dir: str = os.environ.get("PROJECTS_DIR", "./projects")
    model: str = os.environ.get("AGENT_MODEL", "")
    # Agent 经 LiteLLM 网关（OpenAI 兼容）调用，底层模型可自由替换。
    # 配置走 orchestrator 专属变量并显式传给 SDK，绝不改全局 ANTHROPIC_*，
    # 以免影响同机的 Claude Code。
    litellm_base_url: str = os.environ.get("LITELLM_BASE_URL", "http://10.10.10.5:4000")
    litellm_api_key: str = os.environ.get("LITELLM_API_KEY", "")


settings = Settings()


# 本地后端注册（architecture §3 / open-questions A6 的两层算力）。
# caps = 能力标签；vram_gb = 显存；latency = 交互优先级(fast 优先于 slow)。
# Orchestrator 按「能力 + 显存 + 延迟」在后端间路由（见 backends.py）。
BACKENDS = [
    {
        "name": "local-5090",
        "kind": "comfy",
        "url": os.environ.get("COMFY_URL", "http://10.10.10.2:8188"),
        "vram_gb": 32,
        "latency": "fast",
        "caps": ["txt2img", "edit", "i2v", "upscale"],
    },
    {
        "name": "local-dgx",
        "kind": "comfy",
        "url": os.environ.get("DGX_COMFY_URL", "http://10.10.10.5:8188"),
        "vram_gb": 128,
        "latency": "slow",
        "caps": ["txt2img", "edit", "i2v", "train", "bigmodel"],
    },
    # 云后端(即梦/Vidu/…) 预留, M6 接通: {"name":"cloud-...","kind":"cloud",...}
]

