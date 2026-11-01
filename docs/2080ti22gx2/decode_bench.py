import json, statistics, sys, urllib.request

URL = "http://127.0.0.1:8000/v1/chat/completions"
KEY = "llama_local"

PROMPTS = [
    "用大约 250 字解释为什么 MoE 模型在同样参数量下推理更便宜。",
    "写一个 Python 函数，判断一个字符串是否是合法的 IPv4 地址，并简要说明思路。",
    "简述数据库索引的 B+ 树结构，以及它为什么适合范围查询。",
]


def one(prompt, max_tokens=256):
    body = json.dumps({"model": "glm-5.3-flash", "messages": [{"role": "user", "content": prompt}],
                       "max_tokens": max_tokens, "temperature": 0, "reasoning_effort": "off"}).encode()
    req = urllib.request.Request(URL, data=body, headers={"Content-Type": "application/json",
                                                          "Authorization": f"Bearer {KEY}"})
    with urllib.request.urlopen(req, timeout=1800) as r:
        d = json.load(r)
    return d["timings"]["predicted_per_second"], d["timings"].get("draft_n_accepted", 0), \
        d["timings"].get("draft_n", 0)


def main(label):
    print(f"== {label}")
    one("热身：只回答“好”。", max_tokens=32)
    rates = []
    for p in PROMPTS:
        r, acc, tot = one(p)
        rates.append(r)
        print(f"  {r:5.1f} tok/s   (draft {acc}/{tot})")
    med = statistics.median(rates)
    print(f"  中位数: {med:.1f} tok/s")
    return med


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "run")
