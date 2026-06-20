"""导出工程(阶段4 / open-questions D4):有序片段文件夹 + FCPXML。

FCPXML 同时被 Final Cut Pro 与 DaVinci Resolve 导入。从项目的镜头顺序 + 选定 take
生成时间线。视频时长用 ffprobe 取帧数(按 fps 折算为 FCPXML 的有理时间)。
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
from xml.sax.saxutils import escape


def _probe(path: str) -> dict:
    """ffprobe 取 帧数/fps/宽高。失败则给保守默认。"""
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "error", "-select_streams", "v:0",
             "-show_entries", "stream=nb_frames,r_frame_rate,width,height",
             "-of", "json", path],
            capture_output=True, text=True, check=True).stdout
        s = json.loads(out)["streams"][0]
        num, den = (s.get("r_frame_rate", "16/1").split("/") + ["1"])[:2]
        fps = round(float(num) / float(den)) or 16
        frames = int(s.get("nb_frames") or 0)
        if not frames:  # 有些容器不写 nb_frames,退而求时长×fps
            dur = subprocess.run(["ffprobe", "-v", "error", "-show_entries",
                                  "format=duration", "-of", "default=nw=1:nk=1", path],
                                 capture_output=True, text=True).stdout.strip()
            frames = int(round(float(dur or 1) * fps))
        return {"frames": frames, "fps": fps,
                "w": int(s.get("width", 832)), "h": int(s.get("height", 480))}
    except Exception:
        return {"frames": 48, "fps": 16, "w": 832, "h": 480}


def export_project(store, event_name: str = "ReelForge") -> dict:
    """导出项目为 有序片段 + FCPXML。返回 {fcpxml, clips_dir, clips:[...]}。"""
    doc = store.load()
    exports = os.path.join(store.root, "exports")
    clips_dir = os.path.join(exports, "clips")
    os.makedirs(clips_dir, exist_ok=True)

    # 收集每个镜头的选定 take(无选定取最后一条)
    clips = []
    for idx, shot in enumerate(doc.get("shots", []), 1):
        takes = shot.get("takes", [])
        if not takes:
            continue
        sel = shot.get("selected_take")
        take = next((t for t in takes if t["id"] == sel), takes[-1])
        src = take.get("video")
        if not src or not os.path.exists(src):
            continue
        dst = os.path.join(clips_dir, f"{idx:02d}_{shot['id']}.mp4")
        shutil.copyfile(src, dst)
        meta = _probe(dst)
        clips.append({"name": f"{idx:02d}_{shot['id']}", "path": os.path.abspath(dst), **meta})

    title = doc.get("meta", {}).get("title", "project")
    fcpxml_path = os.path.join(exports, f"{title}.fcpxml")
    with open(fcpxml_path, "w", encoding="utf-8") as f:
        f.write(_build_fcpxml(title, event_name, clips))
    return {"fcpxml": fcpxml_path, "clips_dir": clips_dir, "clips": [c["name"] for c in clips]}


def _build_fcpxml(title: str, event_name: str, clips: list[dict]) -> str:
    fps = clips[0]["fps"] if clips else 16
    w = clips[0]["w"] if clips else 832
    h = clips[0]["h"] if clips else 480
    total = sum(c["frames"] for c in clips) or 1

    res = [f'<format id="r1" name="FFVideoFormat{h}p{fps}" frameDuration="1/{fps}s" '
           f'width="{w}" height="{h}" colorSpace="1-1-1 (Rec. 709)"/>']
    spine = []
    offset = 0
    for i, c in enumerate(clips, 1):
        aid = f"a{i}"
        dur = f"{c['frames']}/{fps}s"
        src = "file://" + c["path"].replace(" ", "%20")
        res.append(
            f'<asset id="{aid}" name="{escape(c["name"])}" start="0s" hasVideo="1" '
            f'format="r1" videoSources="1" duration="{dur}">'
            f'<media-rep kind="original-media" src="{escape(src)}"/></asset>')
        spine.append(
            f'<asset-clip ref="{aid}" offset="{offset}/{fps}s" name="{escape(c["name"])}" '
            f'duration="{dur}" format="r1"/>')
        offset += c["frames"]

    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE fcpxml>\n'
        '<fcpxml version="1.10">\n'
        f'  <resources>\n    ' + "\n    ".join(res) + '\n  </resources>\n'
        f'  <library>\n    <event name="{escape(event_name)}">\n'
        f'      <project name="{escape(title)}">\n'
        f'        <sequence format="r1" duration="{total}/{fps}s" tcStart="0s" tcFormat="NDF">\n'
        f'          <spine>\n            ' + "\n            ".join(spine) + '\n'
        '          </spine>\n        </sequence>\n      </project>\n'
        '    </event>\n  </library>\n</fcpxml>\n'
    )
