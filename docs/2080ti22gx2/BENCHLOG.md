# 基准台账（2× 2080 Ti 22G / sm_75）

每次合并上游提交前后，在同一组 prompt 上测一次，追加一行。**测 prefill 必须用唯一 nonce**（否则会命中会话槽，得到 0.08 秒的假数据）。

## 基线（v1.1.46，2026-11-01）

| 模型 | Decode（256 tok 中位） | Prefill ~1.7K | Prefill ~5.8K | Prefill ~13.5K | 备注 |
|---|---:|---:|---:|---:|---|
| GLM-5.3 Maya-S24 | 33.8 | 300 | 477 | 608 | 256K，MISS_SKIP 0.12，DEFER_CPU=2（#722） |
| DeepSeek Maya-XS | 39.6 | 247 | 544 | 730 | 256K，experts 4，chunk 8192，IQ1_S 向量化（#695），AR2=2 |
| MiniMax Maya-XS | 10.1 | 99 | 135 | 143 | 131K，chunk 8192 |

## 验证记录

| 日期 | 上游提交 | 内容 | GLM dec/pre13K | DS dec/pre13K | 结论 |
|---|---|---|---:|---:|---|
| 2026-11-01 | v1.1.46 | 基线（无新 PR） | 31.3 / 602 | 31.0 / 652 | 采用 |
| 2026-11-01 | PR #722 | GLM `MAYA_GLM_DEFER_CPU=2` | **33.8 / 608** | — | ✅ +8.0%，prefill 无退化 |
| 2026-11-01 | PR #695 | CPU lane IQ1_S 向量化（逐位一致） | — | **41.6 / 665** | ✅ +34%，prefill 略升 |
| 2026-11-01 | #722+#695 | 合并版复测（冷/热） | — | 36.8 → **41.2** / 660 | ✅ 与单独 #695 一致 |
| 2026-11-01 | `DS4_AR2=2` | prompt all-reduce FP16 线上 | — | **39.6 / 730** | ✅ +10% prefill；10 题 9/10 与 AR2=1 相同 |
| 2026-11-02 | chunk 16384 + 小开关 | 专家槽 1694/1310 | — | 585 / 35.0 | ❌ −20%，chunk 借走 4GB 专家槽 |
| 2026-11-02 | chunk 8192 + 小开关组 | 2280/1896 | — | 700 / 36.0 | ❌ 小开关合计 −4~5%，revert |
| 2026-11-02 | **最终：AR2=2 + budget 2048** | 2263/1879 | — | **693 / 39.5（质量 10/10）** | ✅ 保留 |

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

## 2026-11-04：v1.1.52 / GLM-5.3 A/B 与 Engram 包变更

### GLM-5.3 Maya-S24（v1.1.52，Maya-S24）

| 配置 | Decode | Prefill 1.6K / 6.6K / 13K | 结论 |
|---|---:|---:|---|
| baseline | 34.3 | 349.1 / 525.8 / 677.3 | — |
| `MAYA_GLM_PREFILL_CPU_GATE=0` | 34.5 | **401.3 / 547.9 / 715.6** | ✅ 采用 |
| `MAYA_GLM_PCIE_SHARE=0.25` | 34.5 | 同 gate0 | ➖ 中性，保留 |
| #460 `RAM_INCLUSIVE` | **30.8** | 404.9 / 553.1 / 719.2 | ❌ decode −10.7%，revert |
| 质量 10 题 | — | 9/10（仅词序反转失败，算术通过） | ✅ |

最终 GLM 配置：`gate0 + PCIE_SHARE=0.25`，无 `RAM_INCLUSIVE`。

### DeepSeek v1.1.52 A/B（Maya-XS，pack 已含 Engram）

