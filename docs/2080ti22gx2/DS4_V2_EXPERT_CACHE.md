# DeepSeek V4.1 Maya-XS v2 重载/多轮掉速：expert cache 与 `DS4_SETTLE_MS`

> 记录日期：2026-11-06  
> 机器：2× RTX 2080 Ti 22GB（NVLink NV2，PCIe 3.0 x16），Xeon E5-2666 v3，128GB DDR4，KIOXIA NVMe  
> 模型：`Maya-XS-v2/maya-ds4-v2`（DeepSeek-V4.1-Flash-1017 v2），`--tp 2 --dspark on --mmap-experts off --experts 4 --reserve-mib 768`

## TL;DR

- 掉速不是操作系统、显卡驱动或模型能力的问题，是 **DS4 的 VRAM 热点专家集合与当前 prompt 的路由不匹配**。
- 慢时 `/metrics` 的 `vram_hit` 从 0.95+ 掉到 0.74–0.85，`cpu/ram_fetch` 从约 10 涨到 33–46，于是 prefill 和 decode 一起掉约一半。
- 修复：v2 配置加 **`DS4_SETTLE_MS=2000`**，并在启动后跑 **2 轮预热**（`tools/warmup_ds4.py`）。
- 实测：v1→v2 后 decode 20–29 → **32–49 tok/s**，13K prefill 443 → **约 960–1000 tok/s**；匹配工作集时最好到 **49.4 tok/s**。
- v2 的通用混合 prompt 稳定区间仍是 **40–42 tok/s / 970–1000 prefill**；v1 为 54–58，剩余差距主要来自 v2 的 12 层 `IQ2_XXS`（v1 纯 `IQ1_S`）。
- CUDA1 剩余的约 1.6GB 不建议硬填专家：试过 `3,6`、自动 TP、`4,5:3,6`，能多塞槽位但没有速度收益，`4,5` 仍最好。

## 现象

1. 直接启动 v2：首轮约 **41.6 tok/s decode、1000 tok/s（13K prefill）**。
2. 停 v2 再启 v2：仍约 **39–41 tok/s**，正常。
3. 启动 v1、再停 v1、再启 v2：v2 掉到 **20–29 tok/s decode**，13K prefill 掉到 **443 tok/s**。
4. 同一 v2 进程空闲约 5 分钟后，自己回到 **40.2 tok/s / 986 tok/s**，不需要重启。
5. v1 也会短暂掉速：从 v2 切到 v1 后第一轮 21.8 tok/s，几分钟后回到 **54.1 tok/s / 952 prefill**。

## 关键证据

### `/metrics` 的 `tiers.now`

```bash
curl -s -H "Authorization: Bearer $KEY" http://127.0.0.1:8000/metrics \
  | jq '.tiers.now | {tok_s,vram_hit,cpu,ram_fetch,engram_ms,disk}'
```

| 状态 | decode | `vram_hit` | `cpu` / `ram_fetch` | `engram_ms` | `disk` |
|---|---:|---:|---:|---:|---:|
| 慢 | 16–29 | 0.74–0.85 | 33–46 | ~0.01 | 0 |
| 快 | 40–49 | 0.93–0.99 | 2–12 | ~0.02–0.7 | 0 |

`vram_hit` 下降、`cpu/ram_fetch` 上升，说明更多专家从 VRAM 退回 CPU/RAM lane；`engram_ms` 和 `disk` 都很低，所以不是 Engram 或磁盘 I/O。

### 慢的时候硬件是正常的

- GPU SM 时钟约 1.8GHz，显存 6800MHz，功耗 200–229W，无 thermal/power throttle
- PCIe 负载时 Gen3 x16
- NVLink 两条链路各 25.781GB/s，Replay/Recovery/CRC 错误全 0
- CPU 3.2–3.5GHz，约 46–54°C
- 主机内存带宽实测约 **37GB/s**
- 96GB 专家区拿到 2MB THP（`AnonHugePages ≈ 94GB`）

因此不是“操作系统/驱动里卡了一个永久低性能状态”。

### v2 与 v1 的 profile 差异

本机 `expert-profile.bin` 统计：

| | 累计命中 | 每层 top16 专家占比 |
|---|---:|---:|
| v1 | 8.43 亿 | 34.8% |
| v2 | 0.57 亿 | 54.9% |

v2 的 profile 更“尖”，切换模型/长 prompt 后更容易长时间低命中；v1 更分散，恢复更快。这解释了“v1 看起来没事、v2 更严重”。

## 根因

DS4 是分层专家缓存：一部分专家在 VRAM，其余在 RAM/CPU lane。

