#!/bin/sh
set -eu
RAIZ=$(cd "$(dirname "$0")/.." && pwd)
python3 - "$RAIZ" <<'PY'
import json, os, pathlib, stat, subprocess, sys, tempfile

script = pathlib.Path(sys.argv[1]) / 'scripts/barra-claude.py'
assert script.is_file(), 'falta barra-claude.py'
prefix = 'tee "$HOME/.mascota/claude-barra.json" | '
minimal = 'tee "$HOME/.mascota/claude-barra.json" >/dev/null; echo ""'
with tempfile.TemporaryDirectory(prefix='mascota-barra-') as tmp:
    home = pathlib.Path(tmp) / "casa con 'comilla"
    settings = home / '.claude/settings.json'
    settings.parent.mkdir(parents=True)
    env = dict(os.environ, HOME=str(home))

    def run(*args, ok=True):
        result = subprocess.run([sys.executable, str(script), *args], env=env,
                                capture_output=True, text=True)
        assert (result.returncode == 0) == ok, result.stderr

    def backups():
        return {p: p.read_bytes() for p in settings.parent.glob('*.bak-mascota-*')}

    for line in [dict(type='command', command='cat', padding=2), None]:
        original = dict(model='conservar', hooks={'Stop': []})
        if line is not None:
            original['statusLine'] = line
        settings.write_text(json.dumps(original))
        settings.chmod(0o600)
        before = settings.read_bytes()
        old_backups = backups()
        run()
        cfg = json.loads(settings.read_text())
        expected = dict(original, statusLine=(dict(line, command=prefix+'cat') if line else
                                              dict(type='command', command=minimal)))
        assert cfg == expected
        assert stat.S_IMODE(settings.stat().st_mode) == 0o600
        new_backups = backups()
        assert len(new_backups) == len(old_backups) + 1
        assert next(v for p, v in new_backups.items() if p not in old_backups) == before
        assert all(stat.S_IMODE(p.stat().st_mode) == 0o600 for p in new_backups)
        installed = settings.read_bytes()
        run()
        assert settings.read_bytes() == installed and backups() == new_backups
        # La barra realmente captura stdin y conserva la salida del comando original.
        payload = '{"rate_limits":{"five_hour":{"used_percentage":23}}}\n'
        result = subprocess.run(['/bin/sh', '-c', cfg['statusLine']['command']],
                                input=payload, text=True, capture_output=True, env=env)
        assert result.returncode == 0, result.stderr
        assert result.stdout == (payload if line else '\n')
        assert (home/'.mascota/claude-barra.json').read_text() == payload
        # Un cambio ajeno posterior no se pierde al quitar la captura.
        cfg['model'] = original['model'] = 'cambiado después'
        settings.write_text(json.dumps(cfg))
        run('--quitar')
        assert json.loads(settings.read_text()) == original
        removed, saved = settings.read_bytes(), backups()
        run('--quitar')
        assert settings.read_bytes() == removed and backups() == saved

    settings.unlink()
    run('--quitar')
    assert not settings.exists()
    run()
    assert json.loads(settings.read_text())['statusLine']['command'] == minimal
    run('--quitar')
    assert json.loads(settings.read_text()) == {}
    # No sobrescribir JSON roto ni formas desconocidas de statusLine.
    for invalid in ['{roto', '[]', '{"statusLine":"ajena"}',
                    '{"statusLine":{"type":"command","command":42}}']:
        settings.write_text(invalid)
        saved = backups()
        run(ok=False)
        run('--quitar', ok=False)
        assert settings.read_text() == invalid and backups() == saved
print('OK barra-claude')
PY
