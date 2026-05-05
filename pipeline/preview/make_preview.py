"""
本地 HTML 预览生成器。

输入：transcript.json + 媒体文件（mp4/mp3）路径
输出：自包含 HTML 文件，浏览器打开就能看视频+同步字幕，验证转写质量。

特性：
- 当前 segment 在右侧列表自动高亮 + 滚动
- 主字幕区显示当前句的英文（词级高亮）+ 中文
- 点列表任一行 → 跳到该段
- 点单词 → 跳到该词
"""
import argparse
import json
import sys
from pathlib import Path


def make_preview(
    transcript_path: Path,
    media_path,
    output_path: Path,
    title: str = "",
    speaker: str = "",
    date: str = "",
) -> None:
    """生成 HTML 预览，所有数据 inline，单文件可打开。
    media_path 可以是本地 Path 或 http(s) URL 字符串。"""
    transcript = json.loads(transcript_path.read_text(encoding="utf-8"))

    template_path = Path(__file__).resolve().parent / "template.html"
    html = template_path.read_text(encoding="utf-8")

    # media URL: HTTP(S) 直接传，本地路径转 file://
    media_str = str(media_path)
    if media_str.startswith(("http://", "https://")):
        media_url = media_str
    else:
        media_url = "file://" + str(Path(media_str).resolve())

    # 启发式 title
    if not title:
        title = transcript.get("podcast_id") or transcript_path.stem

    # 替换占位符
    html = html.replace("__TITLE__", title)
    html = html.replace("__SPEAKER__", speaker or "")
    html = html.replace("__DATE__", date or "")
    html = html.replace("__MEDIA_PATH__", media_url)
    html = html.replace("__TRANSCRIPT_JSON__", json.dumps(transcript, ensure_ascii=False))

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(html, encoding="utf-8")

    size_kb = output_path.stat().st_size / 1024
    print(f"✓ HTML 预览生成：{output_path}（{size_kb:.0f}KB）")
    print(f"  在浏览器打开：open {output_path}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--transcript", "-t", required=True, type=Path,
                        help="transcript.json 路径")
    parser.add_argument("--media", "-m", required=True, type=Path,
                        help="媒体文件路径（mp4 / mp3）")
    parser.add_argument("--output", "-o", required=True, type=Path,
                        help="输出 HTML 路径")
    parser.add_argument("--title", default="", help="podcast 标题")
    parser.add_argument("--speaker", default="", help="speaker / channel")
    parser.add_argument("--date", default="", help="发布日期")
    args = parser.parse_args()

    if not args.transcript.exists():
        print(f"✗ transcript 不存在：{args.transcript}")
        sys.exit(1)
    media = str(args.media)
    if not media.startswith(("http://", "https://")) and not args.media.exists():
        print(f"✗ 媒体文件不存在：{args.media}")
        sys.exit(1)

    make_preview(args.transcript, media, args.output,
                 title=args.title, speaker=args.speaker, date=args.date)


if __name__ == "__main__":
    main()
