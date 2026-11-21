"""Self-check: engine starts, speaks fast, and Stop cancels a long read. Run: .venv/bin/python test_engine.py"""
import json, subprocess, sys, time

p = subprocess.Popen([sys.executable, "engine.py"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                     stderr=subprocess.DEVNULL, text=True, bufsize=1)
send = lambda o: (p.stdin.write(json.dumps(o) + "\n"), p.stdin.flush())
read = lambda: json.loads(p.stdout.readline())

t = time.time()
assert read() == {"ready": True}
print(f"startup (load + warm-up): {time.time() - t:.1f}s")

send({"id": 0, "cmd": "voices"})
voices = read()["builtin"]
assert sum(map(len, voices.values())) == 37, voices

t = time.time()
send({"id": 1, "text": "Hello! This is KittenSpeak reading your selection.", "voice": "Vincent"})
assert "chunk" in read()
print(f"first audio: {time.time() - t:.2f}s")
while "done" not in (msg := read()):
    assert "chunk" in msg, msg

send({"id": 2, "text": " ".join(f"This is sentence number {i}." for i in range(40)), "voice": "Iris"})
assert read()["id"] == 2
t = time.time()
send({"cmd": "stop"})
send({"id": 3, "text": "Stopped.", "voice": "Max"})
msgs = []
while not msgs or msgs[-1].get("id") != 3 or "done" not in msgs[-1]:
    msgs.append(read())
assert not any(m.get("id") == 2 and m.get("done") for m in msgs), "long read was not cancelled"
print(f"stop + next speech: {time.time() - t:.2f}s")
p.kill()
print("OK")
