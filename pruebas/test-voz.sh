#!/bin/sh
set -eu
RAIZ=$(cd "$(dirname "$0")/.." && pwd)
python3 - "$RAIZ" <<'PY'
import json, os, pathlib, shutil, subprocess, sys, tempfile, time, traceback

repo = pathlib.Path(sys.argv[1])
errors = []
# Solo las fronteras externas son falsas: síntesis, audio y procesos del usuario.
fake = r'''
import json, os, pathlib, subprocess, sys, time
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['CALLS'], 'a') as f:
    f.write(json.dumps([name, args]) + '\n')
audio = b'ID3\x03\x00\x00\x00\x00\x00\x00' + b'\x00' * 128
if name == 'curl':
    assert '--max-time' in args and args[args.index('--max-time')+1] == '60'
    payload = json.loads(pathlib.Path(args[args.index('--data')+1][1:]).read_text())
    assert payload['model_id'] == 'eleven_multilingual_v2'
    code = os.environ.get('CURL_CODE', '401')
    pathlib.Path(args[args.index('-o')+1]).write_bytes(
        audio if code == '200' else b'{"detail":{"status":"quota_exceeded"}}')
    print(code, end='')
elif name == 'edge-tts':
    if os.environ.get('EDGE_FAIL') == '1': sys.exit(1)
    pathlib.Path(args[args.index('--write-media')+1]).write_bytes(audio)
elif name == 'say':
    with open(os.environ['SPOKEN'], 'a') as f: f.write(sys.stdin.read())
    time.sleep(float(os.environ.get('SAY_DELAY', '0')))
elif name == 'pgrep':
    busy = pathlib.Path(os.environ['BUSY'])
    if busy.exists():
        busy.unlink()
        print('123 afplay')
    else: sys.exit(1)
elif name == 'nohup' and os.environ.get('RUN_NOHUP') == '1':
    subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)
'''

