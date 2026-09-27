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
revisar claude-s1.json cwd /Users/x/vps-prod
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
    run({'hook_event_name':'SubagentStart','session_id':'especial','cwd':'/tmp/'+project,'transcript_path':'/r.jsonl'}, 'codex')
    state = json.loads((root/'estado/codex-especial.json').read_text())
    assert state == dict(cli='codex', session='especial', project=project,
                         state='running', ts=state['ts'], cwd='/tmp/'+project)
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

# Anota el pid del proceso claude/codex más cercano hacia arriba en la cadena de procesos.
falso=$(mktemp -d); ln -s /bin/sh "$falso/claude"
"$falso/claude" -c 'printf "{\"hook_event_name\":\"Stop\",\"session_id\":\"p1\",\"cwd\":\"/a\"}" | "$1" claude; echo $$ > "$2"; true' _ "$HOOK" "$falso/pid"
revisar claude-p1.json pid "$(cat "$falso/pid")"
evento claude Stop p2
[ -z "$(plutil -extract pid raw -o - "$MASCOTA_DIR/estado/claude-p2.json" 2>/dev/null)" ] || { echo "FALLA: pid sin proceso claude"; fallos=$((fallos+1)); }
# El servicio de fondo de Codex (codex app-server) no cuenta como dueño de la sesión.
ln -s /bin/sh "$falso/codex"
"$falso/codex" -c 'printf "{\"hook_event_name\":\"Stop\",\"session_id\":\"d1\",\"cwd\":\"/a\"}" | "$1" codex; true' app-server "$HOOK"
[ -e "$MASCOTA_DIR/estado/codex-d1.json" ] || { echo "FALLA: no escribió la sesión del servicio"; fallos=$((fallos+1)); }
[ -z "$(plutil -extract pid raw -o - "$MASCOTA_DIR/estado/codex-d1.json" 2>/dev/null)" ] || { echo "FALLA: anotó el pid del servicio de fondo"; fallos=$((fallos+1)); }
# Sesiones automáticas: se marcan "auto" para que el menú muestre solo las del usuario.
"$falso/codex" -c 'printf "{\"hook_event_name\":\"Stop\",\"session_id\":\"x1\",\"cwd\":\"/a\",\"transcript_path\":\"/r.jsonl\"}" | "$1" codex; true' exec "$HOOK"
revisar codex-x1.json auto true
printf '{"hook_event_name":"Stop","session_id":"w1","cwd":"/a","transcript_path":null}' | "$HOOK" codex
revisar codex-w1.json auto true
printf '{"hook_event_name":"Stop","session_id":"u1","cwd":"/a","transcript_path":"/r.jsonl"}' | "$HOOK" codex
[ -z "$(plutil -extract auto raw -o - "$MASCOTA_DIR/estado/codex-u1.json" 2>/dev/null)" ] || { echo "FALLA: sesión del usuario marcada auto"; fallos=$((fallos+1)); }
printf '{"hook_event_name":"Stop","session_id":"u2","cwd":"/a","transcript_path":"/r.jsonl"}' | MASCOTA_SIN_VOZ=1 "$HOOK" claude
revisar claude-u2.json auto true
rm -rf "$falso"

rm -rf "$MASCOTA_DIR"
[ $fallos -eq 0 ] && echo "OK pet-hook" || exit 1
