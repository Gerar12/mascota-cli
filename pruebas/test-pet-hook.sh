#!/bin/sh
set -u
RAIZ=$(cd "$(dirname "$0")/.." && pwd)
HOOK="$RAIZ/hooks/pet-hook.sh"
export MASCOTA_DIR=$(mktemp -d)
trap 'rm -rf "$MASCOTA_DIR"' EXIT
fallos=0
evento() { printf '{"hook_event_name":"%s","session_id":"%s","cwd":"/Users/x/vps-prod"}' "$2" "$3" | "$HOOK" "$1"; }
revisar() { # archivo campo esperado
  real=$(plutil -extract "$2" raw -o - "$MASCOTA_DIR/estado/$1" 2>/dev/null)
  [ "$real" = "$3" ] || { echo "FALLA $1 $2: '$real' != '$3'"; fallos=$((fallos+1)); }
}

salida=$(evento claude UserPromptSubmit s1)
[ -z "$salida" ] || { echo "FALLA: el hook imprimió '$salida'"; fallos=$((fallos+1)); }
revisar claude-s1.json state running
revisar claude-s1.json project vps-prod
revisar claude-s1.json cli claude
evento claude PermissionRequest s1; revisar claude-s1.json state waiting
evento claude PostToolUse s1;       revisar claude-s1.json state running
evento claude Stop s1;              revisar claude-s1.json state done
evento claude StopFailure s1;       revisar claude-s1.json state failed
evento codex PreToolUse 'c/../2';   revisar codex-c..2.json state running
evento codex Notification s9;       [ ! -e "$MASCOTA_DIR/estado/codex-s9.json" ] || { echo "FALLA: evento ignorado creó archivo"; fallos=$((fallos+1)); }
evento claude SessionEnd s1;        [ ! -e "$MASCOTA_DIR/estado/claude-s1.json" ] || { echo "FALLA: SessionEnd no borró"; fallos=$((fallos+1)); }
echo 'basura' | "$HOOK" claude;     [ $? -eq 0 ] || { echo "FALLA: exit != 0 con basura"; fallos=$((fallos+1)); }
[ -z "$(find "$MASCOTA_DIR/estado" -type f -name '.*')" ] || { echo "FALLA: quedaron temporales"; fallos=$((fallos+1)); }

python3 - "$HOOK" "$MASCOTA_DIR" <<'PY' || fallos=$((fallos+1))
import json, os, pathlib, subprocess, sys, time
hook, root = sys.argv[1], pathlib.Path(sys.argv[2])
errors = []
def run(payload, *args, directory=None):
    env = dict(os.environ, MASCOTA_DIR=str(directory or root))
    r = subprocess.run([hook, *args], input=json.dumps(payload), text=True,
                       capture_output=True, env=env)
    assert (r.returncode, r.stdout, r.stderr) == (0, '', ''), r
def check(name, test):
    try:
        test()
    except (AssertionError, OSError, ValueError) as e:
        errors.append(name)
        print(f'FALLA {name}: {e}')
def explicit_event():
    run({'session_id':'argumento','cwd':'/a'}, 'claude', 'PreToolUse')
    assert json.loads((root/'estado/claude-argumento.json').read_text())['state'] == 'running'
check('evento como argumento', explicit_event)
def special_project():
    project = 'á "comillas" \\ barra\ttab\nsalto\n'
    run({'hook_event_name':'SubagentStart','session_id':'especial','cwd':'/tmp/'+project}, 'codex')
    state = json.loads((root/'estado/codex-especial.json').read_text())
    assert state == dict(cli='codex', session='especial', project=project,
                         state='running', ts=state['ts'])
    assert abs(state['ts'] - time.time()) < 5
check('escape JSON sin perder nombre', special_project)
def missing_cwd():
    run({'hook_event_name':'Stop','session_id':'sin-cwd'}, 'claude')
    assert json.loads((root/'estado/claude-sin-cwd.json').read_text())['project'] == '?'
check('cwd ausente', missing_cwd)
def invalid_inputs():
    before = set((root/'estado').iterdir())
    for payload, cli in [({'hook_event_name':'Stop'}, 'claude'),
                         ({'hook_event_name':'Stop','session_id':42}, 'claude'),
                         ({'hook_event_name':'Stop','session_id':'x'}, 'invalido')]:
        run(payload, cli)
    assert set((root/'estado').iterdir()) == before
check('campos inválidos no crean estados', invalid_inputs)
def unwritable():
    blocked = root/'archivo-no-directorio'
    blocked.write_text('x')
    run({'hook_event_name':'Stop','session_id':'bloqueado'}, 'claude', directory=blocked)
check('error de escritura silencioso', unwritable)
assert not errors, errors
PY

rm -rf "$MASCOTA_DIR"
[ $fallos -eq 0 ] && echo "OK pet-hook" || exit 1
