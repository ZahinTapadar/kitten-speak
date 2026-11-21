"""KittenSpeak engine: JSON lines on stdin -> WAV chunk paths on stdout.

Request:  {"id": 1, "text": "...", "voice": "Vincent", "speed": 1.0} | {"cmd": "stop"} | {"id": 0, "cmd": "voices"}
Replies:  {"ready": true}, {"id": 1, "chunk": "/path.wav"} ... {"id": 1, "done": true} | {"id": 1, "error": "..."}
Any new line on stdin cancels the speech in progress at the next sentence boundary.
"""
import json, os, queue, re, sys, tempfile, threading, traceback
import soundfile as sf

OUT_DIR = tempfile.mkdtemp(prefix="kittenspeak-")
_proto = sys.stdout
inbox = queue.Queue()


def send(obj):
    _proto.write(json.dumps(obj) + "\n")
    _proto.flush()


def handle(m, req):
    rid = req.get("id")
    if req.get("cmd") == "voices":
        return send({"id": rid, "builtin": m.available_voices})
    if req.get("cmd"):  # "stop": nothing to do, the loop below already broke off
        return
    # One sentence per synthesis call: first audio comes sooner and Stop takes effect within a sentence.
    sentences = [s for s in re.split(r"(?<=[.!?。！？])\s+|\n+", req["text"]) if s.strip()]
    for i, sentence in enumerate(sentences):
        audio = m.generate(sentence, voice=req.get("voice") or None, speed=float(req.get("speed", 1.0)))
        path = os.path.join(OUT_DIR, f"{rid}-{i}.wav")
        sf.write(path, audio, m.sample_rate)
        send({"id": rid, "chunk": path})
        if not inbox.empty():  # superseded by Stop or a newer request
            return
    send({"id": rid, "done": True})


def main():
    sys.stdout = sys.stderr  # keep library chatter (progress bars, prints) off the protocol channel
    from kittenml import KittenTTS
    m = KittenTTS("KittenML/kitten-tts-2-nano")
    m.generate("Warm up.")  # first call loads the G2P stack; pay it at launch, not on the first right-click
    threading.Thread(target=lambda: [inbox.put(l) for l in sys.stdin], daemon=True).start()
    send({"ready": True})
    while True:
        line = inbox.get()
        if not line.strip():
            continue
        req = {}
        try:
            req = json.loads(line)
            handle(m, req)
        except Exception as e:
            traceback.print_exc()
            send({"id": req.get("id"), "error": str(e)})


if __name__ == "__main__":
    main()
