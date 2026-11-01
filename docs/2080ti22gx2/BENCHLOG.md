# 基准台账（2× 2080 Ti 22G / sm_75）

每次合并上游提交前后，在同一组 prompt 上测一次，追加一行。**测 prefill 必须用唯一 nonce**（否则会命中会话槽，得到 0.08 秒的假数据）。

## 基线（v1.1.46，2026-11-01）

| 模型 | Decode（256 tok 中位） | Prefill ~1.7K | Prefill ~5.8K | Prefill ~13.5K | 备注 |
|---|---:|---:|---:|---:|---|
| GLM-5.3 Maya-S24 | 33.8 | 300 | 477 | 608 | 256K，MISS_SKIP 0.12，DEFER_CPU=2（#722） |
| DeepSeek Maya-XS | 41.6 | 235 | 504 | 665 | 256K，experts 4，chunk 8192，IQ1_S 向量化（#695） |
| MiniMax Maya-XS | 10.1 | 99 | 135 | 143 | 131K，chunk 8192 |

## 验证记录

| 日期 | 上游提交 | 内容 | GLM dec/pre13K | DS dec/pre13K | 结论 |
|---|---|---|---:|---:|---|
| 2026-11-01 | v1.1.46 | 基线（无新 PR） | 31.3 / 602 | 31.0 / 652 | 采用 |
| 2026-11-01 | PR #722 | GLM `MAYA_GLM_DEFER_CPU=2` | **33.8 / 608** | — | ✅ +8.0%，prefill 无退化 |
| 2026-11-01 | PR #695 | CPU lane IQ1_S 向量化（逐位一致） | — | **41.6 / 665** | ✅ +34%，prefill 略升 |
| 2026-11-01 | #722+#695 | 合并版复测（冷/热） | — | 36.8 → **41.2** / 660 | ✅ 与单独 #695 一致 |

## 测法

```bash
# DeepSeek（默认在跑）
cd /mnt/kioxia/maya
./.venv/bin/python docs/2080ti22gx2/bench_ds4.py "标签"

# GLM：先 ./stop_ds4.sh，再 ./start_glm.sh，然后
./.venv/bin/python docs/2080ti22gx2/decode_bench.py "标签"   # decode（256 tok，才有意义）
./.venv/bin/python docs/2080ti22gx2/bench_ab.py "标签"       # prefill（只生成 4-8 tok，decode 列别用）

# MiniMax：./stop_ds4.sh && ./start_mm3.sh
./.venv/bin/python docs/2080ti22gx2/bench_mm3.py "标签"
```

判定标准：

- **decode 或 prefill 掉 >3%** → 视为回退，不合入
- **±3% 内** → 无变化，按需合入（修 bug 就合，纯重构可不合）
- **提升 >3%** → 合入，并更新本文的基线表
