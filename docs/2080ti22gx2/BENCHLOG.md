# 基准台账（2× 2080 Ti 22G / sm_75）

每次合并上游提交前后，在同一组 prompt 上测一次，追加一行。**测 prefill 必须用唯一 nonce**（否则会命中会话槽，得到 0.08 秒的假数据）。

## 基线（v1.1.46，2026-11-01）

| 模型 | Decode（256 tok 中位） | Prefill 1.6K | Prefill 6.5K | Prefill 13K | 备注 |
|---|---:|---:|---:|---:|---|
| GLM-5.3 Maya-S24 | 32.1 | 330 | 489 | 641 | 256K，MISS_SKIP 0.12 |
| DeepSeek Maya-XS | 30.3（峰值 34.2） | 203 | 483 | 641 | 256K，experts 4，chunk 8192 |
| MiniMax Maya-XS | 10.1 | 99 | 135 | 143 | 131K，chunk 8192 |

## 验证记录

| 日期 | 上游提交 | 内容 | GLM dec/pre13K | DS dec/pre13K | 结论 |
|---|---|---|---:|---:|---|
| 2026-11-01 | v1.1.46 | 基线 | 32.1 / 641 | 30.3 / 641 | 采用 |

## 测法

```bash
# DeepSeek（默认在跑）
cd /mnt/kioxia/maya
./.venv/bin/python docs/2080ti22gx2/bench_ds4.py "标签"

# GLM：先 ./stop_ds4.sh，再 ./start_glm.sh，然后
./.venv/bin/python docs/2080ti22gx2/bench_ab.py "标签"

# MiniMax：./stop_ds4.sh && ./start_mm3.sh
./.venv/bin/python docs/2080ti22gx2/bench_mm3.py "标签"
```

判定标准：

- **decode 或 prefill 掉 >3%** → 视为回退，不合入
- **±3% 内** → 无变化，按需合入（修 bug 就合，纯重构可不合）
- **提升 >3%** → 合入，并更新本文的基线表
