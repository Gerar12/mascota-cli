#!/bin/sh
set -u
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
HOOK="$RAIZ/hooks/pet-hook.sh"
export MASCOTA_DIR=$(mktemp -d)
trap 'rm -rf "$MASCOTA_DIR"' EXIT
fallos=0
evento() { printf '{"hook_event_name":"%s","session_id":"%s","cwd":"/Users/x/vps-prod"}' "$2" "$3" | "$HOOK" "$1"; }
revisar() { # archivo campo esperado
  real=$(plutil -extract "$2" raw -o - "$MASCOTA_DIR/estado/$1" 2>/dev/null)
  [ "$real" = "$3" ] || { echo "FALLA $1 $2: '$real' != '$3'"; fallos=$((fallos+1)); }
}

salida=$(evento claude UserPromptSubmit s1)
[ -z "$salida" ] || { echo "FALLA: el hook imprimió '$salida'"; fallos=$((fallos+1)); }
revisar claude-s1.json state running
revisar claude-s1.json project vps-prod
revisar claude-s1.json cli claude
evento claude PermissionRequest s1; revisar claude-s1.json state waiting
evento claude PostToolUse s1;       revisar claude-s1.json state running
evento claude Stop s1;              revisar claude-s1.json state done
evento claude StopFailure s1;       revisar claude-s1.json state failed
evento codex PreToolUse 'c/../2';   revisar codex-c..2.json state running
evento codex Notification s9;       [ ! -e "$MASCOTA_DIR/estado/codex-s9.json" ] || { echo "FALLA: evento ignorado creó archivo"; fallos=$((fallos+1)); }
evento claude SessionEnd s1;        [ ! -e "$MASCOTA_DIR/estado/claude-s1.json" ] || { echo "FALLA: SessionEnd no borró"; fallos=$((fallos+1)); }
echo 'basura' | "$HOOK" claude;     [ $? -eq 0 ] || { echo "FALLA: exit != 0 con basura"; fallos=$((fallos+1)); }
[ -z "$(find "$MASCOTA_DIR/estado" -type f -name '.*')" ] || { echo "FALLA: quedaron temporales"; fallos=$((fallos+1)); }

rm -rf "$MASCOTA_DIR"
[ $fallos -eq 0 ] && echo "OK pet-hook" || exit 1
