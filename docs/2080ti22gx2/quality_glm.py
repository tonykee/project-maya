"""Ten fixed quality checks for GLM-5.3 (same categories as the earlier 3700X run)."""

import json
import re
import urllib.request

URL = "http://127.0.0.1:8000/v1/chat/completions"
KEY = "llama_local"
MODEL = "glm-5.3-flash"


def ask(prompt, max_tokens=600):
    body = json.dumps({
        "model": MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": 0,
        "reasoning_effort": "off",
    }).encode()
    req = urllib.request.Request(URL, data=body, headers={
        "Content-Type": "application/json", "Authorization": "Bearer " + KEY})
    with urllib.request.urlopen(req, timeout=1800) as r:
        d = json.load(r)
    return d["choices"][0]["message"].get("content", "") or ""


def code_of(text):
    m = re.search(r"```(?:python)?\s*(.*?)```", text, re.S)
    return (m.group(1) if m else text).strip()


def main():
    results = []

    # 1 arithmetic (known hard case for Maya-S24)
    a = ask("1234*5678 等于多少？只回答数字，不要解释。", 32)
    results.append(("arithmetic 1234*5678", "7006652" in re.sub(r"[^0-9]", "", a)))

    # 2 prime function, executed
    code = code_of(ask("写一个 Python 函数 is_prime(n)，只输出代码，不要解释。", 600))
    ok = False
    try:
        ns = {}
        exec(code, ns)
        f = ns["is_prime"]
        ok = all(f(x) for x in (2, 3, 5, 7, 11, 13)) and not any(f(x) for x in (0, 1, 4, 6, 9, 15))
    except Exception:
        ok = False
    results.append(("prime function", ok))

    # 3 strict JSON
    a = ask('只输出 JSON：{"name":"Maya","version":1,"tags":["glm","local"]}', 120)
    try:
        j = json.loads(code_of(a))
        ok = j.get("name") == "Maya" and j.get("version") == 1 and j.get("tags") == ["glm", "local"]
    except Exception:
        ok = False
    results.append(("strict JSON", ok))

    # 4 exactly three bullets
    a = ask("用恰好 3 个 bullet 列出 MoE 的三个优点；只输出列表，不要额外文字。", 300)
    bullets = [l for l in a.splitlines() if re.match(r"^\s*[-*•]\s+", l)]
    results.append(("bullet count = 3", len(bullets) == 3))

    # 5 word reversal
    a = ask("把 strawberry 这个单词反转，只回答结果。", 32)
    results.append(("word reversal", "yrrebwarts" in a.lower()))

    # 6 regex for a mainland phone number
    a = ask("写一个正则，匹配中国大陆 11 位手机号（1 开头，第二位 3-9），只输出正则。", 120)
    pat = code_of(a)
    try:
        rx = re.compile(pat)
        ok = bool(rx.fullmatch("13812345678")) and not rx.fullmatch("12812345678") and not rx.fullmatch("1381234567")
    except Exception:
        ok = False
    results.append(("phone regex", ok))

    # 7 weekday
    a = ask("2026-11-04 是星期几？只回答中文星期。", 32)
    results.append(("weekday 2026-11-04", "星期三" in a or "周三" in a))

    # 8 1.2K needle
    filler = ("稀疏专家模型在推理时只激活少量专家，其余专家保持在内存或固态硬盘中。"
              "工程部署需要关注显存容量、内存带宽和专家迁移策略。") * 120
    needle = "蓝色猎鹰四十二"
    text = filler[:1200] + f"\n\n重要暗号是：{needle}。请记住它。\n\n" + filler[1200:2400]
    a = ask("阅读下面材料，只回答其中的暗号：\n\n" + text, 64)
    results.append(("1.2K needle", needle in a))

    # 9 count letter i
    a = ask("统计 artificial intelligence 这两个单词中字母 i 出现的总次数，只回答数字。", 32)
    results.append(("count letter i", re.search(r"\b4\b", a) is not None))

    # 10 sorted JSON
    a = ask("把 [3,1,4,1,5,9,2,6] 升序排列，只回答 JSON 数组。", 80)
    try:
        arr = json.loads(code_of(a))
        ok = arr == [1, 1, 2, 3, 4, 5, 6, 9]
    except Exception:
        ok = False
    results.append(("sort numbers", ok))

    passed = sum(1 for _, ok in results if ok)
    for name, ok in results:
        print(("PASS" if ok else "FAIL"), name)
    print(f"score: {passed}/10")


if __name__ == "__main__":
    main()
