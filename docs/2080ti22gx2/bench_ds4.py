import json, statistics, sys, time, urllib.request, uuid

URL = "http://127.0.0.1:8000/v1/chat/completions"
KEY = "llama_local"
MODEL = "deepseek-v4.1-flash"

BASE = ("混合专家模型通过稀疏激活在保持参数规模的同时控制计算量。每个词元只经过少数专家，"
        "路由网络决定哪些专家参与计算，其余专家保持空闲。本地部署时专家分层缓存在显存、内存和固态硬盘之间，"
        "按对话中出现的频率动态迁移。工程实践中需要专家并行、容量因子和丢词策略的配合。")

def post(msgs, max_tokens, effort="high"):
    body = json.dumps({"model": MODEL, "messages": msgs, "max_tokens": max_tokens,
                       "temperature": 0, "reasoning_effort": effort}).encode()
    req = urllib.request.Request(URL, data=body, headers={"Content-Type": "application/json",
                                                          "Authorization": f"Bearer {KEY}"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=3600) as r:
        d = json.load(r)
    return d, time.time() - t0

def prefill(n):
    text = "[" + uuid.uuid4().hex + "] 请阅读下面材料，最后只回答“收到”。\n\n" + BASE * int(n * 1.4 / len(BASE))
    d, w = post([{"role": "user", "content": text}], 8, "off")
    t = d["timings"]; u = d["usage"]
    print(f"  prompt={u['prompt_tokens']:>6} tok (cached {u['prompt_tokens_details']['cached_tokens']})  prefill={t['prompt_ms']/1000:7.2f}s  {t['prompt_per_second']:6.1f} tok/s  端到端={w:6.1f}s")
    return t["prompt_per_second"]

label = sys.argv[1] if len(sys.argv) > 1 else "ds4"
print(f"== {label}")
post([{"role": "user", "content": "热身：只回答“好”。"}], 16, "off")
for n in (2000, 8000, 16000):
    prefill(n)

print("  --- decode (256 tokens, thinking off)")
rates = []
for p in ["写一个 Python 脚本，用 websocket 向 ComfyUI 提交 prompt 并监听进度。",
          "写一段 bpy 脚本：清空场景、创建立方体、加 subdivision、红色材质、导出 glb。",
          "用 MCP 工具（comfyui / blender / filesystem）编排：读配置 → 出图 → 合成，给出伪代码。"]:
    d, w = post([{"role": "user", "content": p}], 256, "off")
    r = d["timings"]["predicted_per_second"]; rates.append(r)
    print(f"  {r:5.1f} tok/s  {w:5.1f}s")
print(f"  decode 中位数 {statistics.median(rates):.1f} tok/s")
