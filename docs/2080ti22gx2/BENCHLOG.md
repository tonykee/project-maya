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


## 2026-11-05：PR #821 cache-aware expert substitution（DS4 decode，opt-in，改输出）

- 引擎：`/tmp/opencode/maya-pr821/build-pr821/maya-ds4`（PR 821 `5fbf233` + 本地 CUDA 修补：`ds4_model.cu` 将 `ds4_cache_sub_config.hpp` 改为非 HIP 条件包含）
- 配置基线：生产 `maya-ds4.json` 同参（TP=2, dspark on, mmap-experts off, experts 4, reserve-mib 768, gpu [1,0], 256K, `DS4_ENGRAM_CACHE_MB=2048` 等）
- 方法：PR 二进制跑 OFF/ON 两臂（排除版本差异），back-to-back 独立加载；`bench_ds4.py`（nonce prefill 1.6K/6.6K/13K + 256tok decode×3）+ `quality_ds4.py`（10 题，temp 0，reasoning off）

| 配置 | Decode 中位（256 tok） | Prefill 1.6K / 6.6K / 13K | quality_ds4.py | 结论 |
|---|---:|---:|---:|---|
| `MAYA_DS4_CACHE_SUB_RATIO=0` | **32.3** (30.6/35.4/32.3) | 415.9 / 762.2 / 957.3 | 7/10（fail: strict JSON, word reversal, count letter i） | OFF 基线 |
| `RATIO=0.1, N=12, BUDGET=0.6, NORM=reference` | **44.6** (44.6/53.3/41.6) | 405.4 / 763.5 / 946.9 | 8/10（fail: strict JSON, word reversal） | ✅ **decode +38.1%**，prefill ±1% 内；质量在该 10 题集未回退但样本小 |

- 启动确认（ON）：`ds4: APPROXIMATE cache substitution: ratio 0.1, top 12, reference normalization, mass budget 0.6; changes answers and depends on cache residency`
- 注意：#821 **改变模型输出**（近似推理），仅作用于 decode/target verification；prefill/drafter 原生。合入前需更广质量/真实任务回归；PR 说明 CUDA 执行此前未在作者工作站实测，本次在 2×2080 Ti 22G CUDA/sm_75 + TP=2 + Maya-XS GGUF 形态下验证可构建/可运行并获 decode 提升。

### 2026-11-05 详细质量 A/B（同上 PR 821 build/配置，30 题可验证，temp 0）

| 臂 | 得分 | 相对变化 |
|---|---:|---|
| OFF `RATIO=0` | **26/30** | 基线 |
| ON `RATIO=0.1,N=12,BUDGET=0.6` | **27/30** | **净 +1**，无系统性下滑迹象 |

- ON 修复：`arith_1234x5678`（OFF=7009752 错 → ON=7006652 对）、`json_extract`（OFF 输出带尾引号导致解析失败 → ON 通过）
- ON 回退：`count_letter_i`（OFF=4 对 → ON=3 错）
- 两者同错：`arith_multistep`（OFF=193, ON=172，均错，正确 219.5）、`word_reversal`（均得 `yarrubts`）
- 其余 25 题两臂一致通过（代码执行、JSON/SQL/regex、逻辑、needle 1K/4K、约束遵循、工具调用 JSON 形状等）。结果文件：`/tmp/opencode/maya-pr821/quality_pr821_off_detail.json`、`/tmp/opencode/maya-pr821/quality_pr821_on_detail.json`。

**解读**：#821 改变输出，存在个例波动（1 回退/2 修复/2 同错）属预期；在该 30 题自动回归集上**未观察到质量崩塌或系统性下滑**，与 decode +38% 的吞吐提升可并存。仍需在你真实工作负载（长生成、agent/工具调用、多轮、并发）上继续验证后再决定是否常开。

