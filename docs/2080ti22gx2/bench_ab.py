import json, time, urllib.request, uuid, sys

URL = "http://127.0.0.1:8000/v1/chat/completions"
KEY = "llama_local"
BASE = ("混合专家模型通过稀疏激活在保持参数规模的同时控制计算量。每个词元只经过少数专家，"
        "路由网络决定哪些专家参与计算，其余专家保持空闲。这使得训练和推理的代价远低于同等参数量的稠密模型，"
        "但也带来了负载均衡、显存占用和通信开销等工程挑战。工程实践中通常需要专家并行、容量因子和丢词策略的配合。"
        "在本地部署时，专家往往被分层缓存到显存、内存和固态硬盘之间，按对话中出现的频率动态迁移。")


def run(approx_tokens, max_tokens=8, salt=None):
    salt = salt or uuid.uuid4().hex
    text = f"[{salt}] 请阅读下面材料，最后只回答“收到”。\n\n"
    reps = max(1, int(approx_tokens * 1.4 / len(BASE)))
    text += BASE * reps
    body = json.dumps({"model": "glm-5.3-flash", "messages": [{"role": "user", "content": text}],
                       "max_tokens": max_tokens, "temperature": 0, "reasoning_effort": "off"}).encode()
    req = urllib.request.Request(URL, data=body, headers={"Content-Type": "application/json",
                                                          "Authorization": f"Bearer {KEY}"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=3600) as r:
        d = json.load(r)
    wall = time.time() - t0
    t = d["timings"]; u = d["usage"]
    print(f"  prompt={u['prompt_tokens']:>6} tok  prefill={t['prompt_ms']/1000:>7.2f}s  "
          f"{t['prompt_per_second']:>6.1f} tok/s   decode={t['predicted_per_second']:>5.1f} tok/s   "
          f"wall={wall:>6.2f}s")
    return t["prompt_per_second"], t["predicted_per_second"]


if __name__ == "__main__":
    label = sys.argv[1] if len(sys.argv) > 1 else "run"
    print(f"== {label}")
    # 两轮取第二轮：避免首次请求的冷启动
    run(2000, max_tokens=4)
    for n in (2000, 7000, 16000):
        run(n)
