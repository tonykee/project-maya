#!/usr/bin/env bash
# 断点续传下载 DeepSeek-V4.1-Flash-1017 Maya-XS (5 个分片, 276.6 GB)
# 可随时 Ctrl+C / 重跑本脚本，curl -C - 会从已下载的字节继续，不会重下。
# 用法:
#   ./dl_ds4_xs.sh           下载（后台运行建议: setsid nohup ./dl_ds4_xs.sh >> logs/download-ds4.log 2>&1 &）
#   ./dl_ds4_xs.sh --check   只校验已完成分片的大小与 sha256
set -uo pipefail
cd "$(dirname "$0")"

REPO="peasantsmith/DeepSeek-V4.1-Flash-1017-Maya-GGUF"
REV="c273fcbdda76a1db074c2f414cb70edbfca2f2ef"
SUBDIR="Maya-XS"
DEST="/mnt/kioxia/Maya-data/models/DeepSeek-V4.1-Flash-1017-GGUF/${SUBDIR}"
JOBS=4

# 文件名 大小 sha256
FILES=(
"DeepSeek-V4.1-Flash-1017-Maya-XS-IQ1_S-00001-of-00005.gguf 47781530400 a0cb7966afd68bc35c46f78018d1fa1d2e4bcbe3c3baf39f60cd1733ed9ad7e5"
"DeepSeek-V4.1-Flash-1017-Maya-XS-IQ1_S-00002-of-00005.gguf 47775748128 ba5afb43adfc667436ebcfbd82d25411fa2843ee7e1d877290611cd60f93cca1"
"DeepSeek-V4.1-Flash-1017-Maya-XS-IQ1_S-00003-of-00005.gguf 19784230848 1482443bb4957c8d2f005ded365445f98558ff05c50674f9ee9a96ddabc122a4"
"DeepSeek-V4.1-Flash-1017-Maya-XS-IQ1_S-00004-of-00005.gguf 80641295472 0d93315942c523d82f6dbc0a6e0e1751548e309f3963f96b82f92e8f9bc52e36"
"DeepSeek-V4.1-Flash-1017-Maya-XS-IQ1_S-00005-of-00005.gguf 80643503412 39bbc8cde8b17604fed9a7ba7fc6bc9c5e72e34733657943ac049b4b9ca2d340"
)

size_of() { stat -c %s "$DEST/$1" 2>/dev/null || echo 0; }
human()   { numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "$1"; }

check() {
  local bad=0
  echo "== 校验 $DEST"
  for row in "${FILES[@]}"; do
    read -r n want sha <<<"$row"
    local got; got=$(size_of "$n")
    if [ "$got" -ne "$want" ]; then
      printf "  %-64s %s / %s  ✗\n" "$n" "$(human "$got")" "$(human "$want")"; bad=1; continue
    fi
    printf "  %-64s %s  size ✓" "$n" "$(human "$got")"
    if command -v sha256sum >/dev/null; then
      if [ "$(sha256sum "$DEST/$n" | cut -d' ' -f1)" = "$sha" ]; then echo "  sha256 ✓"; else echo "  sha256 ✗"; bad=1; fi
    else echo; fi
  done
  [ "$bad" -eq 0 ] && echo "全部完成 ✅" || echo "还有未完成/不匹配的文件"
  return "$bad"
}

if [ "${1:-}" = "--check" ]; then check; exit $?; fi

mkdir -p "$DEST"
echo "== 目标目录: $DEST"
echo "== 起始时间: $(date '+%F %T')   并发: $JOBS"

fetch_one() {
  local name="$1" want="$2"
  local url="https://huggingface.co/${REPO}/resolve/${REV}/${SUBDIR}/${name}"
  local out="$DEST/$name" try=0
  while :; do
    try=$((try+1))
    local have; have=$(size_of "$name")
    [ "$have" -ge "$want" ] && { echo "[完成] $name $(human "$have")"; return 0; }
    echo "[开始] $name 已有 $(human "$have") / $(human "$want") (第 $try 次)"
    curl -sS -L --fail -C - \
         --retry 20 --retry-delay 10 --retry-all-errors \
         --speed-limit 1024 --speed-time 120 \
         --connect-timeout 30 -o "$out" "$url"
    have=$(size_of "$name")
    [ "$have" -ge "$want" ] && { echo "[完成] $name $(human "$have")"; return 0; }
    echo "[重试] $name 中断于 $(human "$have")，10 秒后继续"
    sleep 10
    [ "$try" -ge 500 ] && { echo "[放弃] $name 重试过多"; return 1; }
  done
}
export -f fetch_one size_of human
export DEST REPO REV SUBDIR

# 大文件先下（并行 4 个），再做剩下的小文件
{
  for row in "${FILES[@]}"; do read -r n want sha <<<"$row"; echo "$n $want"; done
} | sort -k2 -nr | xargs -P "$JOBS" -n 2 bash -c 'fetch_one "$0" "$1"'

echo "== 下载循环结束: $(date '+%F %T')"
check
