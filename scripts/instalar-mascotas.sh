#!/bin/sh
# Copia las mascotas incluidas en ChatGPT.app a ~/.mascota/mascotas (solo uso personal en esta Mac).
set -eu
ASAR=/Applications/ChatGPT.app/Contents/Resources/app.asar
DESTINO="${MASCOTA_DIR:-$HOME/.mascota}/mascotas"
[ -f "$ASAR" ] || { echo "No encuentro ChatGPT.app" >&2; exit 1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
# Guardar el listado evita que una tubería oculte un fallo de npx.
npx -y @electron/asar list "$ASAR" > "$TMP/listado"
grep -E '^/webview/assets/[a-z0-9-]+-spritesheet-v[0-9]+-[0-9a-f]+\.webp$' "$TMP/listado" > "$TMP/mascotas" || { echo "No encontré mascotas en ChatGPT.app" >&2; exit 1; }
while IFS= read -r ruta; do
  archivo=$(basename "$ruta")
  id=$(printf '%s' "$archivo" | sed -E 's/-spritesheet-v[0-9]+-[0-9a-f]+\.webp$//')
  npx -y @electron/asar extract-file "$ASAR" "${ruta#/}"
  alto=$(sips -g pixelHeight "$archivo" | awk '/pixelHeight/ {print $2}')
  case "$alto" in 2288) version=2 ;; 1872) version=1 ;; *) echo "Omito $id (alto $alto)" >&2; continue ;; esac
  nombre=$(printf '%s' "$id" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)} 1')
  mkdir -p "$DESTINO/$id"
  mv -f "$archivo" "$DESTINO/$id/spritesheet.webp"
  printf '{"id":"%s","displayName":"%s","description":"Mascota incluida en ChatGPT.","spriteVersionNumber":%s,"spritesheetPath":"spritesheet.webp"}\n' \
    "$id" "$nombre" "$version" > "$DESTINO/$id/pet.json"
  echo "Instalada $nombre"
done < "$TMP/mascotas"