长 prompt 是分块读的。读完 prompt 后，引擎默认不会把这一轮 prompt 的路由结果像逐 token decode 那样喂给 expert cache，于是 decode 开始时 VRAM 里还是上一轮的热点集合：

- prompt 的专家不在 VRAM → 大量 CPU/RAM 访问 → prefill/decode 一起变慢；
- 下一轮长 prompt 又重置热点 → 多轮对话不等于“会自愈”；
- 空闲几分钟后后台 swap 落完，才会恢复。

源码里对应的注释在 `src/ds4/ds4_model.cu`：

> a run of chunks is a single tick and fed it nothing, so the decode after a long prompt found the cache as the prompt before had left it

## 修复

### 1. v2 配置：`DS4_SETTLE_MS=2000`

在 `maya-ds4-v2.json` 的 `env` 中加入：

```json
{
  "DS4_SETTLE_MS": "2000"
}
```

含义：一个 chunked prompt 读完后，最多花 2000ms，把这轮 prompt 实际用得最多的 CPU-lane 专家换进 VRAM，替换最冷的 VRAM 专家，然后开始 decode。

- 只影响专家放置，**不改变模型输出**
- 是上限，不是每次都固定 2 秒；没有值得搬的专家会提前结束
- 别名：`MAYA_DS4_SETTLE_MS`
- 文档：`docs/SETTINGS.md` 的 `MAYA_DS4_SETTLE_MS`

### 2. 启动预热：`tools/warmup_ds4.py`

`start_ds4_v2.sh` 在 `/health` ready 后自动执行 2 轮：

```text
短 decode → 1.6K prefill → 13K prefill → 128-token decode
（重复 2 轮）
```

用法：

```bash
./start_ds4_v2.sh                 # 默认预热 2 轮
MAYA_WARMUP=0 ./start_ds4_v2.sh   # 跳过预热
MAYA_WARMUP_ROUNDS=3 ./start_ds4_v2.sh
```

预热脚本是 best effort：失败不会阻止服务启动，`start_ds4_v2.sh` 里还有 240s 超时。

> 预热文本目前是固定的 MoE 说明。若你的真实业务是代码/agent/长文档，可把 `tools/warmup_ds4.py` 里的 `BASE` 换成代表性文本，命中率会更贴近实际。

## 验证数据

### v1 → v2 路径

| 配置 | decode | 13K prefill |
|---|---:|---:|
| 无 settle | 20–29 | 443 |
| `DS4_SETTLE_MS=2000` | 32–43 | 422 / 963 |
| 2 轮预热后（匹配工作集） | **49.4**（最好） | 约 970–1004 |
| 空闲 5 分钟后 | 40.2 | 986 |

### 通用 bench（`docs/2080ti22gx2/bench_ds4.py`）

| 场景 | decode 中位 | prefill 1.6K / 6.6K / 13K |
|---|---:|---:|
| v2 + settle + 2 轮预热 | 40–42 | 487 / 820 / **1004** |
| v1 热态参考 | 54.1 | 444 / 772 / 952 |
| v2 干净首轮（历史记录） | 42.1 | 438 / 806 / 1001 |

## 为什么 v2 不总能到 50

- 匹配 warm-up 的工作集：**43–49.4 tok/s**，基本到 v1 的 50。
- 任意混合 prompt：**40–42 tok/s**。
- v1：**54–58 tok/s**。

剩余差距主要来自 v2 的权重配方：v2 有 12 层 `IQ2_XXS`，v1 是纯 `IQ1_S`（见 `BENCHLOG`）。要把“任意 prompt 都 50”做成常态，只有：

1. 用真实业务文本预热；
2. 把 v2 的 12 层 `IQ2_XXS` requant 成 `IQ1_S`（会改变 v2 权重和输出质量）。

单纯调参/提高 cache substitution ratio 没有带来额外的稳定收益。

## 失败/未采用的尝试

| 尝试 | 结果 | 结论 |
|---|---|---|
| 把 v1 的 `expert-profile.bin` 复制给 v2 | decode 38.9 | 略差，回滚 |
| `--expert-profile none` | decode 24.2 | 明显差，回滚 |
| 去掉 `DS4_TP_SHARES`（自动 TP） | 4476 槽，prefill 970 / decode 38.7 | 能吃卡1 空间，但无速度收益 |
| `DS4_TP_SHARES=3,6` | 3598 槽，卡0 反而剩 3.3GB | 更差，回滚 |
| `DS4_TP_SHARES=4,5:3,6` | 4166 槽，卡0 剩 1.46GB | 无收益，回滚 |
| `DS4_SETTLE_MS=4000` | decode 29–32 | swap 排队，拖慢 |
| `DS4_SETTLE_MS=500` | decode 24.6 | 缓存太冷 |
| `CACHE_SUB_RATIO=0.2` | decode 40–41 | 与 0.1 持平，不值得多牺牲质量 |
| `CACHE_SUB_N=32` | decode 39–42 | 与 12 持平 |
| 显式 2MB hugepage 池 + `DS4_COPY_HUGETLB=1` | 无稳定收益 | 已回滚/释放 |

