import os
from dataclasses import dataclass


@dataclass
class Settings:
    comfy_url: str = os.environ.get("COMFY_URL", "http://10.10.10.2:8188")
    projects_dir: str = os.environ.get("PROJECTS_DIR", "./projects")
    model: str = os.environ.get("AGENT_MODEL", "claude-opus-4-8")
    # ANTHROPIC_API_KEY is read by the anthropic SDK directly from the env.


settings = Settings()
