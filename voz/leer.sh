#!/bin/sh
# Hook Stop silencioso: publicar el trabajo completo antes de despertar al worker.
exec >/dev/null 2>&1
VOZ="${MASCOTA_DIR:-$HOME/.mascota}/voz"
[ -f "$VOZ/OFF" ] && exit 0
case "${1:-}" in claude|codex) ;; *) exit 0 ;; esac
BIN=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 0
export PYTHONDONTWRITEBYTECODE=1
if python3 -c '
import json, os, pathlib, re, sys, tempfile, time
sys.path.insert(0, sys.argv[2])
from limpiar import clean

def publicar(path, text):
    fd, tmp = tempfile.mkstemp(prefix=".texto-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            out.write(text)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)

try:
    voice = pathlib.Path(sys.argv[1])
    data = json.load(sys.stdin)
    text = data.get("last_assistant_message", "")
    if not isinstance(text, str) or not text.strip(): sys.exit(1)
    text = clean(text)[:1500].strip()
    if not text or (voice/"OFF").exists(): sys.exit(1)
    sid = data.get("session_id")
    sid = re.sub(r"[^A-Za-z0-9_.-]", "", sid)[:120] if isinstance(sid, str) else ""
    sid = sid if sid not in ("", ".", "..") else "global"
    queue = voice/"cola"
    queue.mkdir(parents=True, exist_ok=True)
    publicar(voice/f"ultimo-{sid}.txt", text)
    publicar(voice/"ultimo.txt", text)
    job = queue/f"{time.time_ns():020d}-{os.getpid()}.job"
    publicar(job, f"SPEAK\n{sid}\n{text}\n")
except Exception:
    sys.exit(1)
' "$VOZ" "$BIN"; then
    nohup /bin/sh "$BIN/despachador.sh" </dev/null >/dev/null 2>&1 &
fi
exit 0
