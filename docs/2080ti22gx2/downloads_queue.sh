#!/usr/bin/env bash
# 下载队列：等 DeepSeek Maya-XS 下载并校验通过后，自动开始 MiniMax Maya-XS。
# 用法: setsid nohup ./downloads_queue.sh >> logs/downloads-queue.log 2>&1 &
set -uo pipefail
cd "$(dirname "$0")"

echo "== 队列启动 $(date '+%F %T')"

# 1) 等 DeepSeek 的下载进程全部结束（脚本 + curl）
while pgrep -f "dl_ds4_xs\.sh" >/dev/null || pgrep -f "curl.*DeepSeek-V4.1-Flash-1017-Maya-XS" >/dev/null; do
  sleep 60
done
echo "== DeepSeek 下载进程已结束 $(date '+%F %T')"

# 2) 校验；未通过则重跑一次续传
if ! ./dl_ds4_xs.sh --check; then
  echo "== DeepSeek 校验未通过，续传一次"
  ./dl_ds4_xs.sh
  ./dl_ds4_xs.sh --check || { echo "== DeepSeek 仍不完整，队列中止"; exit 1; }
fi
echo "== DeepSeek 校验通过 $(date '+%F %T')"

# 3) 开始 MiniMax
echo "== 开始下载 MiniMax Maya-XS $(date '+%F %T')"
./dl_mm3_xs.sh
rc=$?
if [ $rc -eq 0 ]; then
  echo "== MiniMax 下载完成并校验通过 $(date '+%F %T')"
else
  echo "== MiniMax 下载结束但校验未通过 (rc=$rc) $(date '+%F %T')"
fi
echo "== 队列结束"
