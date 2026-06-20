"""云接入(阶段6,open-questions A3):reference-to-video / i2v 的云后端。

两条路:
  A) ComfyUI partner 节点(Kling/Vidu/Runway/Luma/Veo,装机已带)——**节点无 key 输入,
     key 配在 ComfyUI**(Comfy-Org API nodes)。orchestrator 把它当一个云 i2v 配方(图节点)调用,
     走现有 run_ir,无需本模块的 endpoint。这是国际厂商的首选路径(A3:直接作图节点)。
  B) 直连适配器(即梦/火山、Qwen/DashScope)——无 partner 节点,orchestrator 直接调云 REST:
     submit → poll → download。需 endpoint + key(火山可能 AK/SK),配在 env。本模块实现 B 的通用骨架。

未配置凭据时,调用会抛 CloudNotConfigured(清晰报错,不静默失败)。
"""
from __future__ import annotations

import os
import time
from dataclasses import dataclass


class CloudNotConfigured(RuntimeError):
    pass


@dataclass
class CloudProvider:
    name: str
    endpoint: str
    api_key: str
    kind: str = "direct"  # direct(REST 适配器) | partner(ComfyUI 节点)

    @property
    def configured(self) -> bool:
        return self.kind == "partner" or bool(self.endpoint and self.api_key)


def load_providers() -> dict[str, CloudProvider]:
    """从 env 读云 provider 配置(直连模式)。未配置则为空 → 云后端处于"未激活"。

    约定 env:
      JIMENG_ENDPOINT / JIMENG_API_KEY   即梦(火山引擎)
      DASHSCOPE_ENDPOINT / DASHSCOPE_API_KEY  Qwen 通义万相
    partner 节点路径不在此(key 在 ComfyUI),用 i2v_cloud 配方走 run_ir。
    """
    provs: dict[str, CloudProvider] = {}
    for name, ep_env, key_env in [
        ("jimeng", "JIMENG_ENDPOINT", "JIMENG_API_KEY"),
        ("dashscope", "DASHSCOPE_ENDPOINT", "DASHSCOPE_API_KEY"),
    ]:
        ep, key = os.environ.get(ep_env, ""), os.environ.get(key_env, "")
        if ep or key:
            provs[name] = CloudProvider(name, ep, key, kind="direct")
    return provs


class CloudVideoAdapter:
    """直连云 i2v/reference-to-video 的通用骨架(submit→poll→download)。

    具体 provider 的请求/响应字段差异较大,activate 时按其 API 文档实现 _submit/_parse;
    这里给出统一外形与生命周期,未配置即抛错。
    """

    def __init__(self, provider: CloudProvider):
        self.p = provider

    def i2v(self, image_bytes: bytes, prompt: str, **params) -> bytes:
        if not self.p.configured:
            raise CloudNotConfigured(
                f"云 provider '{self.p.name}' 未配置 endpoint/key —— 阶段6 需提供凭据后激活")
        # 接到真实 provider 时实现:
        #   task_id = self._submit(image_bytes, prompt, params)   # POST endpoint + key
        #   url = self._poll(task_id)                              # 轮询直到完成
        #   return self._download(url)
        raise NotImplementedError(
            f"provider '{self.p.name}' 直连适配器待按其 API 实现(submit/poll/download)")
