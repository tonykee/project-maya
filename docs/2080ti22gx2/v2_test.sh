#!/usr/bin/env bash
# v2 测试：停 v1，启动 v2（maya-ds4-v2 pack），预热 Engram，跑基线
set -euo pipefail
cd /mnt/kioxia/maya
D=/mnt/kioxia/Maya-data/models/DeepSeek-V4.1-Flash-1017-GGUF/Maya-XS

./stop_ds4.sh
if ! MAYA_CONFIG=maya-ds4-v2.json ./start_ds4.sh; then
  echo '=== v2 failed; restoring v1'
  ./start_ds4.sh
  exit 1
fi

echo '=== warm Engram tables (v1 shards hold the embed tables)'
dd if="$D/DeepSeek-V4.1-Flash-1017-Maya-XS-IQ1_S-00004-of-00005.gguf" of=/dev/null bs=1M count=400 status=none
dd if="$D/DeepSeek-V4.1-Flash-1017-Maya-XS-IQ1_S-00005-of-00005.gguf" of=/dev/null bs=1M count=400 status=none

echo '=== v2 baseline'
./.venv/bin/python docs/2080ti22gx2/bench_ds4.py v2-test
./.venv/bin/python docs/2080ti22gx2/bench_53k.py
echo '=== done; rollback: ./stop_ds4.sh && ./start_ds4.sh'
