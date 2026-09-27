#!/bin/sh
set -eu
RAIZ=$(cd "$(dirname "$0")/.." && pwd)
python3 - "$RAIZ" <<'PY'
import json, os, pathlib, shutil, subprocess, sys, tempfile

repo = pathlib.Path(sys.argv[1])
for name in ['instalar.sh', 'desinstalar.sh']:
    assert (repo/'scripts'/name).is_file(), 'falta ' + name
    assert os.access(repo/'scripts'/name, os.X_OK), 'no ejecutable: ' + name

# Fronteras externas: defaults, macOS, dibujo, extracción, compilación y audio.
# Los instaladores de hooks y barra sí corren de verdad con HOME temporal.
fake = r'''
import json, os, pathlib, sys
name, args = pathlib.Path(sys.argv[0]).name, sys.argv[1:]
with open(os.environ['CALLS'], 'a') as log:
    log.write(json.dumps([name, args]) + '\n')
if name == 'uname': print(os.environ.get('OS_FALSO', 'Darwin'))
elif name == 'sw_vers': print(os.environ.get('VERSION_FALSA', '14.0'))
elif name == 'defaults':
    assert args[1:3] == ['dev.gcoder.mascota', 'mascota'], args
    pref = pathlib.Path(os.environ['HOME'])/'preferencia'
    if args[0] == 'read':
        if not pref.exists(): sys.exit(1)
        print(pref.read_text())
    elif args[0] == 'write': pref.write_text(args[3])
    else: raise AssertionError(args)
elif name == 'python3':
    if args == ['-c', 'from PIL import Image']: sys.exit(int(os.environ.get('SIN_PILLOW', '0')))
    if args and pathlib.Path(args[0]).name == 'dibujar-clawd.py':
        assert args[1:] == [str(pathlib.Path(os.environ['HOME'])/'.mascota/mascotas/clawd')]
        folder = pathlib.Path(args[1]); folder.mkdir(parents=True, exist_ok=True)
        (folder/'pet.json').write_text('{"id":"clawd"}')
        (folder/'spritesheet.png').write_bytes(b'dibujo falso')
    else: os.execv(sys.executable, [sys.executable, *args])
elif name == 'npx':
    assert args[:2] == ['-y', '@electron/asar']
    if args[2] == 'list': print('/webview/assets/gato-spritesheet-v2-ab12.webp')
    elif args[2] == 'extract-file': pathlib.Path(args[4]).name and pathlib.Path(pathlib.Path(args[4]).name).write_bytes(b'imagen falsa')
    else: raise AssertionError(args)
elif name == 'sips': print('pixelHeight: 2288')
elif name == 'pkill':
    assert args == ['-x', 'Mascota'], args
    sys.exit(1)  # También funciona cuando la app ya está cerrada.
elif name == 'sh':
    assert not any(pathlib.Path(a).name == 'empaquetar.sh' for a in args), 'intentó empaquetar'
    os.execv('/bin/sh', ['/bin/sh', *args])
else: raise AssertionError('Comando prohibido en pruebas: ' + name)
'''