### 2026-11-05 NVLink peer prefill all-reduce（DS4 TP=2）
- 硬件：2× RTX 2080 Ti 22GB，NV2（2 link），CUDA P2P 可用（用户已验证）。
- 发现：显式 `MAYA_DS4_AR2=2` 会让 `init_peer_ar` 跳过该 TP2 组（`peer prefill all-reduce not selected for AR2/flow group` 逻辑）；`MAYA_DS4_HIP_PEER_AR=auto` 在本机因 probe 额外缓冲显存不足失败（`GPU0 has 543 MiB free, needs 544 (auto: + the probe's input row)`），回退 host transport，prefill 386/708/876。
- 生效配置：`MAYA_DS4_HIP_PEER_AR=1`（强制，省去 auto probe 额外行）+ 移除 `MAYA_DS4_AR2`，`MAYA_DS4_CACHE_SUB_RATIO=0.1` 保持。日志：`ds4: exact peer prefill all-reduce enabled on GPU0/GPU1 (320 MiB/rank)`。
- 结果（bench_ds4，nonce prefill + 256tok decode×3）：

| 配置 | Decode 中位 | Prefill 1.6K / 6.6K / 13.2K |
|---|---:|---:|
| `AR2=2`, 无 peer AR, `SUB=0.1`（前测） | 48.5 tok/s | 405 / 768 / 950 |
| `HIP_PEER_AR=auto`, 无 AR2（probe OOM 回退 host） | 49.5 tok/s | 386 / 708 / 876 |
| **`HIP_PEER_AR=1` 强制 NVLink peer, 无 AR2, `SUB=0.1`** | **51.7 tok/s** | **421 / 787 / 982** |

- 结论：在本机 NVLink + GeForce 2080 Ti P2P 可用前提下，**强制 peer prefill all-reduce** 比 `AR2=2` 更好；显存紧张时优先用 `HIP_PEER_AR=1` 而非 `auto`。

### 2026-11-05 `MAYA_DS4_AR2_DECODE=1` A/B（非 peer-VRAM decode all-reduce，精确）
- 前提：`HIP_PEER_AR=1`（NVLink peer prefill 生效）, `SUB=0.1`，`AR2` 未显式设置。
- 基线（同机紧接着，`AR2_DECODE` off）：prefill 437/782/968 tok/s，decode 中位 **58.1** (60.7/56.3/58.1)。
- 开启 `MAYA_DS4_AR2_DECODE=1`（日志确认 `decode windows' all-reduces ... in one launch ... sums bit for bit`）：prefill 422/786/981 tok/s，decode 中位 **49.4** (47.3/57.9/49.4)，**-15%**。
- **结论：无提升且回退，已撤销 `AR2_DECODE=1`，恢复基线配置。**

### 2026-11-05 DeepSeek Maya-XS v2 测试（同 v1 调优参数）
- 包：`/mnt/kioxia/Maya-data/models/DeepSeek-V4.1-Flash-1017-GGUF/Maya-XS/maya-ds4-v2`（v2 IQ1_S 3-shard GGUF 已存在，pack 含 `engram.bin`/`expert-profile.bin`/`slots`/`ds4.txt`/`tensors.txt`/`tokenizer`）。
- 参数（不变）：`--tp 2 --dspark on --mmap-experts off --experts 4 --reserve-mib 768 --max-context 262144`，`HIP_PEER_AR=1`，`CACHE_SUB_RATIO=0.1/N=12/BUDGET=0.6`，`DS4_ENGRAM_CACHE_MB=2048`，`DS4_STREAM_*/LAND/TP_SHARES` 等。启动确认 peer AR 与 substitution 均生效。
- 结果（bench_ds4 + quality_ds4 10 题）：

| 版本 | Decode 中位 | Prefill 1.6K / 6.6K / 13.2K | quality_ds4.py |
|---|---:|---:|---:|
| **v1 (maya-ds4)，同参数基线** | **~48–58 tok/s** | **~421–437 / 782–787 / 968–982** | 7–8/10（波动） |
| **v2 (maya-ds4-v2)，同参数** | **22.1** (19.5/24.3/22.1) | **107 / 292 / 414** | **9/10**（仅 word reversal fail） |

- 结论：**v2 在当前 v1 调优参数下“能跑、功能正常（peer AR/sub 生效）、质量样本 OK”，但吞吐严重回退**（decode -55%+，prefill -57%~75%）。README 称 v2 “更接近原始/+20% writing” 可能依赖不同默认/调优（专家槽/预留/Engram/内存布局/profile）；**v2 需要在本机单独重调（`--experts`、`--reserve-mib`、Engram/cache、profile/calibration、chunk/线程等）后再评估**，当前生产已恢复 v1。

