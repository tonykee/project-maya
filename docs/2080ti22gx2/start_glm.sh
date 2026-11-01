#!/usr/bin/env bash
# start.sh - 后台启动 Project Maya（GLM-5.3 · Maya-S24）并等待就绪
# 用法: ./start.sh [传给 run-maya-maya-s24.sh 的额外参数]
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="maya-maya-s24.json"
RUN_SCRIPT="./run-maya-maya-s24.sh"
RUN_DIR="$PWD/run"
LOG_DIR="$PWD/logs"
PID_FILE="$RUN_DIR/maya.pid"
LOG_FILE="$LOG_DIR/server.log"
WAIT_S="${MAYA_START_WAIT:-300}"

mkdir -p "$RUN_DIR" "$LOG_DIR"

cfg() { "${PY:-python3}" -c "import json,sys;d=json.load(open('$CONFIG'));print(eval(sys.argv[1]))" "$1"; }
PORT="$(cfg "d.get('port',8080)")"
KEY="$(cfg "d.get('api_key','') or ''")"
HOST="$(cfg "d.get('host','127.0.0.1')")"

health() {
  if [ -n "$KEY" ]; then
    curl -sf -m 2 -H "Authorization: Bearer $KEY" "http://127.0.0.1:$PORT/health" 2>/dev/null
  else
    curl -sf -m 2 "http://127.0.0.1:$PORT/health" 2>/dev/null
  fi
}

# 已在运行？
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "已在运行 (PID $(cat "$PID_FILE"), 端口 $PORT)。先执行 ./stop.sh 再启动。"
  exit 0
fi
if health >/dev/null; then
  echo "端口 $PORT 上已有 Maya 在运行（不是本脚本启动的）。"
  echo "如需重启：kill \$(pgrep -f 'maya[.]py --config') 后再运行本脚本。"
  exit 0
fi

echo "启动 Maya..."
nohup "$RUN_SCRIPT" --port "$PORT" "$@" >>"$LOG_FILE" 2>&1 &
PID=$!
echo "$PID" >"$PID_FILE"
disown "$PID" 2>/dev/null || true

printf '等待模型加载'
for _ in $(seq 1 "$WAIT_S"); do
  if ! kill -0 "$PID" 2>/dev/null; then
    echo
    echo "启动失败：进程已退出。最近 20 行日志："
    tail -20 "$LOG_FILE"
    rm -f "$PID_FILE"
    exit 1
  fi
  if health >/dev/null; then
    echo " 就绪"
    break
  fi
  printf '.'
  sleep 1
done

if ! health >/dev/null; then
  echo
  echo "超时：${WAIT_S}s 内未就绪。查看日志: tail -f $LOG_FILE"
  exit 1
fi

IP="$(ip -4 addr show 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | grep -v '^127\.' | head -n1 || true)"
echo
echo "Maya 已启动 (PID $PID)"
echo "  日志      : $LOG_FILE"
echo "  引擎日志  : $(cfg "d.get('log','')")"
echo "  本机访问  : http://127.0.0.1:$PORT"
[ -n "$IP" ] && echo "  内网访问  : http://$IP:$PORT"
[ -n "$KEY" ] && echo "  API Key   : $KEY"
echo "  API       : http://127.0.0.1:$PORT/v1  (OpenAI) / /v1/messages (Anthropic)"
echo "  停止      : ./stop_glm.sh"
