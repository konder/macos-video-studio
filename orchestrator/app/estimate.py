"""耗时/费用预估(api-contract:POST /graphs/estimate;pipeline:云调用先预估→再确认→计费)。

本地:按配方历史计时给粗估,无现金成本。云:按时长 × 单价(env 可调)。估算用于费用闸:
客户端在云调用前展示 estimate,用户确认后才 run、再累计账单。
"""
from __future__ import annotations

import os

# 本地各任务粗估耗时(秒,5090 经验值;仅作进度/排期参考)
_LOCAL_SECONDS = {
    "char_concept": 12, "char_turnaround": 40, "keyframe_edit": 18,
    "keyframe_compose": 26, "i2v_local": 70, "interp_upscale": 30,
}
# 云单价(元/秒,估算;VOLCANO_PRICE_PER_SEC 可覆盖)。豆包 Seedance 实际以账单为准。
_CLOUD_RATE = float(os.environ.get("VOLCANO_PRICE_PER_SEC", "0.30"))


def estimate(task: str, backend: str = "local-5090", duration: int = 5) -> dict:
    """返回 {backend, seconds, cost, currency, note}。backend 含 'cloud' 视为云计费。"""
    if "cloud" in backend or backend in ("volcano", "dashscope"):
        cost = round(duration * _CLOUD_RATE, 2)
        return {"backend": backend, "seconds": duration + 20, "cost": cost,
                "currency": "CNY", "note": f"云按时长计费估算({duration}s × ¥{_CLOUD_RATE}/s),以账单为准"}
    return {"backend": backend, "seconds": _LOCAL_SECONDS.get(task, 30), "cost": 0.0,
            "currency": "CNY", "note": "本地无现金成本(电费忽略)"}
