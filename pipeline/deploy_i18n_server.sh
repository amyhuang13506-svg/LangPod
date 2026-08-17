#!/bin/bash
# 多语言 pipeline 部署到阿里云（47.84.141.119 → /opt/langpod/pipeline/）
# 用法：./deploy_i18n_server.sh   （会提示输服务器密码，或先配好免密）
set -e

SERVER="root@47.84.141.119"
DEST="/opt/langpod/pipeline"

# 新增 + 改动的文件（zh 主流程文件仅含非致命 enqueue 钩子）
FILES=(
  languages.py
  prompts_ko.py
  prompts_ja.py
  prompts_es.py
  prompts_pt_br.py
  hant.py
  localize_content.py
  translate_episode.py
  localize_patterns.py
  localize_queue.py
  localize_daily.py
  backfill_localization.py
  translate_ui_strings.py
  check_xcstrings_placeholders.py
  generate_daily.py
  generate_audio.py
  upload_oss.py
  push_new_episode.py
  push_new_raw_podcast.py
)

echo "== 上传 ${#FILES[@]} 个文件 =="
scp "${FILES[@]}" "$SERVER:$DEST/"
scp -r qc "$SERVER:$DEST/"

echo "== 服务器侧验证 import + 加 cron =="
ssh "$SERVER" bash -s <<'REMOTE'
set -e
cd /opt/langpod/pipeline
# zh-Hant 通道依赖 OpenCC
python3 -c "import opencc" 2>/dev/null || pip3 install opencc opencc-python-reimplemented 2>&1 | tail -1
python3 - <<'PY'
import languages, prompts_ko, prompts_ja, prompts_es, prompts_pt_br
import localize_queue, translate_episode, localize_content, hant
import localize_patterns, localize_daily, backfill_localization
from qc import rules, judge
print("✓ all i18n modules import OK, NEW_LANGS =", languages.NEW_LANGS)
PY

# cron：4:30 localize + 6:00 重试（幂等添加）
( crontab -l 2>/dev/null | grep -v localize_daily ; cat <<'CRON'
30 4 * * * cd /opt/langpod/pipeline && python3 localize_daily.py >> logs/localize.log 2>&1
0 6 * * * cd /opt/langpod/pipeline && python3 localize_daily.py >> logs/localize.log 2>&1
CRON
) | crontab -
echo "✓ crontab:"
crontab -l | grep localize

# 空队列干跑（应打印 queue empty 干净退出）
python3 localize_daily.py
REMOTE

echo ""
echo "== 部署完成。后续步骤 =="
echo "1. 明天 3:00 generate_daily 会自动入 localize 队列，4:30 产出韩语层"
echo "2. 存量回填（近30天先跑）："
echo "   ssh $SERVER 'cd $DEST && python3 backfill_localization.py --limit 60 && nohup python3 localize_daily.py >> logs/backfill.log 2>&1 &'"
echo "3. 验证：早上看 logs/localize.log + curl index_ko.json 条数递增"
