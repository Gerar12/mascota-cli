#!/bin/sh
set -eu
RAIZ=$(cd "$(dirname "$0")/.." && pwd)
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
python3 - "$RAIZ" "$T" <<'PY'
import json, pathlib, shlex, subprocess, sys
repo, root = map(pathlib.Path, sys.argv[1:])
dest = root / "ruta con 'comilla" / 'pet-hook.sh'
configs = [root/'claude-extra.json', root/'codex-extra.json']
def run(*extra):
    return subprocess.run([sys.executable, str(repo/'scripts/instalar-hooks.py'),
        '--claude', str(configs[0]), '--codex', str(configs[1]),
        '--destino-hook', str(dest), *extra], capture_output=True, text=True)
original = {'model':'preservar', 'hooks':{'Stop':[{'matcher':'*','hooks':[
    {'type':'command','command':'/otro/pet-hook.sh claude'},
    {'type':'command','command':'/tts.sh'}]}]}}
for path in configs:
    path.write_text(json.dumps(original))
assert run().returncode == 0
errors = []
for path, cli in zip(configs, ['claude','codex']):
    cfg = json.loads(path.read_text())
    if cfg['hooks']['Stop'][0] != original['hooks']['Stop'][0]:
        errors.append('alteró un grupo ajeno')
    own = cfg['hooks']['Stop'][-1]['hooks'][0]
    try:
        assert shlex.split(own['command']) == ['/bin/sh', str(dest), cli]
    except (ValueError, AssertionError):
        errors.append('ruta con comilla mal escapada')
    if cli == 'claude':
        assert own['async'] is True
    else:
        assert 'async' not in own
before = [p.read_bytes() for p in configs]
backups = {p:p.read_bytes() for p in root.glob('*extra.json.bak-mascota-*')}
assert run().returncode == 0
assert [p.read_bytes() for p in configs] == before, 'no es idempotente'
if any(p.read_bytes() != data for p,data in backups.items()):
    errors.append('sobrescribió un respaldo')
# Un hook ajeno añadido al mismo grupo debe sobrevivir a la desinstalación.
for path in configs:
    cfg = json.loads(path.read_text())
    cfg['hooks']['Stop'][-1]['hooks'].append({'type':'command','command':'/keep-alive.sh'})
    path.write_text(json.dumps(cfg))
assert run('--desinstalar').returncode == 0
for path in configs:
    cfg = json.loads(path.read_text())
    commands = [h['command'] for g in cfg['hooks'].get('Stop', []) for h in g['hooks']]
    if commands != ['/otro/pet-hook.sh claude','/tts.sh','/keep-alive.sh']:
        errors.append('desinstalar borró hooks ajenos')
assert not errors, errors
for path in configs:
    path.write_text('{"model":"sin hooks"}')
before = [p.read_bytes() for p in configs]
assert run('--desinstalar').returncode == 0
assert [p.read_bytes() for p in configs] == before, 'desinstalar modificó configuración sin hooks'
PY
python3 - "$RAIZ" "$T" <<'PY'
import json, os, pathlib, shlex, subprocess, sys
repo, root = map(pathlib.Path, sys.argv[1:])
voice = root / "voz con 'comilla" / 'bin'
configs = [root/'voz-claude.json', root/'voz-codex.json']
def run(*extra):
    result = subprocess.run([sys.executable, str(repo/'scripts/instalar-hooks.py'),
        '--claude', str(configs[0]), '--codex', str(configs[1]),
        '--destino-hook', str(root/'pet-hook.sh'), '--destino-voz', str(voice),
        *extra], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
def hooks(path):
    return [h for g in json.loads(path.read_text())['hooks']['Stop'] for h in g['hooks']]
for path in configs:
    path.write_text(json.dumps({'hooks': {'Stop': [{'hooks': [
        {'type': 'command', 'command': '/otra/leer.sh'},
        {'type': 'command', 'command': '/tts.sh'}]}]}}))
run()
assert not voice.exists(), 'sin --voz instaló archivos de voz'
run('--voz')
for name in ['leer.sh', 'despachador.sh', 'limpiar.py', 'callar.sh', 'repetir.sh']:
    assert (voice/name).read_bytes() == (repo/'voz'/name).read_bytes()
    assert os.access(voice/name, os.X_OK)
for path, cli in zip(configs, ['claude', 'codex']):
    own = [h for h in hooks(path) if 'bin/leer.sh' in h['command']]
    assert len(own) == 1
    assert shlex.split(own[0]['command']) == ['/bin/sh', str(voice/'leer.sh'), cli]
    assert own[0]['timeout'] == 10
    assert own[0].get('async') is (True if cli == 'claude' else None)
before = [p.read_bytes() for p in configs]
backups = set(root.glob('voz-*.bak-mascota-*'))
run('--voz'); run()
assert [p.read_bytes() for p in configs] == before
assert set(root.glob('voz-*.bak-mascota-*')) == backups
assert backups
# Una reinstalación en otra ruta sustituye el hook anterior, sin duplicarlo.
voice = root/'voz-nueva/bin'
run('--voz')
for path in configs:
    own = [h for h in hooks(path) if 'bin/leer.sh' in h['command']]
    assert len(own) == 1 and str(voice) in own[0]['command']
    cfg = json.loads(path.read_text())
    cfg['hooks']['Stop'][-1]['hooks'].append({'type':'command','command':'/conservar.sh'})
    path.write_text(json.dumps(cfg))
# Retira la voz aunque no se pase --voz y el destino actual sea distinto.
voice = root/'otra-ruta/bin'
run('--desinstalar')
for path in configs:
    assert [h['command'] for h in hooks(path)] == ['/otra/leer.sh', '/tts.sh', '/conservar.sh']
before = [p.read_bytes() for p in configs]
run('--desinstalar')
assert [p.read_bytes() for p in configs] == before
PY
rm -rf "$T"; echo "OK instalar-hooks"
