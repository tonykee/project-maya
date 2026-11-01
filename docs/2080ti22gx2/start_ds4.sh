#!/usr/bin/env bash
# start_ds4.sh - 后台启动 DeepSeek V4.1 Maya-XS 并等待就绪（加载约 7-10 分钟）
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="maya-ds4.json"
RUN_DIR="$PWD/run"
LOG_DIR="$PWD/logs"
PID_FILE="$RUN_DIR/ds4.pid"
LOG_FILE="$LOG_DIR/ds4-server.log"
WAIT_S="${MAYA_START_WAIT:-900}"

mkdir -p "$RUN_DIR" "$LOG_DIR"

cfg() { "${PY:-python3}" -c "import json,sys;d=json.load(open('$CONFIG'));print(eval(sys.argv[1]))" "$1"; }
PORT="$(cfg "d.get('port',8000)")"
KEY="$(cfg "d.get('api_key','') or ''")"

health() {
  if [ -n "$KEY" ]; then
    curl -sf -m 2 -H "Authorization: Bearer $KEY" "http://127.0.0.1:$PORT/health" 2>/dev/null
  else
    curl -sf -m 2 "http://127.0.0.1:$PORT/health" 2>/dev/null
  fi
}

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "已在运行 (PID $(cat "$PID_FILE"), 端口 $PORT)。先执行 ./stop_ds4.sh。"
  exit 0
fi
if health >/dev/null; then
  echo "端口 $PORT 上已有服务在运行（不是本脚本启动的）。"
  exit 0
fi

echo "启动 DeepSeek V4.1（加载约 7-10 分钟：要把 80GB 专家复制进 pinned RAM）..."
nohup ./.venv/bin/python maya.py --config "$CONFIG" --port "$PORT" "$@" >>"$LOG_FILE" 2>&1 &
PID=$!
echo "$PID" >"$PID_FILE"
disown "$PID" 2>/dev/null || true

printf '等待模型加载'
for _ in $(seq 1 "$WAIT_S"); do
  if ! kill -0 "$PID" 2>/dev/null; then
    echo; echo "启动失败：进程已退出。最近 20 行日志："; tail -20 "$LOG_FILE"; rm -f "$PID_FILE"; exit 1
  fi
  if health >/dev/null; then echo " 就绪"; break; fi
  printf '.'; sleep 2
done

if ! health >/dev/null; then
  echo; echo "超时：${WAIT_S}s 内未就绪。日志: tail -f $LOG_FILE"; exit 1
fi

IP="$(ip -4 addr show 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | grep -v '^127\.' | head -n1 || true)"
echo
echo "DeepSeek 已启动 (PID $PID)"
echo "  本机访问 : http://127.0.0.1:$PORT"
[ -n "$IP" ] && echo "  内网访问 : http://$IP:$PORT"
[ -n "$KEY" ] && echo "  API Key  : $KEY"
echo "  日志     : $LOG_FILE / $(cfg "d.get('log','')")"
echo "  停止     : ./stop_ds4.sh"
