import base64, io, json, sys, time, urllib.request

URL = "http://127.0.0.1:8000/v1/chat/completions"
KEY = "llama_local"

def img_data_uri():
    from PIL import Image, ImageDraw
    im = Image.new("RGB", (64, 64), (200, 40, 40))
    d = ImageDraw.Draw(im)
    d.rectangle([16, 16, 48, 48], fill=(20, 20, 200))
    buf = io.BytesIO(); im.save(buf, format="PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()

IMG = img_data_uri()

def post(messages, tag, max_tokens=64):
    body = json.dumps({"model": "deepseek-v4.1-flash", "messages": messages,
                       "max_tokens": max_tokens, "temperature": 0, "reasoning_effort": "off"}).encode()
    req = urllib.request.Request(URL, data=body, headers={"Content-Type": "application/json",
                                                          "Authorization": f"Bearer {KEY}"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=1800) as r:
        d = json.load(r)
    t = d["timings"]; u = d["usage"]
    print(f"[{tag}] prompt={u['prompt_tokens']:5d} tok  cached={u['prompt_tokens_details']['cached_tokens']:5d}  "
          f"prefill={t['prompt_ms']/1000:6.2f}s  {time.time()-t0:5.1f}s")
    return d["choices"][0]["message"]["content"]

FILLER = ("这是一段用于填充上下文的说明文字，用来模拟真实的长对话。它描述了一个项目的背景、"
          "技术选型、目录结构以及若干注意事项。") * 40

msgs = [{"role": "system", "content": "You are a coding assistant."},
        {"role": "user", "content": "下面是我项目的背景，请阅读后只回答“收到”。\n\n" + FILLER}]
a1 = post(msgs, "第1轮 文本")
msgs.append({"role": "assistant", "content": a1})
msgs.append({"role": "user", "content": "补充说明：模块划分如下。\n\n" + FILLER})
a2 = post(msgs, "第2轮 文本")
msgs.append({"role": "assistant", "content": a2})

# 第3轮：只加一张图 + 短问题（前缀完全没变）
msgs.append({"role": "user", "content": [
    {"type": "text", "text": "这张图里主要是什么颜色？一句话回答。"},
    {"type": "image_url", "image_url": {"url": IMG}}]})
a3 = post(msgs, "第3轮 带图", max_tokens=80)
print("回答:", a3.strip()[:80])

# 第4轮：纯文本继续（验证图片轮之后是否还能复用）
msgs.append({"role": "assistant", "content": a3})
msgs.append({"role": "user", "content": "刚才那张图里有没有蓝色方块？只回答有/没有。"})
a4 = post(msgs, "第4轮 纯文本续")
print("回答:", a4.strip()[:60])
