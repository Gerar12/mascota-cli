#!/bin/sh
# Uso: pet-hook.sh <claude|codex> [evento], con el JSON del hook por stdin.
# Un fallo de telemetría nunca debe interferir con el CLI.
exec >/dev/null 2>&1
cli=${1:-claude}
case "$cli" in claude|codex) ;; *) exit 0 ;; esac
dir="${MASCOTA_DIR:-$HOME/.mascota}/estado"
entrada=$(cat)
campo() { printf '%s' "$entrada" | plutil -extract "$1" raw -expect string -n -o - -; }
evento=${2:-$(campo hook_event_name)}
sesion=$(campo session_id) || exit 0
sesion=$(printf '%s' "$sesion" | LC_ALL=C tr -cd 'A-Za-z0-9._-')
[ -n "$sesion" ] || exit 0
archivo="$dir/$cli-$sesion.json"
case "$evento" in
  UserPromptSubmit|PreToolUse|PostToolUse|SubagentStart) estado=running ;;
  PermissionRequest) estado=waiting ;;
  Stop) estado=done ;;
  StopFailure) estado=failed ;;
  SessionEnd) rm -f "$archivo"; exit 0 ;;
  *) exit 0 ;;
esac
# Escapa texto para JSON. La entrada lleva un "." de centinela al final (conserva saltos de línea
# finales) que se devuelve y el llamador quita.
json_escapar() {
  LC_ALL=C awk '
  BEGIN { for (i=1; i<32; i++) escape[sprintf("%c",i)]=sprintf("\\u%04x",i) }
  { if (NR>1) printf "\\n"
    for (i=1; i<=length($0); i++) {
      c=substr($0,i,1)
      if (c=="\\") printf "\\\\"
      else if (c=="\"") printf "\\\""
      else if (c in escape) printf "%s", escape[c]
      else printf "%s", c
    }
  }'
}
carpeta=$(campo cwd; printf '.')
carpeta=${carpeta%.}
proyecto=$carpeta
while [ "${proyecto%/}" != "$proyecto" ]; do proyecto=${proyecto%/}; done
proyecto=${proyecto##*/}
proyecto=$(printf '%s.' "${proyecto:-?}" | json_escapar)
proyecto=${proyecto%.}
# Carpeta completa: la app la usa para encontrar la terminal de la sesión en Ghostty.
carpeta=$(printf '%s.' "$carpeta" | json_escapar)
carpeta=${carpeta%.}
# Proceso claude/codex dueño de la sesión (padre o abuelo del hook): la app lo vigila para
# quitar la sesión cuando se cierra la terminal.
# Sesión automática (encargo de otro agente): el menú la oculta; el globo la sigue mostrando.
# Es automática si viene de `codex exec` o `claude -p`, si tiene MASCOTA_SIN_VOZ, o si es un
# ayudante temporal de Codex (sin archivo de conversación).
auto=
[ -n "${MASCOTA_SIN_VOZ:-}" ] && auto=1
[ "$cli" = codex ] && [ -z "$(campo transcript_path)" ] && auto=1
pid=; p=$PPID; n=0
while [ -n "$p" ] && [ "$p" -gt 1 ] && [ $n -lt 2 ]; do
  nombre=$(ps -o comm= -p "$p") || break
  case "${nombre##*/}" in
    claude|codex)
      comando=" $(ps -o command= -p "$p") "
      case "$comando" in *" exec "*|*" -p "*|*" --print "*) auto=1 ;; esac
      # Los hooks de Codex corren en su servicio de fondo (codex app-server), que no muere al
      # cerrar la terminal: ese pid no sirve; la app vigila entonces si queda alguna terminal con Codex.
      case "$comando" in *app-server*) ;; *) pid=$p ;; esac
      break ;;
  esac
  p=$(ps -o ppid= -p "$p" | tr -d ' '); n=$((n+1))
done
mkdir -p "$dir" || exit 0
tmp=$(mktemp "$dir/.$cli-$sesion.XXXXXX") || exit 0
trap 'rm -f "$tmp"' EXIT
printf '{"cli":"%s","session":"%s","project":"%s","state":"%s","ts":%s%s%s%s}\n' \
  "$cli" "$sesion" "$proyecto" "$estado" "$(date +%s)" "${pid:+,\"pid\":$pid}" "${carpeta:+,\"cwd\":\"$carpeta\"}" \
  "${auto:+,\"auto\":true}" > "$tmp" \
  && mv -f "$tmp" "$archivo"
exit 0
