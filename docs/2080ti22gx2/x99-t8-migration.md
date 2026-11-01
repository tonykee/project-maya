# 华南 X99-T8 迁移清单（E5-2666 v3 + 4×32G DDR3-1600 RDIMM）

> 目标：把当前 3700X 平台的两张 2080Ti 22G 迁到 X99-T8，跑 Maya 三件套。
> 本文只写**这块板子特有的坑**；通用调优见 `../2080TI22GX2.md`。

## 1. 板子事实（官方手册 + 实测核对）

| 项 | 规格 | 对我们的意义 |
|---|---|---|
| CPU 插槽 | **单路** LGA2011-3（不是 T8D 的双路） | 8 条内存槽全归一颗 CPU，单 U 就能上 128G |
| 内存 | 8×DDR3 四通道，1866/1600/1333，最大 256G，支持 REG ECC | 4×32G RDIMM = 128G，是社区公认的稳定线 |
| PCIe | **2× PCIe 3.0 x16**（CPU 直连，可 x16/x16） | 两张 2080Ti 正好；第三条 x16 物理是 x4，别插 |
| x16 间距 | 两条 x16 相距 **3 个槽位（60.96mm）** | 对应 2080Ti 的 **3 槽 NVLink 桥**；到货用尺量中心距 ≈61mm 再上桥 |
| M.2 | 1× PCIe 3.0 x4 + 1× PCIe 2.0 x4 | **模型盘必须插 3.0 那个**（另一个只有 ~2 GB/s） |
| 供电 | 24pin + 单 8pin，6 相 | 2666 v3 135W 够用；双卡建议 850W+ |
| 风扇 | 1× CPU 4pin + 3× 机箱 3pin | 只有 1 个 CPU 风扇接口 |

## 2. 到货前准备

- [ ] **LGA2011-3 散热器**（方 ILM；AM4 的扣具用不了）
- [ ] **850W+ 电源**：两张 2080Ti 满载 500W + CPU 135W + 余量
- [ ] **3 槽 NVLink 桥**（现有那条先量一下长度；3 槽桥约 61mm 中心距）
- [ ] 机箱：两张 3 风扇卡之间只有 1 个空槽，注意进风；涡轮卡无所谓

## 3. 装机顺序（重点是内存）

1. CPU + 散热器先装好（LGA2011-3 的安装方向看三角标记）。
2. **内存一条一条插**：这板子内存识别玄学，社区做法是插一条、开机确认容量、再插下一条。
3. 4 条按**每通道 1 条**分布（8 槽 = 4 通道 × 2；不要 4 条全插同一边）。
4. 模型 NVMe 插 **PCIe 3.0 x4** 那个 M.2（装好后用 `lspci` 确认 8GT/s，不是 5GT/s）。
5. 两张显卡插两条 x16（从上往下第 2 和第 5 槽位，中心距约 61mm）。
6. BIOS：
   - **Above 4G Decoding = Enabled**（双 22G 卡必需）
   - 内存频率**手动锁 1600**（不要 Auto）
   - PCIe 速率 = Gen3（或 Auto）
   - 启动模式 = UEFI（原系统盘是 UEFI 装的）

## 4. 首次开机验证（30 分钟）

```bash
# 1. 内存：4×32G 全识别 + 1600 + 四通道
sudo dmidecode -t memory | grep -E "Size|Configured Memory Speed|Locator"
free -g | head -2                 # 期望 total ~125
# 2. 带宽：四通道的硬指标
sudo apt install mbw && mbw -n 5 1024
#    期望 > 35 GB/s；如果只有 ~20，说明插成双通道，换槽
# 3. PCIe：两条都必须是 16
nvidia-smi --query-gpu=index,pcie.link.gen.current,pcie.link.width.current --format=csv
#    跑负载时看，期望 3,16,3,16
# 4. NVLink
nvidia-smi nvlink -s              # 期望两张卡都 Active
# 5. CPU
lscpu | grep -E "Model name|^CPU\(s\)|Socket|NUMA"   # 10 核 20 线程，1 socket
```

## 5. Maya 期望成绩（4×32G 1600，与当前对比）

| 指标 | 现在（3700X/DDR4-2667） | X99-T8（DDR3-1600 四通道） | 变化 |
|---|---:|---:|---:|
| GLM decode | 33.8 | 37–40 | +12% |
| GLM prefill 13.5K | 608 | 670–730 | +15% |
| DeepSeek decode | 41.6 | 45–49 | +13% |
| DS prefill 13K | 665 | 730–800 | +14% |
| DS 短 prompt 1.6K | 235 | 300–360 | +40%（Engram 16G + 全专家驻留） |

> 只有 4 条时不要开 16G Engram 以上的缓存；`MAYA_DS4_ENGRAM_CACHE_MB=16384` 和
> `MAYA_DS4_SLOT_CAP=16` 是 128G 下的上限。256G 才考虑 96G+ 的 Engram 缓存。

## 6. 256G（8×32G）实验（可选，不建议当生产）

- 官方支持 256G，但社区共识：**128G 是稳定线，256G 是玄学区**（"各种报错，折腾一星期"）。
- 8×32G 通常需要在 BIOS 里**锁 1600** 才稳（1866 条要降频）；你的 1600 条正好。
- 上 8 条前：确认全部是 **RDIMM（REG ECC），不是 LRDIMM**（LRDIMM 是这块板的隐形雷）。
- 上 8 条后：memtest86+ 至少 4 轮；跑 24h 看 `sudo edac-util -s` 的 CE 是否增长。
- 收益：DS4 的 161G Engram 可缓存 ~120G（prefill +5~15%，SSD 读取归零）；GLM+MiniMax 双页缓存。
- 代价：2DPC 四 rank 可能降频/不稳；不稳就退回 4 条，速度不变。

## 7. 故障排查

| 现象 | 处理 |
|---|---|
| 不认内存 / 容量少 | 一条一条插；橡皮擦金手指；换槽；确认 RDIMM |
| 只跑双通道（mbw ~20） | 4 条没覆盖 4 个通道，按手册/丝印换槽 |
| 显卡只跑 x8/x4 | 换到两条 CPU 直连 x16；BIOS 里 PCIe 设 Gen3/Auto |
| NVLink 未激活 | 桥没插紧 / 间距不对；`nvidia-smi nvlink -s` 检查 |
| 开机很慢 | X99 POST + 内存训练，30–60 秒正常；4×32 四 rank 更慢 |
| 系统盘不启动 | UEFI/CSM 设置；原盘是 UEFI 装的，别开 Legacy |

## 8. 参考

- 官方规格：https://www.huananzhi.com/list_6/109.html
- 社区 128G/256G 实录（2026-10）：https://post.smzdm.com/p/axkodzkd/
- 板图/BIOS：https://theretroweb.com/motherboards/s/huananzhi-x99-t8-ver-0-1