| 配置 | Decode | Prefill 1.6K / 6.6K / 13K / 53K | 结论 |
|---|---:|---:|---|
| v1.1.50 旧 pack（无 Engram，10:38） | 35.8 | 405.4 / 763.6 / 953.5 / **1112.0** | 旧基线 |
| v1.1.52 A（旧 config，11:38，page cache 热） | 35.4 | 400.5 / 767.6 / 949.3 / 828.1 | 53K −25% |
| v1.1.52 B（setup-new） | 10.6 | 372.5 / 534.0 / 361.3 / 538.8 | ❌ 不可用 |
| v1.1.50（新 pack，冷 cache） | 17.1 | 108 / 276 / 390 / 573 | ❌ Engram 读盘 |
| v1.1.52 A 复测（冷 cache） | 16.4 | 108 / 276 / 395 / 581 | ❌ 冷 Engram |
| v1.1.52 + `DS4_ENGRAM_CACHE_MB=2048`（warm1） | 16.9 | **395.7 / 772.6** / 471.5 / 574.1 | 短 prompt 恢复 |
| 同上（warm2） | 25.2 | 114 / 277 / 386 / 566 | 13K/53K 仍慢 |

### 测试 2/3（v1.1.50，新 pack）

| 测试 | Decode | Prefill 1.6K / 6.6K / 13K / 53K | 结论 |
|---|---:|---:|---|
| 2：`MAYA_DS4_SLOT_CAP=16` + `MAYA_DS4_ENGRAM_CACHE_MB=16384` | 16.4 | 108 / 275 / 390 / 577 | ❌ 变量名错误，无效果 |
| 3：`--dspark off` | 15.8 | 108 / 277 / 389 / 575 | ❌ 无效果，保持 DSpark on |

### Engram 根因与坑

- 11:21 的 v1.1.52 setup 重建 pack，加入 **Engram（layers 1/14，Q6_K 表约 768MB）**；10:38 的 v1.1.50 跑的是旧 pack（无 Engram），所以 1112 tok/s。
- Engram 行默认从模型文件读，行缓存只有 16–256MB；v2 下载把 page cache 挤掉后，v1.1.50/v1.1.52 都掉到 ~580。
- **`DS4_ENGRAM_RAM=1` 是坑**：实际锁的是整个 80.64GB 分片文件（file 3 全锁 + file 4 43GB），直接 OOM（内核杀进程，file-rss 124.7GB）。**不要用**。
- 可用的缓解：`DS4_ENGRAM_CACHE_MB=2048` + 启动后手动预热 Engram 表到 page cache；`DS4_ENGRAM_PREFETCH` 在 TP=2 下不生效（代码要求单 GPU）。
- `--reserve-mib 300` 对 v1.1.50 太紧：CUDA0 只剩 78MB，64MB IQ scratch 分配失败会走慢速回退；改为 **768**（约 3% 专家槽）。
- 多次重启 + v2 下载/一次 OOM 后，主机内存/驱动状态仍未回到 10:38 的干净水平；建议**重启**后再跑 A 基线确认 828。


### 2026-11-04 重启后 A 基线（完整 Engram）

| 时间 | 配置 | Decode | Prefill 1.6K / 6.6K / 13K / 53K | 结论 |
|---|---|---:|---:|---|
| 18:3x | v1.1.52 + `DS4_ENGRAM_CACHE_MB=2048` + 预热 2×400MB | 34.9 | **406.8 / 768.3 / 953.7 / 1107.7** | ✅ 完整 Engram 追平旧 1112 |

- **828 是冷缓存/主机状态低值，不是 Engram 的固有代价**；重启 + 预热后完整 v1.1.52 与旧 v1.1.50（无 Engram）的 1112 持平/略好。
- 生产定稿：v1.1.52（24df320）+ 完整 Engram + 2GB 行缓存 + `--reserve-mib 768`。**不需要 no-Engram 变体。**
- v2 下载已续传（58%+）；下载会挤 page cache，若 53K 掉速可暂停下载或依赖 2GB 行缓存。

