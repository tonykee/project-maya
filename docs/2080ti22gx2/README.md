# 2× RTX 2080 Ti 22G 部署包

这个目录是 `docs/2080TI22GX2.md` 的配套文件，用于在**同款硬件**（2× RTX 2080 Ti 22GB，sm_75）上快速复现。

## 文件

| 文件 | 说明 |
|---|---|
| `maya-ds4.json` | DeepSeek-V4.1 Maya-XS 的完整调优配置（已脱敏，`api_key` 改成 `CHANGE_ME`） |
| `maya-maya-s24.json` | GLM-5.3 Maya-S24 的完整调优配置（已脱敏） |
| `maya-minimax-maya-xs.json` | MiniMax M3.1 Maya-XS 配置（已脱敏） |
| `start_*.sh` / `stop_*.sh` | 三个模型的启停脚本（从配置读端口和 key）；DeepSeek v2 用独立的 `start_ds4_v2.sh` / `stop_ds4_v2.sh`（独立 `maya-ds4-v2.json`、pid/log，不影响 v1） |
| `dl_*.sh` / `downloads_queue.sh` | 断点续传下载脚本（DeepSeek 277GB / MiniMax 87GB，按 sha256 校验） |
| `bench_*.py` / `decode_bench.py` / `conc_ds4.py` | 测速脚本（prefill 用随机 nonce，避免会话槽缓存污染） |
| `test_image_ds4.py` | 验证图片请求是否复用上下文的脚本 |

## 使用

```bash
# 1. 把配置放回仓库根目录，替换 api_key
cp docs/2080ti22gx2/maya-ds4.json ./maya-ds4.json
sed -i 's/CHANGE_ME/你的密钥/' maya-ds4.json

# 2. 路径要改成你的模型目录（配置里的 --pack 和 tokenizer 指向 /mnt/kioxia/...）
# 3. 启动
cp docs/2080ti22gx2/start_ds4.sh docs/2080ti22gx2/stop_ds4.sh ./
./start_ds4.sh
```

## DeepSeek Maya-XS v2 单独调优（不影响 v1）

v2 权重/分片（HF v2: 3 个模型分片 + 复用 Engram 分片 4-5）已就绪；pack 已重建到**独立物理目录** `Maya-XS-v2/maya-ds4-v2/`（大文件硬链接，非共用产物 `engram.bin`/`tokenizer`/画像 物理分开，不与 `Maya-XS/maya-ds4` 混用）。**不要直接复用 v1 调优参数**（同参数实测吞吐严重回退，见 `BENCHLOG`）；`expert-profile.bin`/`slots` 需在 v2 本机运行/校准时生成。使用归零基线配置单独调优：

```bash
cp docs/2080ti22gx2/maya-ds4-v2.json ./maya-ds4-v2.json   # 按需改路径/api_key
./stop_ds4.sh                # 先停 v1（2×2080 Ti 一次只能跑一个）
./start_ds4_v2.sh            # 使用 maya-ds4-v2.json + 独立 pid/log
# 测完恢复 v1：
./stop_ds4_v2.sh && ./start_ds4.sh
```

`maya-ds4-v2.json` 基线已归零 v1 专项调优（无 `--experts/--reserve-mib` 强设、无 `HIP_PEER_AR/TP_SHARES/STREAM/LAND` 等，`CACHE_SUB_RATIO=0`，保留 `DS4_ENGRAM_CACHE_MB=2048`），在此基础上按 `BENCHLOG` 纪律逐项 A/B（`--experts`、`--reserve-mib`、校准/profile、Engram、HIP peer、#821 等）。

## 注意

- 三个模型**不能同时跑**（44GB 显存一次只能装一个）。
- DeepSeek 启动约 6–7 分钟（80GB 专家复制进 pinned RAM），期间内存会锁到只剩 ~6GB。
- 测速前确认 `--prefill-chunk 8192` 生效；默认的 4096 会慢 15%。
- 开了 `MAYA_DS4_SLOT_KEEP=1` 之后，重复的 prompt 会命中会话槽——测 prefill 一定要加随机前缀。
- `maya-ds4.json` **默认开启** `MAYA_DS4_CACHE_SUB_RATIO=0.1`（#821，decode 近似路由）：在本机 2×2080 Ti 22G/TP=2/Maya-XS 上 decode `32.3 → 44.6~51.7 tok/s`，prefill 基本不变；**会改变输出**（自动回归 30 题 26/30→27/30，个例波动）。如需原生输出/排查质量，设 `MAYA_DS4_CACHE_SUB_RATIO=0`（见 `docs/ds4-cache-substitution.md`、`docs/SETTINGS.md`）。
- `maya-ds4.json` 使用 `MAYA_DS4_HIP_PEER_AR=1`（NVLink 直连 VRAM 的 prefill all-reduce，TP=2）并移除显式 `MAYA_DS4_AR2`：本机实测 prefill `421/787/982 tok/s`（1.6K/6.6K/13.2K），优于 `AR2=2` 路径。注意：显式 `AR2!=0` 会阻止 peer-AR 选中；`HIP_PEER_AR=auto` 探测在显存紧张时可能因额外 probe buffer 失败（本机 auto 报 `needs 544 MiB`），`1` 强制模式可在 P2P 可用时启用（需 NVLink + 驱动允许 CUDA P2P）。
