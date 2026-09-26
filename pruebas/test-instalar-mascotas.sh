#!/bin/sh
set -eu
RAIZ=$(cd "$(dirname "$0")/.." && pwd)
[ -f "$RAIZ/scripts/instalar-mascotas.sh" ] || { echo "FALLA: falta instalar-mascotas.sh"; exit 1; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
# Dobles solo para las herramientas externas de extracción e inspección de imagen.
cat > "$T/bin/npx" <<'EOF'
#!/bin/sh
[ "$1" = -y ] && [ "$2" = @electron/asar ] || exit 80
case "$3" in
list)
  [ "${FALLAR_LISTADO:-0}" = 0 ] || exit 42
  printf '%s\n' /webview/assets/null-signal-spritesheet-v2-ab12.webp /webview/assets/gato-spritesheet-v1-cd34.webp /webview/assets/roto-spritesheet-v2-ef56.webp /webview/assets/otro.webp
  ;;
extract-file)
  case "$5" in webview/assets/*) printf 'imagen' > "${5##*/}" ;; *) exit 81 ;; esac
  ;;
*) exit 82 ;;
esac
EOF
cat > "$T/bin/sips" <<'EOF'
#!/bin/sh
[ "$1" = -g ] && [ "$2" = pixelHeight ] || exit 83
case "$3" in null-signal-*) alto=2288 ;; gato-*) alto=1872 ;; roto-*) alto=100 ;; *) exit 84 ;; esac
printf '%s\n  pixelHeight: %s\n' "$3" "$alto"
EOF
chmod +x "$T/bin/npx" "$T/bin/sips"
PATH="$T/bin:$PATH" MASCOTA_DIR="$T/datos" sh "$RAIZ/scripts/instalar-mascotas.sh" > "$T/salida" 2> "$T/avisos"
python3 - "$T" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
for ident, name, version in [('null-signal','Null Signal',2), ('gato','Gato',1)]:
    folder = root/'datos/mascotas'/ident
    assert json.loads((folder/'pet.json').read_text()) == {
        'id':ident,'displayName':name,'description':'Mascota incluida en ChatGPT.',
        'spriteVersionNumber':version,'spritesheetPath':'spritesheet.webp'}
    assert (folder/'spritesheet.webp').read_text() == 'imagen'
assert not (root/'datos/mascotas/roto').exists()
assert 'Omito roto' in (root/'avisos').read_text()
PY
if PATH="$T/bin:$PATH" FALLAR_LISTADO=1 MASCOTA_DIR="$T/fallo" sh "$RAIZ/scripts/instalar-mascotas.sh" > "$T/salida" 2> "$T/avisos"; then
  echo 'FALLA: fallo de npx ocultado'; exit 1
fi
echo 'OK instalar-mascotas'