### 2026-11-06 DeepSeek Maya-XS v2 物理分离+重建 pack+调优（目标：追平 v1）
- **环境/前提**：`Maya-XS-v2/` 物理分离（5 个大 GGUF 硬链接：3 个 v2 模型分片 + Engram 4/5；`dspark/vision` 共享），`tools/ds4/pack_gguf.py` 重建干净 `Maya-XS-v2/maya-ds4-v2`（48795 tensors，含 `dspark-xs2`/vision，`expert-profile.bin`/`slots` 由本机运行生成；旧坏 pack 备份 `maya-ds4-v2.broken-20261106`）。`start_ds4_v2.sh`/独立 config/pid/log。
- **根因（<20 tok/s）**：v2 基线漏 `MAYA_DS4_TP_GGUF_UNEVEN=1` → `tensor parallel 2 -> 1`（each GPU its own layers, 层 `[0,42]/[19,39]+head` 重叠）→ decode 17–19 / prefill 弱。修复后 TP2 uneven 生效（`DS4_TP_GGUF_UNEVEN`，part0/1）。
- **非 TP（`--tp 1` + layer-split auto）实测**：layer-split 模式，GPU 利用率 ~50%（pipeline 气泡/负载），decode ~10 tok/s 量级，**更差**；2×2080 Ti 22GB 上 v2 仍应走 TP2 uneven。

| 配置（均：TP2 uneven, pack=Maya-XS-v2/maya-ds4-v2, dspark on, engram2G, 2×2080Ti） | decode 中位数 tok/s | prefill tok/s (1.6k/6.6k/13.2k) | 备注 |
|---|---:|---:|---|
| 仅 `TP_GGUF_UNEVEN=1`，`--mmap-experts auto`，`--experts 6`，SUB0，无 peerAR | **8.4** | 256 / 268 / 374 | 修复 TP2 但缺 v1 结构参数，CPU lane 28-41% |
| +`--mmap-experts off --experts 4 --reserve-mib 768`，SUB0，无 peerAR | **11.8** | 128 / 319 / 433 | `experts 4 of 6` |
| +`HIP_PEER_AR=1` +`SUB=0.1` +`AR2=0` +v1 stream/land/slot_keep +`TP_SHARES=4,5`（=v1 结构+关键优化） | **22.7** | 117 / 318 / 453 | `exact peer prefill all-reduce` 生效，SUB 生效，CPU lane 9-13%，draft 接受率高；VRAM 2232/1848 in VRAM，218/1784 MiB free |
| 去掉 `TP_SHARES`（让引擎决定） | **22.2** | 120 / 327 / 470 | VRAM 2428/2044，256/346 MiB free，差异不大 |

- **对照 A/B（同机同时间状态，诊断用）**：v1 生产包/配置（`Maya-XS/maya-ds4`，5-shard，`HIP_PEER_AR+SUB`，原配置）→ **decode 25.7 tok/s，prefill 114 / 303 / 437**。v2 在等价配置下 **~22.7（≈ v1 当前的 88%）**，prefill 13k 略优/相当。
- **结论**：`TP_GGUF_UNEVEN` 缺失是 <20 的直接原因，已修复；`--tp 1` 非 TP 更差。当前 v2 与 v1 在**本机当前状态**下已接近（差距主要在 decode）。v1 历史 48–58 tok/s（见上文记录）与本次 25.7 差距大，**疑似机器状态退化**（此前 BENCHLOG 已提示多次重启/下载/OOM/page cache 后性能未回干净水平；`start_ds4_v2.sh` 偶发 health-check 误判已观察到）。建议**重启主机/恢复干净状态后**重跑 v1 与 v2 基线；再做 v2 专项：expert-profile/slots 预热、`--reserve-mib` 微调、在保证 VRAM/peer buffer 的前提下验证 SUB/peer AR 组合、必要时对 v2 跑 speed calibration。注意 `CACHE_SUB` 近似会改变输出（v1 亦开启）。

### 2026-11-06（重启后）v2 干净状态实测
- 配置：`TP2 uneven` + `--tp 2 --dspark on --mmap-experts off --experts 4 --reserve-mib 768` + `HIP_PEER_AR=1`(生效 320MiB/rank) + `SUB=0.1`(近似) + `AR2=0` + `TP_SHARES=4,5` + stream/land/slot_keep，`Maya-XS-v2/maya-ds4-v2`（重建 pack）。

