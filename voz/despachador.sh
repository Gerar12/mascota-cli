#!/bin/sh
# Un solo consumidor FIFO para ambas CLI; no depende del directorio de trabajo.
VOZ="${MASCOTA_DIR:-$HOME/.mascota}/voz"
COLA="$VOZ/cola"
LOCK="$VOZ/despachador.lock"
LOG="$VOZ/voz.log"
export LC_ALL=C
umask 077
mkdir -p "$COLA" || exit 0

wait_quiet() {
    waited=0
    while pgrep -x afplay >/dev/null 2>&1 || pgrep -x say >/dev/null 2>&1; do
        [ "$waited" -ge 180 ] && break
        sleep 1
        waited=$((waited + 1))
    done
}

play_file() {
    [ -f "$1" ] || return 0
    wait_quiet
    [ -f "$VOZ/OFF" ] || afplay -v 0.5 "$1" >>"$LOG" 2>&1
}

audio_valido() {
    [ -s "$1" ] && file -b "$1" | grep -qiE 'audio|mpeg'
}

speak() {
    [ -n "$PAYLOAD" ] || return 0
    # Los trabajos externos tampoco pueden usar SID para salir de $VOZ.
    SID=$(printf '%s' "$SID" | tr -cd 'A-Za-z0-9_.-' | cut -c 1-120)
    case "$SID" in ''|.|..) SID=global ;; esac
    CACHE="$VOZ/ultimo-$SID.mp3"
    rm -f "$CACHE"
    PROVEEDOR=$(cat "$VOZ/proveedor" 2>/dev/null)
    case "$PROVEEDOR" in edge|local) ;; *) PROVEEDOR=eleven ;; esac
    if [ "$PROVEEDOR" = eleven ]; then
        KEY="${ELEVENLABS_API_KEY:-}"
        [ -n "$KEY" ] || KEY=$(cat "$VOZ/elevenlabs.key" 2>/dev/null)
        if [ -n "$KEY" ]; then
            printf '%s' "$PAYLOAD" | python3 -c '
import json, sys
json.dump({"text": sys.stdin.read(), "model_id": "eleven_multilingual_v2",
           "voice_settings": {"stability": 0.5, "similarity_boost": 0.8,
                              "style": 0.2, "use_speaker_boost": True}}, sys.stdout)
' > "$TMP/payload.json"
            CODE=$(curl -s -o "$TMP/eleven.mp3" -w '%{http_code}' -X POST \
                "https://api.elevenlabs.io/v1/text-to-speech/${ELEVEN_VOICE:-8tm9IYjg8ybDoxe8w6Rk}" \
                -H "xi-api-key: $KEY" -H 'Content-Type: application/json' \
                -H 'Accept: audio/mpeg' --data "@$TMP/payload.json" \
                --connect-timeout 10 --max-time 60) || CODE=000
            unset KEY
            if [ "$CODE" = 200 ] && audio_valido "$TMP/eleven.mp3"; then
                printf 'ELEVEN OK (%s)\n' "${ELEVEN_VOICE:-8tm9IYjg8ybDoxe8w6Rk}" >> "$LOG"
                mv "$TMP/eleven.mp3" "$CACHE"
                play_file "$CACHE"
                return 0
            fi
            # Una sola línea, cuerpo incluido: ControlVoz busca quota_exceeded aquí.
            BODY=$(tr '\r\n' '  ' < "$TMP/eleven.mp3" 2>/dev/null)
            printf 'ELEVEN FAIL (%s): %s\n' "$CODE" "$BODY" >> "$LOG"
            rm -f "$TMP/eleven.mp3"
        fi
    fi
    if [ "$PROVEEDOR" != local ]; then
        EDGE="$HOME/.local/bin/edge-tts"
        [ -x "$EDGE" ] || EDGE=$(command -v edge-tts 2>/dev/null)
        if [ -n "$EDGE" ] && "$EDGE" -v "${EDGE_VOICE:-es-MX-DaliaNeural}" \
            -t "$PAYLOAD" --write-media "$TMP/edge.mp3" >>"$LOG" 2>&1 \
            && audio_valido "$TMP/edge.mp3"; then
            printf 'EDGE OK (%s)\n' "${EDGE_VOICE:-es-MX-DaliaNeural}" >> "$LOG"
            mv "$TMP/edge.mp3" "$CACHE"
            play_file "$CACHE"
            return 0
        fi
        rm -f "$TMP/edge.mp3"
    fi
    printf 'LOCAL (%s)\n' "${SAY_VOICE:-Mónica}" >> "$LOG"
    wait_quiet
    [ -f "$VOZ/OFF" ] || printf '%s\n' "$PAYLOAD" | say -v "${SAY_VOICE:-Mónica}" -r 210 >>"$LOG" 2>&1
}

while :; do
    mkdir "$LOCK" 2>/dev/null || exit 0
    TMP=''
    trap 'rm -rf "$TMP"; rmdir "$LOCK" 2>/dev/null || true' 0
    trap 'exit 0' HUP INT TERM
    TMP=$(mktemp -d "$VOZ/.audio.XXXXXX") || exit 0
    while :; do
        # Glob en orden léxico: solo .job publicados con rename, jamás temporales.
        set -- "$COLA"/*.job
        [ -f "$1" ] || break
        JOB=$1
        TYPE=$(sed -n '1p' "$JOB")
        SID=$(sed -n '2p' "$JOB")
        PAYLOAD=$(sed -n '3,$p' "$JOB")
        rm -f "$JOB"
        [ -f "$VOZ/OFF" ] && continue
        case "$TYPE" in
            SPEAK) speak ;;
            PLAY) play_file "$PAYLOAD" ;;
        esac
    done
    rm -rf "$TMP"
    rmdir "$LOCK" 2>/dev/null || true
    trap - 0 HUP INT TERM
    # Cerrar la carrera con un productor que publicó justo antes de soltar el lock.
    set -- "$COLA"/*.job
    [ -f "$1" ] || exit 0
done
