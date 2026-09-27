# Mascota CLI

Mascota animada para macOS que muestra qué hacen **Claude Code** y **Codex CLI**: trabajando (laptop), pidiendo permiso (❓), terminó (saluda) o falló (ERROR). Vive en una ventana flotante que se arrastra y en la barra de menú.

## Instalar

```sh
git clone git@github.com:Gerar12/mascota-cli.git && cd mascota-cli
sh scripts/instalar.sh            # pregunta si quieres voz; o --voz / --sin-voz
```

Hace todo en un paso, y se puede repetir sin problema:
- Revisa macOS 14+, Swift (Command Line Tools) y Pillow.
- Copia las mascotas de ChatGPT.app si la tienes; si no, dibuja a Clawd.
- Instala los hooks de Claude y Codex, y la voz si la pides.
- Conecta la cuota de Claude a su barra de estado, con respaldo.
- Compila la app, la instala en `~/Applications` y la abre.

Codex solo ejecuta hooks aprobados: abre `codex` y elige **Trust all**.

Para desinstalar: `sh scripts/desinstalar.sh` (con `--todo` borra también `~/.mascota` sin preguntar). Nunca toca `~/.codex/pets`.

## Menú

- **Sesiones:** tus terminales de Claude y Codex. Con un clic vas a su terminal: la pestaña exacta en Terminal.app e iTerm2 (por su tty); en Ghostty, por carpeta y título. Los encargos automáticos que lanza otro agente no salen aquí, solo en el globo.
- **No molestar:** 30 min, 1 hora o hasta mañana. Calla la voz, esconde el globo y los avisos, y al terminar todo vuelve solo.
- **Cuota:**
  - Claude: ventana de 5 h y semana. Se lee de su barra de estado; para activarla, antepón `tee "$HOME/.mascota/claude-barra.json" | ` al comando de `statusLine` en `~/.claude/settings.json`.
  - Codex: porcentaje de la semana, leído de sus registros de sesión.
- **Autodiagnóstico:** si Codex trabaja pero sus hooks no avisan (suele pasar tras una actualización o si pide aprobar los hooks otra vez), el menú lo dice arriba.
- **Avisos:** notificación de macOS cuando Claude o Codex piden permiso y no estás en la terminal; al tocarla te lleva a ella.
- **Vida propia:** en reposo te mira, pasea y hace travesuras. Si pasas el cursor encima de lado a lado, la acaricias ❤️, y te saluda cuando vuelves tras 5 minutos sin usar la Mac.

## Voz (opcional)

Mascota puede leer en voz alta cada respuesta de Claude o Codex:

```sh
python3 scripts/instalar-hooks.py --voz
```

- Voces, en orden: **ElevenLabs**, **edge-tts** (gratis: `uv tool install edge-tts`) y **say** (local, sin internet). Desde el menú de la mascota eliges con cuál empezar; si falla, baja a la siguiente.
- ElevenLabs usa la clave de la variable `ELEVENLABS_API_KEY` o de `~/.mascota/voz/elevenlabs.key` (permisos 600; nunca va al repo).
- Desde el menú: leer respuestas sí/no, elegir voz, repetir lo último y callar ahora. En la terminal: `~/.mascota/voz/bin/callar.sh` y `repetir.sh`.
- Los datos viven en `~/.mascota/voz/`: `OFF`, `proveedor`, la cola, los últimos audios y `voz.log`.

## Energía

Desde el menú de la mascota:
- **Despierta mientras trabajan** (activado por defecto): con el cargador conectado, la Mac no entra en reposo mientras Claude o Codex trabajan o piden permiso, ni en los 15 minutos siguientes.
- **Despierta siempre**: con el cargador conectado, impide el reposo hasta que lo apagues.

Las dos opciones solo funcionan con el cargador conectado: con batería, macOS deja que la Mac entre en reposo con normalidad.

En los dos casos la pantalla sí se apaga. Cerrar la tapa duerme la Mac igual, salvo con un monitor externo. La app usa las aserciones de energía de macOS, las mismas que `caffeinate`, y las suelta al cerrarse.

## Mascota propia

Cualquier mascota con el formato de Codex v2 (`pet.json` + hoja de sprites de 1536×2288, celdas de 192×208) en `~/.codex/pets/<id>/` o `~/.mascota/mascotas/<id>/` aparece en el menú. Se pueden crear con la skill `hatch-pet` de Codex. `python3 scripts/dibujar-clawd.py` dibuja a Clawd (el cangrejito de Claude Code) en pixel art y lo deja en `~/.codex/pets/clawd`.

## Cómo funciona

`hooks/pet-hook.sh` escribe `~/.mascota/estado/<cli>-<sesión>.json` en cada evento; la app lo lee cada 0,5 s y muestra el estado más urgente (permiso > error > trabajando > terminó). El hook anota el pid del proceso `claude`/`codex`: al cerrar una terminal su ícono desaparece, y al cerrar la última se oculta la mascota.

## Desarrollo

- `swift test`: lógica pura en `Sources/MascotaCore` (con pruebas).
- La app (`Sources/Mascota`): `AppDelegate` solo conecta las piezas:
  - `SondeoSesiones`: sesiones y autodiagnóstico.
  - `ControlEnergia`, `ControlAvisos` (con No molestar) y `VidaPropia`.
  - `PanelMascota`, `MenuMascota` y `EnfocarTerminal`.
- `sh pruebas/*.sh`: pruebas del hook y los instaladores.
- Con solo Command Line Tools, swift-testing a veces no encuentra sus macros en compilaciones incrementales: `Package.swift` le pasa `-plugin-path` explícito. Tras `empaquetar.sh` (release), `swift test` puede necesitar `rm -rf .build`.
- El disco de la Mac no distingue mayúsculas: `tests/` y `Tests/` son la misma carpeta. Por eso las pruebas de shell viven en `pruebas/`.

## Requisitos

- macOS 14 o superior y las Command Line Tools de Xcode (`xcode-select --install`).
- Claude Code y/o Codex CLI.
- Opcional: ChatGPT.app, para usar sus mascotas, y Claude.app, para el logo de Claude en el globo.

## Licencia y avisos

Código bajo licencia MIT (ver `LICENSE`).

Proyecto personal, sin relación con Anthropic ni con OpenAI. Claude, Claude Code y Clawd son de Anthropic; ChatGPT, Codex y sus mascotas son de OpenAI. Este repositorio **no incluye** sus imágenes ni sus logos: `instalar-mascotas.sh` los copia de las apps instaladas en tu Mac, para uso personal. `dibujar-clawd.py` es un dibujo de fan en pixel art.
