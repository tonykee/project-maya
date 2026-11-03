#!/usr/bin/env bash
# Resume the Maya-XS v2 download after a network drop.
# The shard 3 is already complete; this fetches the two model shards only.
# curl -C - continues from the bytes on disk, so nothing is downloaded twice.
set -euo pipefail
cd "$(dirname "$0")/../.."

BASE="https://huggingface.co/peasantsmith/DeepSeek-V4.1-Flash-1017-Maya-GGUF/resolve/c33d87b8c7a3b7d55e71324dc82395587a870b0b"
DEST="/mnt/kioxia/Maya-data/models/DeepSeek-V4.1-Flash-1017-GGUF"
FILES=(
  "Maya-XS/DeepSeek-V4.1-Flash-1017-Maya-XS-v2-IQ1_S-00001-of-00003.gguf"
  "Maya-XS/DeepSeek-V4.1-Flash-1017-Maya-XS-v2-IQ1_S-00002-of-00003.gguf"
)

for f in "${FILES[@]}"; do
  curl -L -C - --retry 100 --retry-delay 10 --fail -o "$DEST/$f" "$BASE/$f" &
done
wait
echo "DONE"
