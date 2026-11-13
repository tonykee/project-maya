#!/usr/bin/env bash
# 断点续传下载 ISTA-DASLab DeepSeek-V4.1-Flash-1017-GSQ-RCO-GGUF (IQ2_XXS + 共享 Engram)
# 来源: ModelScope (魔塔)。用于 Strata/llama.cpp。总计 ~248.8 GB
# 用法:
#   ./dl_gsq_rco_iq2_xxs.sh           下载
#   ./dl_gsq_rco_iq2_xxs.sh --check   校验
set -uo pipefail
cd "$(dirname "$0")"

REPO="ISTA-DASLab/DeepSeek-V4.1-Flash-1017-GSQ-RCO-GGUF"
REV="master"
DEST="/mnt/kioxia/Maya-data/models/DeepSeek-V4.1-Flash-1017-GSQ-RCO-GGUF"
JOBS=2

# 文件名 大小 sha256 (来自 HF API/LFS oid; ModelScope 同文件)
FILES=(
"DeepSeek-V4.1-Flash-1017-GSQ-RCO-IQ2_XXS-00001-of-00006.gguf 5780704 f356f198561f56df36f7ab92d7238a926646d76de992c34f15bcb939a5f529b9"
"DeepSeek-V4.1-Flash-1017-GSQ-RCO-IQ2_XXS-00002-of-00006.gguf 39535781184 25af3785ccf925f54137e1ead4c481a8952315dc0b1af6519a99407f67bce8f3"
"DeepSeek-V4.1-Flash-1017-GSQ-RCO-IQ2_XXS-00003-of-00006.gguf 39736712000 8168d0998fc494def2e1952d83c131425a108660aae9d29190f5a8670ab62b48"
"DeepSeek-V4.1-Flash-1017-GSQ-RCO-IQ2_XXS-00004-of-00006.gguf 39036908384 9eb9b4de1968f150dfc207eb31c27be9cd9b5666a9a6246bde8a22b184b4bee0"
"DeepSeek-V4.1-Flash-1017-GSQ-RCO-IQ2_XXS-00005-of-00006.gguf 19923784832 7e35f6b4e6fc46f6c4b152b593d84d683c5ece695ae6ad734f556198c041bec1"
"DeepSeek-V4.1-Flash-Engram-IQ4_NL.gguf 110595290816 3dac4c54893ad7aa89103c0028500eadc78e74112cef3a2930a97e67dc9fb4f3"
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
      printf "  %-66s %s / %s  ✗\n" "$n" "$(human "$got")" "$(human "$want")"; bad=1; continue
    fi
    printf "  %-66s %s  size ✓" "$n" "$(human "$got")"
    if command -v sha256sum >/dev/null; then
      local have_sha; have_sha=$(sha256sum "$DEST/$n" | cut -d' ' -f1)
      if [ "$have_sha" = "$sha" ]; then echo "  sha256 ✓"; else echo "  sha256 ✗"; bad=1; fi
    else echo; fi
  done
  local link="$DEST/DeepSeek-V4.1-Flash-1017-GSQ-RCO-IQ2_XXS-00006-of-00006.gguf"
  if [ -e "$link" ]; then echo "  shard-6 link: OK ($link)"; else echo "  shard-6 link: 缺失 (可创建软链接到 Engram 文件)"; fi
  [ "$bad" -eq 0 ] && echo "IQ2_XXS + Engram 全部完成 ✅" || echo "还有未完成/不匹配的文件"
  return "$bad"
}

if [ "${1:-}" = "--check" ]; then check; exit $?; fi

mkdir -p "$DEST"
echo "== 目标目录: $DEST"
echo "== 起始时间: $(date '+%F %T')   并发: $JOBS   源: ModelScope"
echo "== 文件: IQ2_XXS 00001-00005 + 共享 Engram-IQ4_NL (~248.8GB)"

fetch_one() {
  local name="$1" want="$2"
  local url="https://modelscope.cn/models/${REPO}/resolve/${REV}/${name}"
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
export DEST REPO REV

# 大文件优先
{
  for row in "${FILES[@]}"; do read -r n want sha <<<"$row"; echo "$n $want"; done
} | sort -k2 -nr | xargs -P "$JOBS" -n 2 bash -lc 'fetch_one "$0" "$1"'

ln -sfn "DeepSeek-V4.1-Flash-Engram-IQ4_NL.gguf" "$DEST/DeepSeek-V4.1-Flash-1017-GSQ-RCO-IQ2_XXS-00006-of-00006.gguf"

echo "== 下载循环结束: $(date '+%F %T')"
check
