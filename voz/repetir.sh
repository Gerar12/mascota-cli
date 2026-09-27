#!/bin/sh
# Reproducción dirigida; después el mp3 más reciente y, por último, el texto.
exec >/dev/null 2>&1
VOZ="${MASCOTA_DIR:-$HOME/.mascota}/voz"
[ -f "$VOZ/OFF" ] && exit 0
BIN=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 0
if python3 - "$VOZ" "${1:-}" <<'PY'
import os, pathlib, re, sys, tempfile, time
try:
    voice = pathlib.Path(sys.argv[1])
    sid = re.sub(r"[^A-Za-z0-9_.-]", "", sys.argv[2])[:120]
    mp3 = voice/f"ultimo-{sid}.mp3"
    if not sid or not mp3.is_file():
        mp3 = max((p for p in voice.glob("ultimo-*.mp3") if p.is_file()),
                  key=lambda p: p.stat().st_mtime_ns, default=None)
    if mp3 is not None and mp3.is_file():
        kind, sid, payload = "PLAY", mp3.name[7:-4], str(mp3)
    else:
        kind, sid, payload = "SPEAK", "global", (voice/"ultimo.txt").read_text(encoding="utf-8")
    if not payload.strip(): sys.exit(1)
    queue = voice/"cola"
    queue.mkdir(parents=True, exist_ok=True)
    job = queue/f"{time.time_ns():020d}-{os.getpid()}.job"
    fd, tmp = tempfile.mkstemp(prefix=".repetir-", dir=queue)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            out.write(f"{kind}\n{sid}\n{payload}\n")
        os.replace(tmp, job)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)
except Exception:
    sys.exit(1)
PY
then
    nohup /bin/sh "$BIN/despachador.sh" </dev/null >/dev/null 2>&1 &
fi
exit 0
