#!/usr/bin/env bash
# 断点续传下载 MiniMax-M3.1-Flash Maya-XS (2 个分片 + 1 个索引文件, 93.0 GB)
# 中断后重跑本脚本即从断点继续。用法:
#   ./dl_mm3_xs.sh           下载
#   ./dl_mm3_xs.sh --check   只校验大小与 sha256
set -uo pipefail
cd "$(dirname "$0")"

REPO="peasantsmith/MiniMax-M3.1-Flash-Maya-GGUF"
REV="9d256f59f1abe27216511c82e3a8bbe4bd0930d0"
SUBDIR="Maya-XS"
DEST="/mnt/kioxia/Maya-data/models/MiniMax-M3.1-Flash-Maya-XS"
JOBS=2

FILES=(
"MiniMax-M3.1-Flash-Maya-XS-IQ1_S-00001-of-00002.gguf 47846435136 a7ce35ed3a9059ea4d53e817e55d5a9516e31c82fb01e291b56e34be56c33e3c"
"MiniMax-M3.1-Flash-Maya-XS-IQ1_S-00002-of-00002.gguf 45138103520 62a7e1db00496c87a93fc75f12748251ebeb300fd90b0534a576dfa4c3daf213"
"MiniMax-M3.1-Flash-Maya-XS-maya-indexers.bin 12538080 b68c04c2970707a1cb4c43d32efb85bbb006df7688ef98417f027593610d3a18"
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
      printf "  %-58s %s / %s  ✗\n" "$n" "$(human "$got")" "$(human "$want")"; bad=1; continue
    fi
    printf "  %-58s %s  size ✓" "$n" "$(human "$got")"
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
    curl -sS -L --fail -C - --retry 20 --retry-delay 10 --retry-all-errors \
         --speed-limit 1024 --speed-time 120 --connect-timeout 30 -o "$out" "$url"
    have=$(size_of "$name")
    [ "$have" -ge "$want" ] && { echo "[完成] $name $(human "$have")"; return 0; }
    echo "[重试] $name 中断于 $(human "$have")，10 秒后继续"; sleep 10
    [ "$try" -ge 500 ] && { echo "[放弃] $name"; return 1; }
  done
}
export -f fetch_one size_of human
export DEST REPO REV SUBDIR

{
  for row in "${FILES[@]}"; do read -r n want sha <<<"$row"; echo "$n $want"; done
} | sort -k2 -nr | xargs -P "$JOBS" -n 2 bash -c 'fetch_one "$0" "$1"'

echo "== 下载循环结束: $(date '+%F %T')"
check
