#!/usr/bin/env bash
# One clean X99 benchmark after a fresh boot (no desktop, so no LACT power cap).
# Run from a text console after `systemctl set-default multi-user.target` + reboot:
#   cd /mnt/kioxia/maya
#   ./docs/2080ti22gx2/bench_headless.sh x99-headless-250
#
# The 53K run is deliberately the LAST request: it fills the VRAM expert cache,
# so a second run without a service restart is not comparable.
set -euo pipefail
cd "$(dirname "$0")/../.."

LABEL="${1:-x99-headless}"
LOG="logs/${LABEL}-$(date +%Y%m%d-%H%M%S).log"
mkdir -p logs
exec > >(tee -a "$LOG") 2>&1

echo "== $LABEL  $(date)"
echo "boot: $(uptime -s)"
echo "--- GPU power limit / clocks"
nvidia-smi --query-gpu=index,name,power.limit,power.default_limit,clocks.sm,clocks.mem --format=csv
echo "--- CPU governor"
for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do cat "$f" 2>/dev/null; done | sort | uniq -c
echo "If the GPU limit is 250W this matches the old SSH baseline; for 220W run:"
echo "  sudo nvidia-smi -i 0,1 -pl 220"
echo "For max CPU clocks: sudo cpupower frequency-set -g performance"
echo

if curl -sf -m 2 -H "Authorization: Bearer llama_local" http://127.0.0.1:8000/health >/dev/null; then
  echo "WARNING: DS4 is already running. For a clean baseline, reboot or stop/start it first."
  echo "         The expert cache may already be polluted; results may be low."
else
  echo "--- starting DS4 (about 8-10 minutes)"
  ./start_ds4.sh
fi

echo
echo "--- 1.6K / 6.6K / 13K + decode"
./.venv/bin/python docs/2080ti22gx2/bench_ds4.py "$LABEL"

echo
echo "--- single 53K cold prefill (must be last)"
./.venv/bin/python docs/2080ti22gx2/bench_53k.py

echo
echo "--- done"
echo "log: $LOG"
