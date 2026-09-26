#!/usr/bin/env python3
"""Instala o retira Mascota sin modificar los hooks de otras herramientas."""
import argparse
import json
import os
import shlex
import shutil
import stat
import tempfile
from datetime import datetime
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
EVENTOS = {
    'claude': ['UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'SubagentStart',
               'PermissionRequest', 'Stop', 'StopFailure', 'SessionEnd'],
    'codex': ['UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'SubagentStart',
              'PermissionRequest', 'Stop', 'SessionEnd'],
}
CON_MATCHER = {'PreToolUse', 'PostToolUse', 'PermissionRequest'}


def es_nuestro(hook, destino, cli):
    try:
        return hook.get('type') == 'command' and shlex.split(hook.get('command', '')) == [
            '/bin/sh', str(destino), cli]
    except ValueError:
        return False


def actualizar(cfg, cli, destino, quitar):
    if quitar and 'hooks' not in cfg:
        return
    hooks = cfg.setdefault('hooks', {})
    for evento in EVENTOS[cli]:
        grupos = hooks.get(evento, [])
        if quitar:
            conservados = []
            for grupo in grupos:
                restantes = [h for h in grupo.get('hooks', []) if not es_nuestro(h, destino, cli)]
                if len(restantes) == len(grupo.get('hooks', [])):
                    conservados.append(grupo)
                elif restantes:
                    conservados.append(dict(grupo, hooks=restantes))
            grupos = conservados
        elif not any(es_nuestro(h, destino, cli) for g in grupos for h in g.get('hooks', [])):
            hook = {'type': 'command', 'command': f'/bin/sh {shlex.quote(str(destino))} {cli}',
                    'timeout': 5}
            if cli == 'claude':
                hook['async'] = True
            grupo = {'hooks': [hook]}
            if evento in CON_MATCHER:
                grupo['matcher'] = '*'
            grupos = grupos + [grupo]
        if grupos:
            hooks[evento] = grupos
        else:
            hooks.pop(evento, None)


def guardar(ruta, cfg):
    ruta.parent.mkdir(parents=True, exist_ok=True)
    if ruta.exists():
        # Microsegundos y creación exclusiva: jamás reemplazar un respaldo.
        respaldo = ruta.with_name(ruta.name + '.bak-mascota-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
        with respaldo.open('xb') as salida:
            salida.write(ruta.read_bytes())
        shutil.copystat(ruta, respaldo)
    fd, temporal = tempfile.mkstemp(prefix='.' + ruta.name, dir=ruta.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as salida:
            json.dump(cfg, salida, indent=2, ensure_ascii=False)
            salida.write('\n')
        if ruta.exists():
            os.chmod(temporal, stat.S_IMODE(ruta.stat().st_mode))
        os.replace(temporal, ruta)
    finally:
        if os.path.exists(temporal):
            os.unlink(temporal)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--claude', default='~/.claude/settings.json')
    p.add_argument('--codex', default='~/.codex/hooks.json')
    p.add_argument('--destino-hook', default='~/.mascota/pet-hook.sh')
    p.add_argument('--desinstalar', action='store_true')
    a = p.parse_args()
    destino = Path(a.destino_hook).expanduser().absolute()
    cambios = []
    # Leer ambos archivos antes de modificar cualquiera.
    for cli in EVENTOS:
        ruta = Path(getattr(a, cli)).expanduser()
        if a.desinstalar and not ruta.exists():
            continue
        cfg = json.loads(ruta.read_text(encoding='utf-8')) if ruta.exists() else {}
        anterior = json.dumps(cfg)
        actualizar(cfg, cli, destino, a.desinstalar)
        if json.dumps(cfg) != anterior:
            cambios.append((ruta, cfg))
    if not a.desinstalar:
        destino.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(RAIZ / 'hooks' / 'pet-hook.sh', destino)
        destino.chmod(destino.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    for ruta, cfg in cambios:
        guardar(ruta, cfg)
    print('Hooks de Mascota ' + ('quitados' if a.desinstalar else 'instalados'))


if __name__ == '__main__':
    main()
