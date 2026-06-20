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