### CUDA1 的 1.6GB 为什么不建议硬填

`DS4_TP_SHARES=4,5` 下卡1 约 1.6GB 空闲，这部分是 expert cache 的 spare slot、prompt ring、`--reserve-mib 768` 和 vision 的余量。试过：

- 自动 TP：槽位 4476，卡1 只剩 338MiB，prefill 970 / decode 38.7；
- `3,6`：槽位 3598，卡0 剩 3.3GB；
- `4,5:3,6`：槽位 4166，卡0 剩 1.46GB。

都能“多填”，但没有带来速度收益，甚至破坏两卡的负载平衡。因此保留 `4,5`。

## NVLink 使用情况

- **prefill**：`exact peer prefill all-reduce enabled on GPU0/GPU1 (320 MiB/rank)`，走 NVLink P2P。
- **decode**：不走 NVLink；默认 host/PCIe。`MAYA_DS4_AR2_DECODE=1` 之前实测 -15%，不建议开。
- 验证：`nvidia-smi topo -p2p r` = OK，`nvidia-smi nvlink -s` = 25.781GB/s，`-e` 错误为 0。
- 该驱动/GeForce 上 `nvidia-smi nvlink -gt d` 返回 N/A，无法直接读吞吐计数器；以启动日志 + P2P 状态 + A/B 为准。

## 最终配置

`maya-ds4-v2.json` 的 `env`：

```json
{
  "DS4_SETTLE_MS": "2000",
  "DS4_ENGRAM_CACHE_MB": "2048",
  "MAYA_DS4_CACHE_SUB_RATIO": "0.1",
  "MAYA_DS4_TP_GGUF_UNEVEN": "1",
  "MAYA_DS4_HIP_PEER_AR": "1",
  "DS4_HIP_PEER_AR": "1",
  "MAYA_DS4_AR2": "0",
  "DS4_AR2": "0",
  "MAYA_DS4_CACHE_SUB_N": "12",
  "MAYA_DS4_CACHE_SUB_RISK_BUDGET": "0.6",
  "MAYA_DS4_CACHE_SUB_NORM": "reference",
  "DS4_STREAM_ZC": "1",
  "DS4_STREAM_WIN": "1",
  "DS4_LAND": "1",
  "MAYA_DS4_SLOT_KEEP": "1",
  "DS4_TP_SHARES": "4,5"
}
```

启动参数保持：

```text
--max-context 262144 --tp 2 --dspark on --mmap-experts off --experts 4 --reserve-mib 768
```

## 复现/日常检查

```bash
# 启动（默认 2 轮预热）
./start_ds4_v2.sh

# 看当前状态
curl -s -H "Authorization: Bearer $KEY" http://127.0.0.1:8000/metrics \
  | jq '.tiers.now | {tok_s,vram_hit,cpu,ram_fetch,engram_ms,disk}'

# 判断
# 快：vram_hit > 0.93，cpu/ram_fetch 约 2–12
# 慢：vram_hit < 0.85，cpu/ram_fetch > 30  -> 先预热/等待，不要判断模型质量
```

## 相关文件

- `maya-ds4-v2.json`（本机配置，gitignored）：`DS4_SETTLE_MS=2000`
- `start_ds4_v2.sh`：ready 后跑 2 轮预热
- `tools/warmup_ds4.py`：预热脚本
- `docs/2080ti22gx2/BENCHLOG.md`：简版实验记录
- `src/ds4/ds4_model.cu`：`DS4_SETTLE_MS` / `cache_settle()` / `settle_learn()`
- `docs/SETTINGS.md`：`MAYA_DS4_SETTLE_MS` 的设置说明

## 注意

- `MAYA_DS4_CACHE_SUB_RATIO=0.1` 是**近似推理**，会改变输出；做质量对比时先设 0。
- `DS4_SETTLE_MS` 只改专家放置，不改变输出；代价是长 prompt 后第一 token 最多等 2 秒。
- “多轮会话”本身不会让缓存自愈；每轮长 prompt 都需要 settle/预热，或先用真实业务文本把工作集喂热。