| 时机 | decode 中位数 tok/s | prefill tok/s (1.6k/6.6k/13.2k) | 备注 |
|---|---:|---:|---|
| **重启后首轮加载**（reserve-mib 768） | **42.1** (41.2/44.3/42.1) | **438 / 806 / 1001** | CUDA0 226MiB free；13k prefill 达 1k tok/s |
| reserve-mib 512 A/B | 35.8 (39.8/35.8/22.6，不稳) | 397 / 714 / 886 | 更多 VRAM 专家但更差/不稳，**回退 768** |
| 同一开机后再次重启 v2 进程 | 23.2 | 423 / 430 / 462 | 再次出现运行/重载后退化（与历史“状态未回干净/重载退化”一致） |

- **结论**：重启后干净首轮可达 **~42 tok/s decode、13k prefill ~1k tok/s**（接近 v1 历史区间；decode 略低于 v1 最佳 58，部分来自 v2 权重配方——w2 在 12 层为 `IQ2_XXS` vs v1 纯 `IQ1_S`——及波动）。**v2 配置瓶颈已解决**；后续以“减少不必要重载/保持干净状态、profile/slots 预热、reserve-mib 保持 768”为主。

### 2026-11-06 追加：v2 重载/多轮掉速的定位与 settle 修复
- **现象**：v2 直接启动后首轮 41.6 / 1000；v1→停 v1→v2 后 decode 20–29、13k prefill 443；同一 v2 进程空闲约 5 分钟后自己回到 **40.2 / 986**（无需重启）。v1 也会短暂掉速（21.8 → 54.1）。
- **指标**（`GET /metrics` 的 `tiers.now`）：慢时 `vram_hit 0.74–0.85`、`cpu/ram_fetch 33–46`；快时 `0.93–0.97`、`6–12`；`engram_ms≈0.01`、`disk=0`。慢时 GPU 1.8GHz、PCIe Gen3 x16、NVLink 25.78GB/s 无错误、CPU 3.2–3.5GHz、内存带宽 37GB/s、96GB 区 2MB THP 均正常——**不是 OS/显卡驱动状态，也不是模型能力**。
- **根因**：VRAM 热点专家集合与当前/下一轮 prompt 的路由不匹配；v2 profile 更尖（本机 top16 占 55% vs v1 35%），切换模型/长 prompt 后更容易长时间低命中。多轮长 prompt 每轮都会重置 decode 的热点，所以“多轮”不等于“会自愈”。
- **修复/验证**：v2 配置加 `"DS4_SETTLE_MS": "2000"`（placement only）；同一条 v1→v2 路径上 109/443 prefill → **422/963**，decode 20–29 → **32–43**。`start_ds4_v2.sh` 在 ready 后调用 `tools/warmup_ds4.py`（短 decode + 1.6K/13K prefill，`MAYA_WARMUP=0` 跳过）。
- **未采用的尝试**：v1 profile 移植（decode 38.9，略差）、`--expert-profile none`（24.2，差）、自动 TP（4476 槽，prefill 970 / decode 38.7；能吃下卡1 的 1.6GB 但无速度收益）、`DS4_TP_SHARES=3,6`（3598 槽，更差）、`4,5:3,6`（4166 槽，无收益）、`DS4_SETTLE_MS=4000`（29–32，swap 排队拖慢）、`DS4_SETTLE_MS=500`（24.6，缓存太冷）、`CACHE_SUB_RATIO=0.2`（40–41，与 0.1 持平）、`CACHE_SUB_N=32`（39–42，持平）、显式 2MB hugepage 池（无稳定收益，已回滚）。卡1 的 ~1.6GB 空闲是 expert cache spare/prompt ring/reserve 的余量，硬填无收益，保留 `4,5`。
- **v2 上限（分工作集）**：2 轮预热后，匹配 warm-up 文本的 decode 到 **49.4 tok/s**（`vram_hit 0.99`、`cpu 2`），已基本到 v1 的 50；换成另一组代码 prompt 的 decode_bench 为 31–40，说明命中率取决于工作集。通用混合 prompt 的稳定区间仍是 40–42 / 970–1000 prefill。要把“任意 prompt 都 50”做成常态，需要按真实业务文本预热，或改 v2 的 `IQ2_XXS` 权重配方；单靠调参/提高 ratio 没有带来额外的稳定收益。
- **启动默认**：`start_ds4_v2.sh` 现在在 ready 后跑 `tools/warmup_ds4.py --rounds 2`（`MAYA_WARMUP=0` 跳过，`MAYA_WARMUP_ROUNDS=N` 调整）；v2 配置的 `DS4_SETTLE_MS=2000` 保持。

