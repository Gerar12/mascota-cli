#!/bin/sh
set -eu
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
cat > "$T/settings.json" <<'EOF'
{"model":"x","hooks":{"Stop":[{"hooks":[{"type":"command","command":"/tts.sh"}]}]}}
EOF
cat > "$T/hooks.json" <<'EOF'
{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/codex-tts.sh"}]}]}}
EOF
correr() { python3 "$RAIZ/scripts/instalar-hooks.py" --claude "$T/settings.json" --codex "$T/hooks.json" --destino-hook "$T/bin/pet-hook.sh" "$@"; }
correr; correr   # dos veces: idempotente
python3 - "$T" <<'EOF'
import json, sys, os
t = sys.argv[1]
c = json.load(open(f"{t}/settings.json")); x = json.load(open(f"{t}/hooks.json"))
assert c["model"] == "x"
assert c["hooks"]["Stop"][0]["hooks"][0]["command"] == "/tts.sh"
def cmds(cfg, ev): return [h["command"] for g in cfg["hooks"].get(ev, []) for h in g["hooks"]]
for ev in ["UserPromptSubmit","PreToolUse","PostToolUse","SubagentStart","PermissionRequest","Stop","StopFailure","SessionEnd"]:
    assert sum("pet-hook.sh" in k and k.endswith(" claude") for k in cmds(c, ev)) == 1, ev
for ev in ["UserPromptSubmit","PreToolUse","PostToolUse","SubagentStart","PermissionRequest","Stop","SessionEnd"]:
    assert sum("pet-hook.sh" in k and k.endswith(" codex") for k in cmds(x, ev)) == 1, ev
assert os.access(f"{t}/bin/pet-hook.sh", os.X_OK)
assert any(n.startswith("settings.json.bak-mascota-") for n in os.listdir(t))
EOF
correr --desinstalar
python3 - "$T" <<'EOF'
import json, sys
t = sys.argv[1]
for f in ["settings.json", "hooks.json"]:
    assert "pet-hook.sh" not in open(f"{t}/{f}").read(), f
assert json.load(open(f"{t}/settings.json"))["hooks"]["Stop"][0]["hooks"][0]["command"] == "/tts.sh"
EOF
rm -rf "$T"; echo "OK instalar-hooks"
