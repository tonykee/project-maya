#!/usr/bin/env bash
set -uo pipefail
cd /mnt/kioxia/maya

LOCK="/tmp/watch_gsq_iq2_xxs.lock"
LOG="logs/watch-gsq-iq2_xxs.log"
DL="./dl_gsq_rco_iq2_xxs.sh"
DL_LOG="logs/download-gsq-rco-iq2_xxs.log"

exec 9>"$LOCK" || exit 0
flock -n 9 || exit 0

ts() { date '+%F %T'; }

# if main download/check script process running, nothing to do
if pgrep -f "dl_gsq_rco_iq2_xxs.sh" >/dev/null 2>&1; then
  exit 0
fi

# check completion
if "$DL" --check >/tmp/gsq_iq2_xxs_check.out 2>&1; then
  echo "$(ts) [watch] download complete, no action" >> "$LOG"
  exit 0
fi

echo "$(ts) [watch] downloader not running and not complete, restarting..." >> "$LOG"
setsid bash -lc "nohup $DL >> $DL_LOG 2>&1 &" >> "$LOG" 2>&1
echo "$(ts) [watch] restart issued" >> "$LOG"
