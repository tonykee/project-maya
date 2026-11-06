#!/usr/bin/env bash
# start_ds4_v2.sh - 启动 DeepSeek V4.1 Maya-XS v2（独立于 v1：独立 config/pid/log；参数归零用于重调优）
# 用法：先停 v1（./stop_ds4.sh），再 ./start_ds4_v2.sh。测试完可 ./stop_ds4_v2.sh && ./start_ds4.sh 恢复 v1。
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${MAYA_CONFIG:-maya-ds4-v2.json}"
RUN_DIR="$PWD/run"
LOG_DIR="$PWD/logs"
PID_FILE="$RUN_DIR/ds4-v2.pid"
LOG_FILE="$LOG_DIR/ds4-v2-server.log"
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
  echo "v2 已在运行 (PID $(cat "$PID_FILE"), 端口 $PORT)。先执行 ./stop_ds4_v2.sh。"; exit 0
fi
if health >/dev/null && ss -ltnp 2>/dev/null | grep -q ":$PORT "; then
  echo "端口 $PORT 上已有服务在运行（可能是 v1 或其他实例）。先停止再启动 v2。"; exit 0
fi

echo "启动 DeepSeek V4.1 Maya-XS v2（参数归零基线，加载约 7-10 分钟）..."
nohup ./.venv/bin/python maya.py --yes --config "$CONFIG" --port "$PORT" "$@" >>"$LOG_FILE" 2>&1 &
PID=$!
echo "$PID" >"$PID_FILE"
disown "$PID" 2>/dev/null || true

printf '等待模型加载'
for _ in $(seq 1 "$WAIT_S"); do
  if ! kill -0 "$PID" 2>/dev/null; then
    echo; echo "启动失败：进程已退出。最近 30 行日志："; tail -30 "$LOG_FILE"; rm -f "$PID_FILE"; exit 1
  fi
  if health >/dev/null; then echo " 就绪"; break; fi
  printf '.'; sleep 2
done

if ! health >/dev/null; then
  echo; echo "超时：${WAIT_S}s 内未就绪。日志: tail -f $LOG_FILE $(cfg "d.get('log','')")"; exit 1
fi

IP="$(ip -4 addr show 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | grep -v '^127\.' | head -n1 || true)"
echo
echo "DeepSeek v2 已启动 (PID $PID)  pack=$(cfg "([a for i,a in enumerate(d['args']) if a=='--pack'] and d['args'][d['args'].index('--pack')+1]) or 'maya-ds4-v2'")"
echo "  本机访问 : http://127.0.0.1:$PORT"
[ -n "$IP" ] && echo "  内网访问 : http://$IP:$PORT"
[ -n "$KEY" ] && echo "  API Key  : $KEY"
echo "  日志     : $LOG_FILE / $(cfg "d.get('log','')")"
echo "  停止     : ./stop_ds4_v2.sh   恢复 v1: ./stop_ds4_v2.sh && ./start_ds4.sh"
