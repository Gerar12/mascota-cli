#!/bin/sh
# Quita la app y sus integraciones; conserva los datos salvo confirmación.
set -eu
RAIZ=$(cd "$(dirname "$0")/.." && pwd)
todo=no
for argumento in "$@"; do
  case "$argumento" in
    --todo) todo=si ;;
    *) echo 'Uso: sh scripts/desinstalar.sh [--todo]' >&2; exit 1 ;;
  esac
done
command -v python3 >/dev/null 2>&1 || { echo 'Se necesita python3 para retirar las integraciones.' >&2; exit 1; }
pkill -x Mascota 2>/dev/null || true
python3 "$RAIZ/scripts/instalar-hooks.py" --desinstalar
python3 "$RAIZ/scripts/barra-claude.py" --quitar
rm -rf "$HOME/Applications/Mascota.app"
if [ "$todo" = no ] && [ -d "$HOME/.mascota" ]; then
  printf '¿Borrar también ~/.mascota y todos sus datos? [s/N] '
  respuesta=
  if IFS= read -r respuesta; then
    case "$respuesta" in s|S) todo=si ;; esac
  fi
fi
if [ "$todo" = si ]; then
  rm -rf "$HOME/.mascota"
  echo 'Mascota desinstalada; datos de ~/.mascota borrados.'
else
  echo 'Mascota desinstalada; datos de ~/.mascota conservados.'
fi
