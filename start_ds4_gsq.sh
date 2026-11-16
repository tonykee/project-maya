#!/usr/bin/env bash
# Start the GSQ-RCO IQ2_XXS DeepSeek on the 2x RTX 2080 Ti with the config migrated
# from Strata.  Keeps the 128 GB 2 MB huge-page pool unless DS4_COPY_HUGETLB=0 is set.
# Stop with ./stop_ds4.sh (it also returns the pool).
set -euo pipefail
cd "$(dirname "$0")"

export MAYA_CONFIG="${MAYA_CONFIG:-maya-ds4-gsq-iq2xxs-384k.json}"
export DS4_COPY_HUGETLB="${DS4_COPY_HUGETLB:-1}"
export DS4_HUGEPAGE_GB="${DS4_HUGEPAGE_GB:-128}"

exec ./start_ds4.sh "$@"