with tempfile.TemporaryDirectory(prefix='mascota-instalar-') as tmp:
    root = pathlib.Path(tmp)
    mocks = root/'bin'; mocks.mkdir()
    for name in ['uname', 'sw_vers', 'defaults', 'python3', 'npx', 'sips', 'pkill',
                 'sh', 'swift', 'open', 'say', 'afplay', 'curl', 'osascript', 'xcode-select']:
        path = mocks/name
        path.write_text('#!' + sys.executable + '\n' + fake)
        path.chmod(0o755)
    # PATH cerrado: no puede caer en herramientas externas reales por accidente.
    for name in ['dirname', 'mkdir', 'mktemp', 'rm', 'grep', 'basename', 'sed',
                 'awk', 'tr', 'mv', 'cp', 'head']:
        (mocks/name).symlink_to(shutil.which(name))

    def setup(name, chatgpt=False):
        home = root/name/"casa con 'comilla"; home.mkdir(parents=True)
        pets = home/'.codex/pets/propia'; pets.mkdir(parents=True)
        (pets/'pet.json').write_text('no tocar')
        (home/'.claude').mkdir()
        (home/'.claude/settings.json').write_text(json.dumps({
            'model': 'conservar', 'statusLine': {'type': 'command', 'command': 'cat'},
            'hooks': {'Stop': [{'hooks': [{'type': 'command', 'command': '/ajeno.sh'}]}]}}))
        app = home/'ChatGPT.app'
        if chatgpt:
            (app/'Contents/Resources').mkdir(parents=True)
            (app/'Contents/Resources/app.asar').touch()
        env = dict(os.environ, HOME=str(home), PATH=str(mocks), CALLS=str(home/'calls'),
                   MASCOTA_SIN_COMPILAR='1', MASCOTA_CHATGPT_APP=str(app))
        for key in ['MASCOTA_DIR', 'MASCOTA_ASAR', 'SIN_PILLOW', 'OS_FALSO', 'VERSION_FALSA']:
            env.pop(key, None)
        return home, env

    def run(env, *args, script='instalar.sh', data='', ok=True):
        result = subprocess.run(['/bin/sh', str(repo/'scripts'/script), *args],
                                env=env, input=data, capture_output=True, text=True, timeout=15)
        assert (result.returncode == 0) == ok, result.stdout + result.stderr
        return result.stdout + result.stderr

    def calls(home):
        path = home/'calls'
        return [json.loads(s) for s in path.read_text().splitlines()] if path.exists() else []

    def commands(home):
        return [h['command'] for g in json.loads((home/'.claude/settings.json').read_text())['hooks']['Stop']
                for h in g['hooks']]

    home, env = setup('clawd')
    output = run(env, '--sin-voz')
    assert 'Trust all' in output and 'codex' in output and 'omitida' in output.lower()
    assert (home/'.mascota/mascotas/clawd/pet.json').exists()
    assert (home/'preferencia').read_text() == 'clawd'
    assert (home/'.mascota/pet-hook.sh').exists()
    assert not (home/'.mascota/voz').exists()
    before = {p: p.read_bytes() for folder in ['.claude', '.codex'] for p in (home/folder).rglob('*') if p.is_file()}
    (home/'preferencia').write_text('propia')
    run(env, '--sin-voz')
    assert (home/'preferencia').read_text() == 'propia'
    assert before == {p: p.read_bytes() for folder in ['.claude', '.codex'] for p in (home/folder).rglob('*') if p.is_file()}
    assert sum(name == 'defaults' and args[0] == 'write' for name, args in calls(home)) == 1

    for name, flags, answer, voice in [('voz', ['--voz'], '', True), ('acepta', [], 's\n', True),
                                      ('rechaza', [], 'n\n', False), ('vacia', [], '\n', False),
                                      ('eof', [], '', False)]:
        house, variables = setup(name)
        run(variables, *flags, data=answer)
        assert (house/'.mascota/voz/bin/leer.sh').exists() == voice
        assert any('bin/leer.sh' in c for c in commands(house)) == voice

    house, variables = setup('chatgpt', chatgpt=True)
    run(variables, '--sin-voz')
    assert (house/'.mascota/mascotas/gato/pet.json').exists()
    assert not (house/'.mascota/mascotas/clawd').exists()
    assert not (house/'preferencia').exists()

    house, variables = setup('sin-pillow')
    output = run(dict(variables, SIN_PILLOW='1'), '--sin-voz')
    assert 'Pillow' in output and 'ícono' in output and 'Clawd' in output
    assert not (house/'.mascota/mascotas/clawd').exists()
    assert not (house/'preferencia').exists()
    assert (house/'.mascota/pet-hook.sh').exists()

    for key, value, message in [('VERSION_FALSA', '13.6', '14'), ('OS_FALSO', 'Linux', 'macOS')]:
        house, variables = setup(key)
        assert message in run(dict(variables, **{key:value}), '--sin-voz', ok=False)
        assert not (house/'.mascota').exists()
    for tool, message in [('swift', 'xcode-select --install'), ('python3', 'python3')]:
        house, variables = setup('sin-' + tool)
        (mocks/tool).rename(mocks/(tool+'.oculto'))
        try:
            assert message in run(variables, '--sin-voz', ok=False)
            assert not (house/'.mascota').exists()
        finally:
            (mocks/(tool+'.oculto')).rename(mocks/tool)
    run(env, '--desconocido', ok=False)
    run(env, '--voz', '--sin-voz', ok=False)

    # Desinstalar por defecto conserva datos; --todo y la respuesta s los borran.
    for name, flags, answer, delete in [('conservar', [], '', False),
                                       ('borrar', [], 's\n', True), ('todo', ['--todo'], '', True)]:
        house, variables = setup(name)
        run(variables, '--voz')
        app = house/'Applications/Mascota.app'; app.mkdir(parents=True)
        (app/'archivo').touch()
        run(variables, *flags, script='desinstalar.sh', data=answer)
        assert not app.exists()
        assert (house/'.mascota').exists() != delete
        cfg = json.loads((house/'.claude/settings.json').read_text())
        assert cfg['statusLine']['command'] == 'cat' and cfg['model'] == 'conservar'
        assert commands(house) == ['/ajeno.sh']
        assert not json.loads((house/'.codex/hooks.json').read_text())['hooks']
        assert (house/'.codex/pets/propia/pet.json').read_text() == 'no tocar'
        run(variables, *flags, script='desinstalar.sh', data=answer)
        assert (house/'.mascota').exists() != delete
print('OK instalar (incluye desinstalar)')
PY