## 2026-11-16：从 Strata 迁到 Maya（DS4 GSQ-RCO + GLM-5.3-Flash）

Strata 主线 0.2.14 移除了 DeepSeek，GLM 也没有进主线的计划；两个模型改由 Maya 维护。
迁移不是重写引擎：Maya 已有 pack、config 和启动脚本，主要是把 Strata 的调优参数映射过来。

### DS4 GSQ-RCO（`maya-ds4-iq2xxs-vision`）

- 配置：`maya-ds4-gsq-iq2xxs-384k.json`（384K、vision、4 experts、10 CPU threads、8192 chunk、
  cache sub 0、DSpark off、`--suffix-draft 3`、`MAYA_DS4_VISION_RESIDENT=1`、port 8000）。
- 启动：`./start_ds4_gsq.sh`（保留 128 GB 2 MB 池）；停止：`./stop_ds4.sh`。
- 启动日志：114.4 GB CPU lane、13,303 experts、10 threads、2 MB huge pages；2,057 experts/card
  （vision resident）；copy 51.0 s。
- 首轮测试（`bench_ds4.py`，2K/8K/16K synthetic + 256-token code decode）：13.2K prefill
  **989 tok/s**，decode 中位 **25.1 tok/s**。这是 Maya 的 synthetic prompt，和 Strata 的 13K
  文档 prompt/128-token 不是同一题，不能直接当选胜；同 prompt A/B 还要再跑。
- Lookup（无 DSpark）：复制文本 `drafts 91 of 102 kept`，8-token 窗口，decode **42.46 tok/s**；
  Strata 同测试是 4-token 窗口、44/48、41.3。
- Vision：4 轮图片测试通过（“红色和蓝色” / “有”）；加载日志
  `the vision tower runs in the engine (GPU 0: 318 MiB kept)`。
- 旧 API model 名 `deepseek-v4.1-flash-gsq-rco-iq2_xxs-tp2` 仍被接受，客户端不用改。
- 修复：GSQ-RCO 的 GGUF mmproj vision 是 F32 marker + gate/up 拆分的 `mlp.w1`；Maya 的 loader
  只收 BF16。提交 `e18d82c` 加了 F32→BF16 的 `read_bf16` 和 gate/up 合并。

### GLM-5.3-Flash Maya-S24

- 配置：`maya-maya-s24.json`（262K、KV int8、expert-cache-per-layer、GLM 调优 env、vision），
  port 8000。
- 启动：`./start_glm.sh`；停止：`./stop_glm.sh`。和 DS4 二选一（44 GB 显存放不下两个）。
- 测试：13.5K prefill **716.9 tok/s**（旧 v1.1.46 基线 608），256-token decode 中位
  **37.4 tok/s**（旧 33.8，+11%），draft 184-233/254；图片问答“这张图主要是红色和蓝色。”通过。
- 注意：`MAYA_GLM_DEFER_CPU=2` 是有损项，当前配置保留；如果更看重答案一致性，设 0/去掉。

### 切换

```sh
# DS4
./stop_glm.sh 2>/dev/null || true
./start_ds4_gsq.sh

# GLM
./stop_ds4.sh
./start_glm.sh
```

`stop_ds4.sh` 会把 128 GB 大页池还给系统；`start_ds4_gsq.sh` 再预留。两个模型不能同时跑。

## 2026-11-17：CPU 升级到 E5-2696 v4（22C/44T）后的基线

### 硬件

- CPU：Intel Xeon E5-2696 v4，22 核 / 44 线程，55 MB L3，2.2 GHz 基频。
- 内存：251 GB（8×32 GB DDR3 RDIMM，X99-T8）；11-15 修复后 sysbench 256M×8 约 **80 GB/s**（修复前约 9.5 GB/s）。
- 自动线程数：GLM **21**（22 物理核 − 1，两 GPU 共享池）；DS4 **22**（一物理核一线程，含 service）。

