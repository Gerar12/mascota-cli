#!/usr/bin/env python3
"""Activa o retira la captura de cuota sin reemplazar la barra de Claude."""
import argparse
import json
import os
import shutil
import stat
import tempfile
from datetime import datetime
from pathlib import Path

PREFIJO = 'tee "$HOME/.mascota/claude-barra.json" | '
MINIMO = 'tee "$HOME/.mascota/claude-barra.json" >/dev/null; echo ""'


def actualizar(cfg, quitar):
    if not isinstance(cfg, dict):
        raise ValueError('settings.json debe contener un objeto JSON')
    if 'statusLine' not in cfg:
        if quitar:
            return False
        cfg['statusLine'] = {'type': 'command', 'command': MINIMO}
        return True
    barra = cfg['statusLine']
    if (not isinstance(barra, dict) or barra.get('type') != 'command'
            or not isinstance(barra.get('command'), str)):
        raise ValueError('statusLine debe ser de tipo command y tener un comando de texto')
    comando = barra['command']
    if quitar:
        if barra == {'type': 'command', 'command': MINIMO}:
            del cfg['statusLine']
        elif comando.startswith(PREFIJO):
            barra['command'] = comando[len(PREFIJO):]
        elif comando == MINIMO:
            # Si el usuario añadió opciones a nuestra barra mínima, conservarlas.
            barra['command'] = 'echo ""'
        else:
            return False
    else:
        if comando.startswith(PREFIJO) or comando == MINIMO:
            return False
        barra['command'] = PREFIJO + comando
    return True


def guardar(ruta, cfg):
    ruta.parent.mkdir(parents=True, exist_ok=True)
    if ruta.exists():
        respaldo = ruta.with_name(ruta.name + '.bak-mascota-' +
                                 datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
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
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--quitar', action='store_true', help='retirar la captura de cuota')
    args = parser.parse_args()
    ruta = Path.home() / '.claude/settings.json'
    try:
        cfg = json.loads(ruta.read_text(encoding='utf-8')) if ruta.exists() else {}
        cambio = actualizar(cfg, args.quitar)
        if not args.quitar:
            (Path.home() / '.mascota').mkdir(parents=True, exist_ok=True)
        if cambio:
            guardar(ruta, cfg)
    except (OSError, ValueError) as error:
        parser.exit(1, f'No se pudo configurar la barra de Claude: {error}\n')
    print('Captura de cuota de Claude ' + ('retirada' if args.quitar else 'configurada') +
          ('.' if cambio else ' (sin cambios).'))


if __name__ == '__main__':
    main()
