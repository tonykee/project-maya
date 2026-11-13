#!/usr/bin/env bash
# 断点续传下载 DeepSeek-V4.1-Flash-1017 Maya-S 模型分片 1-4 (178.2 GB)
# 复用已存在的 Engram-Q6_K 表(161GB)、dspark、vision，不重复下载。
# 来源: HuggingFace peasantsmith/DeepSeek-V4.1-Flash-1017-Maya-GGUF
# 用法:
#   ./dl_ds4_maya_s_resume.sh           下载
#   ./dl_ds4_maya_s_resume.sh --check   只校验
set -uo pipefail
cd "$(dirname "$0")"

REPO="peasantsmith/DeepSeek-V4.1-Flash-1017-Maya-GGUF"
REV="c33d87b8c7a3b7d55e71324dc82395587a870b0b"
SUBDIR="Maya-S"
DEST="/mnt/kioxia/Maya-data/models/DeepSeek-V4.1-Flash-1017-GGUF/${SUBDIR}"
JOBS=2

# 文件名 大小 sha256 (仅 1-4；5-6 Engram 表已在 ../Engram-Q6_K 复用)
FILES=(
"DeepSeek-V4.1-Flash-1017-Maya-S-IQ2_XXS-00001-of-00006.gguf 47887697312 1f3437f57042e69f94c141ffbcba0d5610dab63feb07244fb468be4940d6763f"
"DeepSeek-V4.1-Flash-1017-Maya-S-IQ2_XXS-00002-of-00006.gguf 47669578400 66501fee8702ffd54e6f065323ab54bb3150d20b10b01922c589e7462c7b5ba6"
"DeepSeek-V4.1-Flash-1017-Maya-S-IQ2_XXS-00003-of-00006.gguf 47103347360 3195b23f33337c46a07c48583946d99147c3635412bc4adc6acdc4cf42bf30ad"
"DeepSeek-V4.1-Flash-1017-Maya-S-IQ2_XXS-00004-of-00006.gguf 35532532032 d60dba35fac9601cd5c6026439dd980c457a5bb1c009192ea539b220108ea0db"
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
      local have_sha; have_sha=$(sha256sum "$DEST/$n" | cut -d' ' -f1)
      if [ "$have_sha" = "$sha" ]; then echo "  sha256 ✓"; else echo "  sha256 ✗ ($have_sha)"; bad=1; fi
    else echo; fi
  done
  [ "$bad" -eq 0 ] && echo "分片1-4全部完成 ✅ (Engram/dspark/vision 已复用)" || echo "还有未完成/不匹配的文件"
  return "$bad"
}

if [ "${1:-}" = "--check" ]; then check; exit $?; fi

mkdir -p "$DEST"
echo "== 目标目录: $DEST"
echo "== 起始时间: $(date '+%F %T')   并发: $JOBS"
echo "== 复用: Engram-Q6_K (~161GB), dspark (~8GB), vision (~1GB) 已存在"

# 清理明显残缺的小文件，避免错误续传
for row in "${FILES[@]}"; do
  read -r n want sha <<<"$row"
  got=$(size_of "$n")
  if [ "$got" -gt 0 ] && [ "$got" -lt 104857600 ]; then
    echo "[清理] $n 现有 $(human "$got") 过小(残缺)，删除后重下"
    rm -f "$DEST/$n"
  fi
done

fetch_one() {
  local name="$1" want="$2"
  local url="https://huggingface.co/${REPO}/resolve/${REV}/${SUBDIR}/${name}"
  local out="$DEST/$name" try=0
  while :; do
    try=$((try+1))
    local have; have=$(size_of "$name")
    [ "$have" -ge "$want" ] && { echo "[完成] $name $(human "$have")"; return 0; }
    echo "[开始] $name 已有 $(human "$have") / $(human "$want") (第 $try 次)"
    curl -L --fail -C - \
         --retry 20 --retry-delay 10 --retry-all-errors \
         --speed-limit 1024 --speed-time 120 \
         --connect-timeout 30 -o "$out" "$url"
    local rc=$?
    have=$(size_of "$name")
    [ "$have" -ge "$want" ] && { echo "[完成] $name $(human "$have")"; return 0; }
    echo "[重试] $name 中断(rc=$rc)于 $(human "$have")，10 秒后继续"
    sleep 10
    [ "$try" -ge 2000 ] && { echo "[放弃] $name 重试过多"; return 1; }
  done
}
export -f fetch_one size_of human
export DEST REPO REV SUBDIR

# 大文件先下
{
  for row in "${FILES[@]}"; do read -r n want sha <<<"$row"; echo "$n $want"; done
} | sort -k2 -nr | xargs -P "$JOBS" -n 2 bash -lc 'fetch_one "$0" "$1"'

echo "== 下载循环结束: $(date '+%F %T')"
check
