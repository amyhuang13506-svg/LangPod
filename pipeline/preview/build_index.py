"""
拉所有 raw_podcast 资源 → 生成本地审查目录。

输出：
    /tmp/preview/
      ├── index.html         (列表入口)
      ├── preview.html       (字幕预览模板，读 ?id=XXX)
      ├── podcasts.json      (15 集元数据)
      └── transcripts/
            ├── raw-yt-XXX.json
            └── ...

媒体走 OSS HTTPS（不下载到本地）。
"""
import argparse
import json
import shutil
import sys
from pathlib import Path

import requests

OSS_BASE = "https://castlingo.oss-ap-southeast-1.aliyuncs.com"
MASTER_URL = f"{OSS_BASE}/raw_podcasts/raw_podcasts.json"


def fmt_duration(seconds: int) -> str:
    if seconds >= 3600:
        h = seconds // 3600
        m = (seconds % 3600) // 60
        return f"{h}h{m:02d}m"
    return f"{seconds // 60}min"


def build(out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    transcripts_dir = out_dir / "transcripts"
    transcripts_dir.mkdir(exist_ok=True)
    here = Path(__file__).resolve().parent

    # 1. 拷贝 preview.html 模板
    shutil.copy(here / "template.html", out_dir / "preview.html")

    # 2. 拉 master
    print(f"=== 拉 master ===")
    master = requests.get(MASTER_URL, timeout=15).json()
    print(f"  {len(master)} 条")

    # 3. 拉每条 transcript（只拉缺的）+ 收集元数据
    podcasts_meta = []
    for i, m in enumerate(master, 1):
        pid = m["id"]
        tj_path = transcripts_dir / f"{pid}.json"
        if not tj_path.exists() or tj_path.stat().st_size < 100:
            print(f"[{i}/{len(master)}] 拉 {pid}")
            t_url = m.get("transcript_url")
            if not t_url:
                print(f"  ⚠ 无 transcript_url，跳过")
                continue
            r = requests.get(t_url, timeout=30)
            if r.status_code != 200:
                print(f"  ⚠ HTTP {r.status_code}")
                continue
            tj_path.write_bytes(r.content)
        else:
            print(f"[{i}/{len(master)}] 已有 {pid}")

        transcript = json.loads(tj_path.read_text(encoding="utf-8"))
        segs = transcript.get("segments") or []
        words_count = sum(len(s.get("words") or []) for s in segs)
        has_v2 = bool(segs and segs[0].get("words"))

        podcasts_meta.append({
            "id": pid,
            "title": m.get("title", ""),
            "speaker": m.get("speaker", ""),
            "category": m.get("category", ""),
            "topic": m.get("topic", ""),
            "duration": int(m.get("duration_seconds", 0) or 0),
            "published_at": m.get("published_at", ""),
            "thumbnail": m.get("thumbnail"),
            "media_url": m.get("audio_url") or f"{OSS_BASE}/raw_podcasts/{pid}/media.mp4",
            "segments": len(segs),
            "words": words_count,
            "v2": has_v2,
        })

    # 4. 写 podcasts.json（preview.html 读这个拿元数据）
    (out_dir / "podcasts.json").write_text(
        json.dumps(podcasts_meta, ensure_ascii=False, indent=2),
        encoding="utf-8"
    )
    print(f"\n✓ podcasts.json 写入（{len(podcasts_meta)} 条）")

    # 5. 写 index.html
    (out_dir / "index.html").write_text(_render_index(podcasts_meta), encoding="utf-8")
    print(f"✓ index.html 写入")
    print(f"\n打开（必须用 http server，不能 file://）：")
    print(f"  cd {out_dir} && python3 -m http.server 8000")
    print(f"  open http://localhost:8000/index.html")


def _render_index(rows: list[dict]) -> str:
    cards = "\n".join(_render_card(r) for r in rows)
    total_seg = sum(r["segments"] for r in rows)
    total_words = sum(r["words"] for r in rows)
    total_dur = sum(r["duration"] for r in rows)
    v2_count = sum(1 for r in rows if r["v2"])
    return f"""<!DOCTYPE html>
<html lang="zh"><head><meta charset="UTF-8">
<title>Castlingo Raw Podcast 字幕审查</title>
<style>
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{ font-family: -apple-system, "PingFang SC", sans-serif; background: #0a0a0a; color: #eee; padding: 24px; }}
  h1 {{ font-size: 22px; margin-bottom: 6px; }}
  .stats {{ font-size: 13px; color: #888; margin-bottom: 24px; }}
  .grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(360px, 1fr)); gap: 16px; }}
  .card {{
    background: #1a1a1a; border-radius: 10px; padding: 14px;
    display: flex; gap: 12px; cursor: pointer; transition: background 0.1s;
    text-decoration: none; color: inherit;
  }}
  .card:hover {{ background: #232323; }}
  .thumb {{ flex: 0 0 100px; height: 75px; border-radius: 6px; background: #333 center/cover no-repeat; }}
  .info {{ flex: 1; min-width: 0; }}
  .title {{ font-size: 14px; font-weight: 600; line-height: 1.3; margin-bottom: 4px;
           overflow: hidden; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; }}
  .meta {{ font-size: 11px; color: #888; margin-bottom: 6px; }}
  .meta .sep {{ margin: 0 6px; color: #444; }}
  .badges {{ display: flex; gap: 6px; flex-wrap: wrap; }}
  .badge {{ font-size: 10px; padding: 2px 6px; border-radius: 4px; background: #2a2a2a; }}
  .badge.v2 {{ background: #1f3a1f; color: #6ec76e; }}
  .badge.v1 {{ background: #3a1f1f; color: #c76e6e; }}
  .badge.tk {{ background: #1f2d3a; color: #6ea4c7; }}
  .badge.exp {{ background: #3a2f1f; color: #c79f6e; }}
  .check {{ font-size: 11px; color: #555; margin-top: 4px; }}
  .check input {{ vertical-align: middle; margin-right: 4px; }}
</style></head><body>
<h1>📜 Raw Podcast 字幕审查</h1>
<div class="stats">{len(rows)} 集 · {fmt_duration(total_dur)} · {total_seg:,} 段 · {total_words:,} 词 · v2: {v2_count}/{len(rows)}</div>
<div class="grid">
{cards}
</div>
<script>
document.querySelectorAll('input[type=checkbox]').forEach(cb => {{
  const key = 'review:' + cb.dataset.id + ':' + cb.dataset.kind;
  cb.checked = localStorage.getItem(key) === '1';
  cb.addEventListener('change', e => {{
    e.stopPropagation();
    localStorage.setItem(key, cb.checked ? '1' : '0');
  }});
}});
document.querySelectorAll('.check').forEach(el => el.addEventListener('click', e => e.stopPropagation()));
</script>
</body></html>
"""


def _render_card(r: dict) -> str:
    thumb_style = f'style="background-image:url({r["thumbnail"]})"' if r.get("thumbnail") else ""
    cat_badge = '<span class="badge tk">硅谷原声</span>' if r["category"] == "tech_keynote" else '<span class="badge exp">探索</span>'
    v2_badge = '<span class="badge v2">v2</span>' if r["v2"] else '<span class="badge v1">v1</span>'
    title_esc = (r["title"] or "").replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")
    return f"""  <a class="card" href="preview.html?id={r['id']}" target="_blank">
    <div class="thumb" {thumb_style}></div>
    <div class="info">
      <div class="title">{title_esc}</div>
      <div class="meta">{r['speaker']}<span class="sep">·</span>{fmt_duration(r['duration'])}<span class="sep">·</span>{r['published_at']}</div>
      <div class="badges">{cat_badge}{v2_badge}<span class="badge">{r['segments']} 段</span><span class="badge">{r['words']:,} 词</span></div>
      <div class="check">
        <label><input type="checkbox" data-id="{r['id']}" data-kind="ok"> 已检查</label>
        &nbsp;
        <label><input type="checkbox" data-id="{r['id']}" data-kind="bad"> 有问题</label>
      </div>
    </div>
  </a>
"""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="/tmp/preview", type=Path)
    args = parser.parse_args()
    # 清掉旧的 15 个 HTML 文件
    old_previews = args.out / "previews"
    if old_previews.exists():
        shutil.rmtree(old_previews)
        print(f"清掉旧的 previews/ 目录")
    build(args.out)


if __name__ == "__main__":
    main()
