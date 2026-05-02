#!/usr/bin/env python3
"""Render each .screenshot block in appstore_screenshots.html as a 1290x2796 PNG."""
import subprocess
import shutil
from pathlib import Path
import re
import time

ROOT = Path(__file__).resolve().parent
SRC_HTML = ROOT / "appstore_screenshots.html"
OUT_DIR = ROOT.parent / "描述截图"
BACKUP_DIR = OUT_DIR / "_old_simulator"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

NAMES = {
    "s1": "01_fsi_immersive.png",
    "s2": "02_pattern_explain.png",
    "s3": "03_feynman_mastery.png",
    "s4": "04_daily_update.png",
    "s5": "05_scientific_memory.png",
    "s6": "06_silicon_valley.png",
    "s7": "07_video_bilingual.png",
}

# ASC 6.5" slot requires 1284×2778 (or 1242×2688). Render a tiny bit wider at
# source and downscale so the design matches exactly.
TARGET_W, TARGET_H = 1284, 2778

def main():
    html_src = SRC_HTML.read_text(encoding="utf-8")

    # backup old files (keep 6.5inch subfolder intact)
    OUT_DIR.mkdir(exist_ok=True)
    BACKUP_DIR.mkdir(exist_ok=True)
    for f in OUT_DIR.glob("Simulator Screenshot*.png"):
        dest = BACKUP_DIR / f.name
        if dest.exists(): dest.unlink()
        shutil.move(str(f), str(dest))
        print(f"backed up: {f.name}")

    for key, outname in NAMES.items():
        # build a standalone HTML: only this one .screenshot shown, scale:1, fill viewport
        override_css = f"""
        <style id="export-override">
          html, body {{
            background: transparent !important;
            padding: 0 !important;
            margin: 0 !important;
            width: 1290px !important;
            height: 2796px !important;
            overflow: hidden !important;
          }}
          body {{ display: block !important; gap: 0 !important; }}
          .screenshot {{
            transform: none !important;
            margin: 0 !important;
            border-radius: 0 !important;
            box-shadow: none !important;
            display: none !important;
            position: absolute !important;
            top: 0 !important;
            left: 0 !important;
          }}
          .screenshot.{key} {{ display: block !important; }}
        </style>
        """
        export_html = html_src.replace("</head>", override_css + "\n</head>")
        tmp_path = ROOT / f"_export_{key}.html"
        tmp_path.write_text(export_html, encoding="utf-8")

        png_path = OUT_DIR / outname
        if png_path.exists():
            png_path.unlink()

        url = tmp_path.resolve().as_uri()
        cmd = [
            CHROME,
            "--headless=new",
            "--disable-gpu",
            "--hide-scrollbars",
            "--force-device-scale-factor=1",
            "--window-size=1290,2796",
            f"--screenshot={png_path}",
            url,
        ]
        print(f"rendering {outname}...")
        subprocess.run(cmd, check=True, capture_output=True)
        time.sleep(0.3)
        tmp_path.unlink()

        if not png_path.exists():
            raise RuntimeError(f"Chrome did not produce {png_path}")

        # Strip alpha + resize → ASC-compliant RGB PNG at target dimensions
        from PIL import Image
        img = Image.open(png_path)
        if img.mode in ("RGBA", "LA", "P"):
            bg = Image.new("RGB", img.size, (255, 255, 255))
            if img.mode == "P":
                img = img.convert("RGBA")
            bg.paste(img, mask=img.split()[-1] if img.mode in ("RGBA", "LA") else None)
            img = bg
        else:
            img = img.convert("RGB")

        if img.size != (TARGET_W, TARGET_H):
            img = img.resize((TARGET_W, TARGET_H), Image.LANCZOS)

        img.save(png_path, "PNG", optimize=True)

        size = png_path.stat().st_size
        print(f"  → {png_path.name} ({size//1024} KB, {TARGET_W}×{TARGET_H}, RGB)")

    print("\nDone. Files in:", OUT_DIR)
    for p in sorted(OUT_DIR.glob("*.png")):
        print(f"  {p.name}")

if __name__ == "__main__":
    main()
