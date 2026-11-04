"""One 53K cold-prefill run, for the X99 headless baseline.

Run it ONCE after a fresh DS4 start: the 53K prompt fills the VRAM expert
cache and later runs are not comparable.
"""

import json
import time
import urllib.request
import uuid

URL = "http://127.0.0.1:8000/v1/chat/completions"
KEY = "llama_local"
MODEL = "deepseek-v4.1-flash"

BASE = (
    "混合专家模型通过稀疏激活在保持参数规模的同时控制计算量。每个词元只经过少数专家，"
    "路由网络决定哪些专家参与计算，其余专家保持空闲。本地部署时专家分层缓存在显存、内存和固态硬盘之间，"
    "按对话中出现的频率动态迁移。工程实践中需要专家并行、容量因子和丢词策略的配合。"
)

text = "[" + uuid.uuid4().hex + "] 请阅读下面材料，最后只回答“收到”。\n\n" + BASE * int(65000 * 1.4 / len(BASE))
body = json.dumps(
    {
        "model": MODEL,
        "messages": [{"role": "user", "content": text}],
        "max_tokens": 8,
        "temperature": 0,
        "reasoning_effort": "off",
    }
).encode()
req = urllib.request.Request(
    URL,
    data=body,
    headers={"Content-Type": "application/json", "Authorization": "Bearer " + KEY},
)

t0 = time.time()
with urllib.request.urlopen(req, timeout=3600) as response:
    data = json.load(response)
elapsed = time.time() - t0

timings = data["timings"]
usage = data["usage"]
cached = usage["prompt_tokens_details"]["cached_tokens"]
print(
    f"53K prompt={usage['prompt_tokens']} (cached {cached}) "
    f"prefill={timings['prompt_ms'] / 1000:.2f}s "
    f"{timings['prompt_per_second']:.1f} tok/s e2e={elapsed:.1f}s"
)
