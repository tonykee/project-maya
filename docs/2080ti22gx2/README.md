# 2× RTX 2080 Ti 22G 部署包

这个目录是 `docs/2080TI22GX2.md` 的配套文件，用于在**同款硬件**（2× RTX 2080 Ti 22GB，sm_75）上快速复现。

## 文件

| 文件 | 说明 |
|---|---|
| `maya-ds4.json` | DeepSeek-V4.1 Maya-XS 的完整调优配置（已脱敏，`api_key` 改成 `CHANGE_ME`） |
| `maya-maya-s24.json` | GLM-5.3 Maya-S24 的完整调优配置（已脱敏） |
| `maya-minimax-maya-xs.json` | MiniMax M3.1 Maya-XS 配置（已脱敏） |
| `start_*.sh` / `stop_*.sh` | 三个模型的启停脚本（从配置读端口和 key） |
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

## 注意

- 三个模型**不能同时跑**（44GB 显存一次只能装一个）。
- DeepSeek 启动约 6–7 分钟（80GB 专家复制进 pinned RAM），期间内存会锁到只剩 ~6GB。
- 测速前确认 `--prefill-chunk 8192` 生效；默认的 4096 会慢 15%。
- 开了 `MAYA_DS4_SLOT_KEEP=1` 之后，重复的 prompt 会命中会话槽——测 prefill 一定要加随机前缀。
- `maya-ds4.json` **默认开启** `MAYA_DS4_CACHE_SUB_RATIO=0.1`（#821，decode 近似路由）：在本机 2×2080 Ti 22G/TP=2/Maya-XS 上 decode `32.3 → 44.6~48.5 tok/s`，prefill 基本不变；**会改变输出**（自动回归 30 题 26/30→27/30，个例波动）。如需原生输出/排查质量，设 `MAYA_DS4_CACHE_SUB_RATIO=0`（见 `docs/ds4-cache-substitution.md`、`docs/SETTINGS.md`）。
