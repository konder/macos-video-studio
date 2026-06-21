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

import json
import os
import time
import urllib.error
import urllib.request
from dataclasses import dataclass


class CloudNotConfigured(RuntimeError):
    pass


def bailian_image(prompt: str, size: str = "1328*1328", model: str = "qwen-image-2.0-pro",
                  ref_paths: list[str] | None = None) -> bytes:
    """百炼图像生成(经 LiteLLM 网关 pass-through 的 DashScope multimodal-generation)。
    模型:qwen-image-2.0 / qwen-image-2.0-pro / wan2.7-image(-pro)。
    ref_paths:参考图(本地路径,转 base64 作 image 输入,用于锁角色长相/服装)。返回图片字节。"""
    import base64
    from .config import settings
    base = settings.litellm_base_url.rstrip("/")
    url = f"{base}/token-plan/aigc/multimodal-generation/generation"
    content: list[dict] = []
    for p in (ref_paths or [])[:3]:
        try:
            with open(p.lstrip("./") if not os.path.isabs(p) else p, "rb") as f:
                content.append({"image": "data:image/png;base64," + base64.b64encode(f.read()).decode()})
        except Exception:  # noqa: BLE001
            pass
    content.append({"text": prompt})
    body = {"model": model, "input": {"messages": [{"role": "user", "content": content}]},
            "parameters": {"size": size}}
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST", headers={
        "Authorization": f"Bearer {settings.litellm_api_key}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            d = json.loads(r.read())
    except urllib.error.HTTPError as e:
        raise CloudNotConfigured(f"百炼图像 {e.code}: {e.read().decode(errors='replace')[:300]}")
    img_url = (((d.get("output") or {}).get("choices") or [{}])[0].get("message", {}).get("content") or [{}])[0].get("image")
    if not img_url:
        raise CloudNotConfigured(f"百炼未返回图: {str(d)[:300]}")
    with urllib.request.urlopen(img_url, timeout=180) as r:
        return r.read()


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
      VOLCANO_API_KEY  火山方舟 ARK key(豆包 Seedance 视频)。endpoint 默认 /api/v3,
                       model 默认 doubao-seedance-2-0-260128(可用 VOLCANO_ENDPOINT/VOLCANO_MODEL 覆盖)。
                       注意:视频生成走 /api/v3(不是 /api/plan/v3 agentplan);需在火山控制台**开通该模型**。
      DASHSCOPE_API_KEY  Qwen 通义万相(DashScope)。
    partner 节点路径不在此(key 在 ComfyUI),用 i2v_cloud 配方走 run_ir。
    """
    provs: dict[str, CloudProvider] = {}
    vkey = os.environ.get("VOLCANO_API_KEY", "")
    if vkey:
        provs["volcano"] = CloudProvider(
            "volcano",
            os.environ.get("VOLCANO_ENDPOINT", "https://ark.cn-beijing.volces.com/api/v3"),
            vkey, kind="direct")
    dkey = os.environ.get("DASHSCOPE_API_KEY", "")
    if dkey:
        provs["dashscope"] = CloudProvider(
            "dashscope", os.environ.get("DASHSCOPE_ENDPOINT", ""), dkey, kind="direct")
    return provs


def get_volcano() -> "VolcanoArkAdapter":
    """从 env 构造火山 Agent Plan 适配器。需 **Agent Plan 专属 API Key**。

    VOLCANO_API_KEY  Agent Plan 专属 key(非 Coding/普通 key)
    VOLCANO_ENDPOINT 默认 https://ark.cn-beijing.volces.com/api/plan/v3(含 /plan)
    VOLCANO_MODEL    默认 doubao-seedance-1.5-pro(本账号已开通可用;seedance-2.0/2.0-fast
                     虽是 Agent Plan 模型,但本账号未开通→ UnsupportedModel,开通后可切)
    """
    key = os.environ.get("VOLCANO_API_KEY", "")
    if not key:
        raise CloudNotConfigured("缺少 VOLCANO_API_KEY(Agent Plan 专属 key)")
    return VolcanoArkAdapter(
        os.environ.get("VOLCANO_ENDPOINT", "https://ark.cn-beijing.volces.com/api/plan/v3"),
        key, model=os.environ.get("VOLCANO_MODEL", "doubao-seedance-1.5-pro"))


class VolcanoArkAdapter:
    """火山方舟 ARK 视频生成(豆包 Seedance)适配器。异步:创建任务→轮询→取 video_url。

    endpoint 例: https://ark.cn-beijing.volces.com/api/v3 (或 .../api/plan/v3)。
    认证: Authorization: Bearer <api_key>。图片仅接受**外部可达 URL**(不收 base64)。
    """

    def __init__(self, endpoint: str, api_key: str, model: str = "doubao-seedance-2.0"):
        # Agent Plan: endpoint 含 /plan(https://ark.cn-beijing.volces.com/api/plan/v3),
        # model="doubao-seedance-2.0",且**必须用 Agent Plan 专属 API Key**
        # (普通/Coding Plan key 会报 UnsupportedModel: does not support the agent plan feature)。
        self.endpoint = endpoint.rstrip("/")
        self.api_key = api_key
        self.model = model

    def _req(self, method: str, path: str, body: dict | None = None) -> dict:
        url = f"{self.endpoint}{path}"
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method, headers={
            "Authorization": f"Bearer {self.api_key}", "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.loads(r.read())
        except urllib.error.HTTPError as e:
            raise CloudNotConfigured(f"火山 {method} {path} {e.code}: {e.read().decode(errors='replace')[:300]}")

    def create_task(self, prompt: str, image_url: str | None = None,
                    image_role: str | None = None, ratio: str = "adaptive",
                    duration: int = 5, generate_audio: bool = False) -> str:
        content: list[dict] = [{"type": "text", "text": prompt}]
        if image_url:
            img: dict = {"type": "image_url", "image_url": {"url": image_url}}
            if image_role:  # first_frame/last_frame/reference_image;官方 i2v 示例可省
                img["role"] = image_role
            content.append(img)
        body = {"model": self.model, "content": content, "ratio": ratio,
                "duration": duration, "watermark": False, "generate_audio": generate_audio}
        res = self._req("POST", "/contents/generations/tasks", body)
        tid = res.get("id") or res.get("task_id")
        if not tid:
            raise CloudNotConfigured(f"火山未返回 task id: {res}")
        return tid

    def poll(self, task_id: str, timeout: float = 600, interval: float = 5) -> dict:
        t0 = time.monotonic()
        while time.monotonic() - t0 < timeout:
            res = self._req("GET", f"/contents/generations/tasks/{task_id}")
            st = res.get("status")
            if st == "succeeded":
                return res
            if st in ("failed", "expired"):
                raise CloudNotConfigured(f"火山任务 {st}: {res.get('error') or res}")
            time.sleep(interval)
        raise CloudNotConfigured(f"火山任务超时: {task_id}")

    def i2v(self, image_url: str, prompt: str, **params) -> dict:
        """图生视频:返回 {video_url, task_id}。image_url 必须外部可达。"""
        tid = self.create_task(prompt, image_url=image_url, **params)
        res = self.poll(tid)
        return {"task_id": tid, "video_url": res.get("content", {}).get("video_url")}


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
