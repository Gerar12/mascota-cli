#!/bin/sh
# Silenciar el audio actual y descartar la cola de todas las sesiones.
VOZ="${MASCOTA_DIR:-$HOME/.mascota}/voz"
rm -f "$VOZ"/cola/*.job 2>/dev/null || true
pkill -x afplay 2>/dev/null || true
pkill -x say 2>/dev/null || true
exit 0