### 结果（`--bench`，greedy，thinking off，256 token）

| 模型 | 配置 | Decode 平均 | 单题 | 8K prefill | 备注 |
|---|---|---:|---|---:|---|
| GLM-5.3-Flash Maya-S24 | `maya-maya-s24.json`，262K | **40.3** tok/s | 39.3 / 41.4 / 40.1 | 581 tok/s | 旧 CPU 同口径 36.2（**+11.3%**）；CPU lane 21 线程，0.21 ms/expert |
| DeepSeek GSQ-RCO IQ2_XXS | `maya-ds4.json`，32K，DSpark on | **46.1** tok/s | 42.9 / 40.9 / 54.6 | 618 tok/s | 旧 CPU 参考：GSQ 服务日志 31–33，BENCHLOG Maya-XS 40–42（配置/口径不同）；CPU lane 22 线程 |

- GLM 旧最好 38.4 → **40.3**；旧 CPU 同口径 36.2。
- DS4 加载 58 s，117.7 GB 专家复制进 RAM 34.9 s。
- DS4 `--cpu-threads 20` A/B：**46.6**（45.0 / 40.2 / 54.5）vs 自动 22 的 46.1，差 1.1%，在噪声内 → **保留自动 22**。
- 注意：DS4 连续跑 `--bench` 时 2K/8K prefill 会命中上一次的会话槽（27K/96K tok/s），不是真实值；测 prefill 需要唯一 nonce 或先清 slots。

### GLM 官方校准（`tools/calibrate_glm.py`）

- share sweep：0.00 36.0 / **0.10 40.8** / 0.25 39.9 / 0.50 32.6 / 0.75 29.3 tok/s。
- thread sweep：21 34.1 / 16 38.9 / 14 35.3 / 10 27.5 / 5 15.1 tok/s。
- confirmation 后保留 **`MAYA_GLM_PCIE_SHARE=0.36` + 21 线程**（校准内 37.3 tok/s）。
- 手动 `--bench` 复测 share 0.10：**34.0 tok/s**，明显低于 0.36 的 40.3 → 确认 0.36 是对的，不采用单轮 40.8。

### 配置变更

- `maya-ds4-gsq-iq2xxs-cpu8.json`、`maya-ds4-gsq-iq2xxs-384k.json`：删除 `--cpu-threads 8/10`，交回引擎自动（新 CPU 下 22）。
- `maya-ds4.json`、`maya-maya-s24.json` 的线程数本来就自动，无需写死。
- 结果文件：`maya-bench.txt`（GLM 40.3）、`maya-bench.txt.ds4-auto22.bak`（DS4 46.1）、`maya-bench.txt.ds4-cpu20.bak`（DS4 20 线程 46.6）、`logs/bench-20261117-0955-glm-newcpu.log`、`logs/bench-20261117-0958-ds4-newcpu.log`。

## 2026-11-17：CPU 升级到 Xeon E5-2696 v4（22C/44T）

所有启动项不再写死 CPU lane 线程数：

- DS4：活动配置里没有 `--cpu-threads`；默认 0 = 一物理核一线程（22）。
- GLM Maya-S24：没有 `MAYA_GLM_CPU_THREADS`；默认按物理核。
- GLM Swift：从 `/mnt/kioxia/maya-glm/maya-swift-glm.json` 删掉 `MAYA_GLM_CPU_THREADS=10`。
  两个 GPU part 时 GLM 默认留一个服务核，日志是 **21 threads**。

Swift 用同一套 `decode_bench.py` / `bench_ab.py` 复测：

| 项目 | 旧 10 线程 | 新 21 线程 | 变化 |
|---|---:|---:|---:|
| 256-token decode 中位 | 33.4 | **36.1** | +8.1% |
| 13.5K prefill | 721.8 | **736.6** | +2.1% |

CPU lane 每个专家的时间从 0.601/0.452 ms 降到 **0.253/0.198 ms**（CUDA0/CUDA1）。
单次测量，主机状态有波动；Maya-S24 和 DS4 在新 CPU 上还没重测。