with tempfile.TemporaryDirectory(prefix='mascota-voz-') as temp:
    root = pathlib.Path(temp)
    mocks = root/'falsos'; mocks.mkdir()
    for name in ['afplay', 'say', 'curl', 'edge-tts', 'pkill', 'pgrep', 'nohup']:
        p = mocks/name
        p.write_text('#!' + sys.executable + '\n' + fake)
        p.chmod(0o755)

    def setup(name):
        base = root/name; base.mkdir()
        home = base/'home'; home.mkdir()
        voice = base/'datos/voz'; (voice/'cola').mkdir(parents=True)
        binpath = voice/'bin'; binpath.mkdir()
        for source in (repo/'voz').glob('*'):
            if source.is_file(): shutil.copy2(source, binpath/source.name)
        env = dict(os.environ, HOME=str(home), MASCOTA_DIR=str(base/'datos'),
                   PATH=str(mocks)+os.pathsep+os.environ['PATH'], ELEVENLABS_API_KEY='',
                   CALLS=str(base/'calls'), SPOKEN=str(base/'spoken'), BUSY=str(base/'busy'),
                   EDGE_VOICE='es-MX-DaliaNeural', SAY_VOICE='Mónica',
                   ELEVEN_VOICE='8tm9IYjg8ybDoxe8w6Rk')
        for key in ['EDGE_FAIL', 'CURL_CODE', 'RUN_NOHUP', 'SAY_DELAY']:
            env.pop(key, None)
        return base, voice, binpath, env

    def run(binpath, env, name, *args, data=''):
        assert (binpath/name).exists(), 'falta voz/' + name
        r = subprocess.run(['/bin/sh', str(binpath/name), *args], input=data,
                           capture_output=True, text=True, env=env, timeout=8)
        assert r.returncode == 0, r.stderr
        assert r.stdout == '', repr(r.stdout)
        return r

    def calls(base):
        return [json.loads(x) for x in (base/'calls').read_text().splitlines()] if (base/'calls').exists() else []

    def queued(voice):
        return [p.read_text().splitlines() for p in sorted((voice/'cola').glob('*.job'))]

    def check(name, fn):
        try:
            fn(*setup(name))
        except Exception as e:
            errors.append(name)
            print(f'FALLA voz {name}: {e}')
            traceback.print_exc()

    def hook(base, voice, binpath, env):
        text = '# Hola **mundo**\n```sh\nsecreto_codigo\n```\n- Listo `oculto` [enlace](https://ejemplo.com)\n| tabla |\n'
        for cli in ['claude', 'codex']:
            run(binpath, env, 'leer.sh', cli, data=json.dumps({'session_id':cli,'transcript_path':'/x/r.jsonl','last_assistant_message':text}))
            clean = (voice/f'ultimo-{cli}.txt').read_text()
            assert 'Hola mundo' in clean and 'Listo' in clean
            assert all(x not in clean for x in ['```', '**', 'secreto', 'oculto', 'https', 'tabla'])
            assert (voice/'ultimo.txt').read_text() == clean
        jobs = queued(voice)
        assert [j[:2] for j in jobs] == [['SPEAK','claude'], ['SPEAK','codex']], jobs
        assert '\n'.join(jobs[0][2:]).strip() == clean
        deadline = time.monotonic()+2
        while len([c for c in calls(base) if c[0]=='nohup']) < 2 and time.monotonic()<deadline:
            time.sleep(.02)
        assert len([c for c in calls(base) if c[0]=='nohup']) == 2
        (voice/'OFF').touch()
        run(binpath, env, 'leer.sh', 'claude', data='{"session_id":"off","last_assistant_message":"No leer"}')
        assert not (voice/'ultimo-off.txt').exists() and queued(voice) == jobs
        (voice/'OFF').unlink()
        for bad in ['basura', '{}', '[]', '{"last_assistant_message":42}']:
            run(binpath, env, 'leer.sh', 'claude', data=bad)
        assert queued(voice) == jobs
        blocked = base/'bloqueado'; blocked.write_text('x')
        run(binpath, dict(env, MASCOTA_DIR=str(blocked)), 'leer.sh', 'claude',
            data='{"last_assistant_message":"Hola"}')
    check('leer', hook)

    def cleaner(base, voice, binpath, env):
        assert (binpath/'limpiar.py').exists(), 'falta voz/limpiar.py'
        r = subprocess.run([sys.executable, str(binpath/'limpiar.py')],
            input='Hola /tmp/archivo.py snake_case camelCase abc12345. Espera 25% y 10ms.',
            text=True, capture_output=True, env=env)
        assert r.returncode == 0 and 'Hola' in r.stdout
        assert 'por ciento' in r.stdout and 'milisegundos' in r.stdout
        assert all(s not in r.stdout for s in ['/tmp', 'archivo.py', 'snake_case', 'camelCase', 'abc12345'])
    check('limpiar', cleaner)

    def worker(provider, key='', code='401', edge_fail=False):
        def test(base, voice, binpath, env):
            if provider: (voice/'proveedor').write_text(provider)
            env.update(ELEVENLABS_API_KEY=key, CURL_CODE=code, EDGE_FAIL=str(int(edge_fail)))
            (voice/'cola/001.job').write_text('SPEAK\ns1\nHola voz\n')
            run(binpath, env, 'despachador.sh')
            names = [c[0] for c in calls(base)]
            if provider == 'local' or edge_fail:
                assert 'say' in names and 'afplay' not in names
                assert (base/'spoken').read_text().strip() == 'Hola voz'
                say_args = next(c[1] for c in calls(base) if c[0]=='say')
                assert say_args == ['-v','Mónica','-r','210']
                assert not (voice/'ultimo-s1.mp3').exists()
            else:
                assert 'afplay' in names and 'say' not in names
                assert (voice/'ultimo-s1.mp3').read_bytes().startswith(b'ID3')
            if provider == 'local': assert 'edge-tts' not in names and 'curl' not in names
            elif not key or provider == 'edge': assert 'curl' not in names and 'edge-tts' in names
            elif code == '401':
                line = [s for s in (voice/'voz.log').read_text().splitlines() if s.startswith('ELEVEN')][-1]
                assert line.startswith('ELEVEN FAIL (401') and 'quota_exceeded' in line
                assert names.index('curl') < names.index('edge-tts') < names.index('afplay')
            else:
                assert any(s.startswith('ELEVEN OK') for s in (voice/'voz.log').read_text().splitlines())
                assert 'edge-tts' not in names
            if 'edge-tts' in names:
                args = next(c[1] for c in calls(base) if c[0]=='edge-tts')
                assert args[args.index('-v')+1] == 'es-MX-DaliaNeural'
            assert not queued(voice) and not (voice/'despachador.lock').exists()
        return test
    for name, args in [('local',('local',)), ('edge',('edge','clave-falsa')),
                       ('sin-clave',('eleven',)), ('cuota',('', 'clave-falsa')),
                       ('eleven-ok',('eleven','clave-falsa','200')),
                       ('edge-falla',('edge','','401',True))]:
        check(name, worker(*args))

    def fifo(base, voice, binpath, env):
        (voice/'proveedor').write_text('local')
        (voice/'cola/002.job').write_text('SPEAK\ns2\nSegundo\n')
        (voice/'cola/001.job').write_text('SPEAK\ns1\nPrimero\n')
        (voice/'despachador.lock').mkdir()
        run(binpath, env, 'despachador.sh')
        assert len(queued(voice)) == 2 and not calls(base), (queued(voice), calls(base))
        (voice/'despachador.lock').rmdir()
        (base/'busy').touch()
        run(binpath, env, 'despachador.sh')
        assert (base/'spoken').read_text() == 'Primero\nSegundo\n', repr((base/'spoken').read_text())
        names = [c[0] for c in calls(base)]
        # Primera vuelta: afplay ocupado; segunda: afplay y say libres.
        assert names[:names.index('say')].count('pgrep') >= 3, calls(base)
    check('fifo-singleton-espera', fifo)

    def replay(base, voice, binpath, env):
        run(binpath, env, 'repetir.sh')
        assert not queued(voice)
        (voice/'ultimo.txt').write_text('Último texto')
        run(binpath, env, 'repetir.sh')
        assert queued(voice)[-1] == ['SPEAK','global','Último texto']
        old = voice/'ultimo-antiguo.mp3'; old.write_bytes(b'old'); os.utime(old, (1,1))
        new = voice/'ultimo-reciente.mp3'; new.write_bytes(b'new')
        run(binpath, env, 'repetir.sh', 'antiguo')
        assert queued(voice)[-1] == ['PLAY','antiguo',str(old)]
        run(binpath, env, 'repetir.sh', 'inexistente')
        assert queued(voice)[-1] == ['PLAY','reciente',str(new)]
        # Procesar PLAY no sintetiza ni pierde la ruta que contiene espacios.
        for p in (voice/'cola').glob('*.job'): p.unlink()
        (voice/'cola/001.job').write_text(f'PLAY\nreciente\n{new}\n')
        run(binpath, env, 'despachador.sh')
        assert any(c[0]=='afplay' and c[1][-1]==str(new) for c in calls(base))
        assert not any(c[0] in ['curl','edge-tts','say'] for c in calls(base))
        (voice/'cola/002.job').write_text('SPEAK\ns1\nNo leer\n')
        run(binpath, env, 'callar.sh')
        assert not queued(voice)
        assert ['pkill',['-x','afplay']] in calls(base) and ['pkill',['-x','say']] in calls(base)
    check('repetir-callar', replay)

    def background(base, voice, binpath, env):
        env.update(RUN_NOHUP='1', SAY_DELAY='1.5')
        (voice/'proveedor').write_text('local')
        start = time.monotonic()
        run(binpath, env, 'leer.sh', 'codex', data='{"session_id":"bg","transcript_path":"/x/r.jsonl","last_assistant_message":"Hola fondo"}')
        assert time.monotonic()-start < 1.3, 'el hook esperó al audio'
        deadline = time.monotonic()+6
        while time.monotonic()<deadline:
            if (base/'spoken').exists() and not (voice/'despachador.lock').exists(): break
            time.sleep(.05)
        assert (base/'spoken').read_text().strip() == 'Hola fondo'
        assert not (voice/'despachador.lock').exists() and not queued(voice)
    check('segundo-plano', background)

if errors:
    sys.exit(1)
print('OK voz')
PY
