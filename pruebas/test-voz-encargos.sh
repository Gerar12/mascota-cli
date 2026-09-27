#!/bin/sh
# La voz no lee las sesiones automáticas (codex exec, claude -p) ni las marcadas con MASCOTA_SIN_VOZ.
set -u
RAIZ=$(cd "$(dirname "$0")/.." && pwd)
LEER="$RAIZ/voz/leer.sh"
export MASCOTA_DIR=$(mktemp -d)
falso=$(mktemp -d)
fallos=0
json='{"session_id":"s","last_assistant_message":"Hola mundo"}'
encolados() { find "$MASCOTA_DIR/voz/cola" -name '*.job' 2>/dev/null | wc -l | tr -d ' '; }
limpiar() { rm -rf "$MASCOTA_DIR/voz"; mkdir -p "$MASCOTA_DIR/voz"; }
esperar() { # nombre esperado(0/1)
  sleep 1
  [ "$(encolados)" = "$2" ] || { echo "FALLA $1: encolados=$(encolados), esperaba $2"; fallos=$((fallos+1)); }
  limpiar
}
# El despachador no debe correr de verdad: se reemplaza por uno vacío en una copia de voz/.
cp -R "$RAIZ/voz" "$falso/voz"; printf '#!/bin/sh\nexit 0\n' > "$falso/voz/despachador.sh"; LEER="$falso/voz/leer.sh"
ln -s /bin/sh "$falso/codex"; ln -s /bin/sh "$falso/claude"
limpiar

"$falso/codex" -c 'printf "%s" "$1" | "$2" codex; true' exec "$json" "$LEER"
esperar "codex exec no se lee" 0
"$falso/claude" -c 'printf "%s" "$1" | "$2" claude; true' -p "$json" "$LEER"
esperar "claude -p no se lee" 0
printf '%s' "$json" | MASCOTA_SIN_VOZ=1 "$LEER" claude
esperar "MASCOTA_SIN_VOZ no se lee" 0
"$falso/codex" -c 'printf "%s" "$1" | "$2" codex; true' tui "$json" "$LEER"
esperar "codex interactivo sí se lee" 1
"$falso/claude" -c 'printf "%s" "$1" | "$2" claude; true' _ "$json" "$LEER"
esperar "claude interactivo sí se lee" 1

rm -rf "$MASCOTA_DIR" "$falso"
[ $fallos -eq 0 ] && echo "OK voz-encargos" || exit 1
