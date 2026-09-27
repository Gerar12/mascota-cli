#!/bin/sh
# Instalación completa. MASCOTA_SIN_COMPILAR=1 omite la compilación y la app.
set -eu
RAIZ=$(cd "$(dirname "$0")/.." && pwd)
voz=preguntar
for argumento in "$@"; do
  case "$argumento" in
    --voz)
      [ "$voz" != no ] || { echo 'No combines --voz y --sin-voz.' >&2; exit 1; }
      voz=si ;;
    --sin-voz)
      [ "$voz" != si ] || { echo 'No combines --voz y --sin-voz.' >&2; exit 1; }
      voz=no ;;
    *) echo 'Uso: sh scripts/instalar.sh [--voz | --sin-voz]' >&2; exit 1 ;;
  esac
done

[ "$(uname -s)" = Darwin ] || { echo 'Mascota requiere macOS 14 o superior.' >&2; exit 1; }
version=$(sw_vers -productVersion)
mayor=${version%%.*}
case "$mayor" in
  ''|*[!0-9]*) echo "No pude comprobar la versión de macOS: $version" >&2; exit 1 ;;
esac
[ "$mayor" -ge 14 ] || { echo 'Mascota requiere macOS 14 o superior.' >&2; exit 1; }
command -v swift >/dev/null 2>&1 || {
  echo 'Falta swift. Ejecuta xcode-select --install y vuelve a instalar Mascota.' >&2
  exit 1
}
command -v python3 >/dev/null 2>&1 || { echo 'Falta python3. Instálalo y vuelve a intentar.' >&2; exit 1; }
pillow=si
if ! python3 -c 'from PIL import Image' >/dev/null 2>&1; then
  pillow=no
  echo 'Aviso: falta Pillow; se continuará sin ícono ni dibujo de Clawd.' >&2
fi

mkdir -p "$HOME/.mascota"
# Ruta sustituible para probar ambas ramas sin tocar /Applications.
CHATGPT_APP=${MASCOTA_CHATGPT_APP:-/Applications/ChatGPT.app}
if [ -d "$CHATGPT_APP" ]; then
  MASCOTA_DIR="$HOME/.mascota" MASCOTA_ASAR="$CHATGPT_APP/Contents/Resources/app.asar" \
    sh "$RAIZ/scripts/instalar-mascotas.sh"
  mascotas='Mascotas copiadas de ChatGPT.app.'
elif [ "$pillow" = si ]; then
  python3 "$RAIZ/scripts/dibujar-clawd.py" "$HOME/.mascota/mascotas/clawd"
  elegida=$(defaults read dev.gcoder.mascota mascota 2>/dev/null || true)
  if [ -z "$elegida" ]; then
    defaults write dev.gcoder.mascota mascota clawd
  fi
  mascotas='Clawd instalado en ~/.mascota/mascotas/clawd.'
else
  mascotas='No se añadieron mascotas: faltan ChatGPT.app y Pillow.'
fi

if [ "$voz" = preguntar ]; then
  printf '¿Instalar también los hooks de voz? [s/N] '
  respuesta=
  if IFS= read -r respuesta; then
    case "$respuesta" in s|S) voz=si ;; *) voz=no ;; esac
  else
    voz=no
  fi
fi
if [ "$voz" = si ]; then
  python3 "$RAIZ/scripts/instalar-hooks.py" --voz
else
  python3 "$RAIZ/scripts/instalar-hooks.py"
fi
python3 "$RAIZ/scripts/barra-claude.py"

if [ "${MASCOTA_SIN_COMPILAR:-0}" = 1 ]; then
  app='Compilación e instalación de la app omitidas (MASCOTA_SIN_COMPILAR=1).'
else
  sh "$RAIZ/scripts/empaquetar.sh"
  app='App compilada, instalada en ~/Applications/Mascota.app y abierta.'
fi
printf '\nResumen de instalación:\n- %s\n- Hooks de Claude y Codex instalados (voz solicitada: %s).\n- Captura de cuota de Claude configurada.\n- %s\n' "$mascotas" "$voz" "$app"
echo 'Para aprobar los hooks en Codex: abre codex → Trust all.'
