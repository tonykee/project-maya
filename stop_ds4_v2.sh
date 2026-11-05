#!/usr/bin/env bash
# stop_ds4_v2.sh - 停止 DeepSeek v2 服务（与 v1 隔离）
set -uo pipefail
cd "$(dirname "$0")"

CONFIG="${MAYA_CONFIG:-maya-ds4-v2.json}"
RUN_DIR="$PWD/run"
PID_FILE="$RUN_DIR/ds4-v2.pid"
GRACE="${MAYA_STOP_GRACE:-90}"

cfg() { "${PY:-python3}" -c "import json,sys;d=json.load(open('$CONFIG'));print(eval(sys.argv[1]))" "$1"; }
PORT="$(cfg "d.get('port',8000)")" || PORT=8000

pids=()
if [ -f "$PID_FILE" ]; then
  p="$(cat "$PID_FILE" 2>/dev/null || true)"
  [ -n "$p" ] && kill -0 "$p" 2>/dev/null && pids+=("$p")
fi
while read -r p; do [ -n "$p" ] && [ "$(ps -o comm= -p "$p" 2>/dev/null)" = "python" ] && pids+=("$p"); done < <(pgrep -f "maya[.]py --config .*maya-ds4-v2" 2>/dev/null || true)
while read -r p; do [ -n "$p" ] && [ "$(ps -o comm= -p "$p" 2>/dev/null)" = "python" ] && pids+=("$p"); done < <(pgrep -f "serve/server[.]py --engine .* --config .*maya-ds4-v2" 2>/dev/null || true)
while read -r p; do [ -n "$p" ] && pids+=("$p"); done < <(pgrep -f "build/maya-ds4 --serve --pack .*maya-ds4-v2" 2>/dev/null || true)

if [ ${#pids[@]} -eq 0 ]; then echo "DeepSeek v2 未在运行。"; rm -f "$PID_FILE"; exit 0; fi
mapfile -t pids < <(printf '%s\n' "${pids[@]}" | sort -u)
echo "正在停止 DeepSeek v2 (PID: ${pids[*]}) ..."
kill -TERM "${pids[@]}" 2>/dev/null || true
alive=1
for _ in $(seq 1 "$GRACE"); do
  alive=0; for p in "${pids[@]}"; do kill -0 "$p" 2>/dev/null && alive=1; done
  [ "$alive" -eq 0 ] && break; sleep 1
done
if [ "$alive" -eq 1 ]; then kill -KILL "${pids[@]}" 2>/dev/null || true; sleep 2; fi
command -v fuser >/dev/null 2>&1 && fuser -k "$PORT"/tcp >/dev/null 2>&1 || true
sleep 1
rm -f "$PID_FILE"
echo "已停止 v2，端口 $PORT 已释放。"
