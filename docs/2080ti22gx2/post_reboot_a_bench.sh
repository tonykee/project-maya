#!/usr/bin/env bash
# 重启后：启动 v1.1.52（完整 Engram）、预热 Engram 表、跑 A 基线（不续传 v2）
set -euo pipefail
cd /mnt/kioxia/maya
D=/mnt/kioxia/Maya-data/models/DeepSeek-V4.1-Flash-1017-GGUF/Maya-XS

./start_ds4.sh

echo '=== warm Engram tables (2x400MB)'
dd if="$D/DeepSeek-V4.1-Flash-1017-Maya-XS-IQ1_S-00004-of-00005.gguf" of=/dev/null bs=1M count=400 status=none
dd if="$D/DeepSeek-V4.1-Flash-1017-Maya-XS-IQ1_S-00005-of-00005.gguf" of=/dev/null bs=1M count=400 status=none

echo '=== A baseline'
./.venv/bin/python docs/2080ti22gx2/bench_ds4.py post-reboot-A
./.venv/bin/python docs/2080ti22gx2/bench_53k.py

echo '=== done; resume v2 with: bash docs/2080ti22gx2/resume_ds4_v2.sh'
