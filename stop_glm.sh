#!/usr/bin/env bash
# stop.sh - 优雅停止 Project Maya（先 SIGTERM，超时再 SIGKILL）
set -uo pipefail
cd "$(dirname "$0")"

CONFIG="maya-maya-s24.json"
RUN_DIR="$PWD/run"
PID_FILE="$RUN_DIR/maya.pid"
GRACE="${MAYA_STOP_GRACE:-70}"   # 引擎默认 50s 内退出，留余量

cfg() { "${PY:-python3}" -c "import json,sys;d=json.load(open('$CONFIG'));print(eval(sys.argv[1]))" "$1"; }
PORT="$(cfg "d.get('port',8080)")" || PORT=8080

pids=()

# 1) PID 文件
if [ -f "$PID_FILE" ]; then
  p="$(cat "$PID_FILE" 2>/dev/null || true)"
  [ -n "$p" ] && kill -0 "$p" 2>/dev/null && pids+=("$p")
fi

# 2) 兜底：按命令行查找（含引擎）
while read -r p; do
  [ -z "$p" ] && continue
  # only the engine's own python process (the shell that runs this script matches the pattern too)
  [ "$(ps -o comm= -p "$p" 2>/dev/null)" = "python" ] && pids+=("$p")
done < <(pgrep -f "maya[.]py --config" 2>/dev/null || true)

if [ ${#pids[@]} -eq 0 ]; then
  echo "Maya 未在运行。"
  rm -f "$PID_FILE"
  exit 0
fi

# 去重
mapfile -t pids < <(printf '%s\n' "${pids[@]}" | sort -u)

echo "正在停止 Maya (PID: ${pids[*]}) ..."
kill -TERM "${pids[@]}" 2>/dev/null || true

for _ in $(seq 1 "$GRACE"); do
  alive=0
  for p in "${pids[@]}"; do kill -0 "$p" 2>/dev/null && alive=1; done
  [ "$alive" -eq 0 ] && break
  sleep 1
done

if [ "$alive" -eq 1 ]; then
  echo "优雅退出超时，强制结束 ..."
  kill -KILL "${pids[@]}" 2>/dev/null || true
  sleep 2
fi

# 确认端口释放
if command -v ss >/dev/null 2>&1 && ss -tln 2>/dev/null | grep -q ":$PORT "; then
  echo "警告: 端口 $PORT 仍被占用："
  ss -tlnp 2>/dev/null | grep ":$PORT " || true
  rm -f "$PID_FILE"
  exit 1
fi

rm -f "$PID_FILE"
echo "已停止，端口 $PORT 已释放。"
