#!/usr/bin/env bash
# sync.sh - 把 2080ti22GX2 与上游主干同步（合并，不 force push）
#
#   docs/2080ti22gx2/sync.sh          合并上游 main 到本分支并推送
#   docs/2080ti22gx2/sync.sh --check  只看差异，不合并
#
# 本分支只加了文档和脚本（docs/2080TI22GX2.md 与 docs/2080ti22gx2/），
# 所以与 main 的合并不会冲突。
set -euo pipefail
cd "$(dirname "$0")/../.."

BRANCH="2080ti22GX2"
REMOTE="fork"          # tonykee/project-maya

git fetch -q origin main

if [ "${1:-}" = "--check" ]; then
  echo "主干落后本分支 $(git rev-list --count origin/main..HEAD) 个提交，领先 $(git rev-list --count HEAD..origin/main) 个"
  git log --oneline HEAD..origin/main | head -20
  exit 0
fi

git checkout -q "$BRANCH"
git merge --no-edit origin/main
git push -q "$REMOTE" "$BRANCH"
echo "已同步：$(git log -1 --format='%h %s' | cut -c1-70)"
