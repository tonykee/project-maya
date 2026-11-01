import json, threading, time, urllib.request, statistics, sys

URL="http://127.0.0.1:8000/v1/chat/completions"; KEY="llama_local"
PROMPTS=[
 "用大约200字解释什么是数据库事务的隔离级别。",
 "用大约200字说明 TCP 三次握手为什么不能是两次。",
 "用大约200字解释为什么 GPU 适合矩阵乘法。",
 "用大约200字说明缓存穿透和缓存雪崩的区别。",
]

def one(i, out):
    body=json.dumps({"model":"deepseek-v4.1-flash","messages":[{"role":"user","content":PROMPTS[i%len(PROMPTS)]}],
                     "max_tokens":160,"temperature":0,"reasoning_effort":"off"}).encode()
    req=urllib.request.Request(URL,data=body,headers={"Content-Type":"application/json","Authorization":f"Bearer {KEY}"})
    t0=time.time()
    with urllib.request.urlopen(req,timeout=1800) as r: d=json.load(r)
    out[i]=(time.time()-t0, d["timings"]["predicted_per_second"], d["usage"]["completion_tokens"])

n=int(sys.argv[1]) if len(sys.argv)>1 else 2
out={}; ths=[threading.Thread(target=one,args=(i,out)) for i in range(n)]
t0=time.time()
for t in ths: t.start()
for t in ths: t.join()
wall=time.time()-t0
tot=sum(v[2] for v in out.values())
print(f"{n} 个并发请求：总墙钟 {wall:.1f}s，总生成 {tot} tokens → 聚合 {tot/wall:.1f} tok/s")
for i in sorted(out): print(f"   # {i}: {out[i][0]:5.1f}s  {out[i][1]:5.1f} tok/s  {out[i][2]} tok")
