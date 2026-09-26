# Mascota CLI — diseño

Fecha: 2026-09-26

## Objetivo

Una mascota animada en macOS, parecida a la de ChatGPT/Codex desktop, que muestre qué están haciendo
Claude Code y Codex CLI en la terminal: si trabajan, si esperan permiso, si terminaron o si fallaron.
Aparece en cuanto el usuario habla con cualquiera de los dos CLI.

## Componentes

### 1. Hook de estado: `hooks/pet-hook.sh`

- Un solo script que usan los dos CLI. Recibe el nombre del evento como primer argumento
  (`pet-hook.sh claude PreToolUse`) y el JSON del hook por stdin (de ahí toma `session_id` y `cwd`).
- Escribe de forma atómica (`tmp` + `mv`) `~/.mascota/estado/<cli>-<session_id>.json`:
  `{"cli":"claude","session":"…","project":"<basename cwd>","state":"running","ts":<epoch>}`.
- Siempre termina con `exit 0`, sin salida por stdout, y tarda menos de 50 ms. Un error nunca bloquea al CLI.
- Se agrega a los hooks existentes (`~/.claude/settings.json` y `~/.codex/hooks.json`) sin tocar los demás
  (TTS, Orca, keep-awake). Respaldo de los dos archivos antes de editarlos.

| Evento del CLI | Estado |
|---|---|
| `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `SubagentStart` | `running` |
| `PermissionRequest` | `waiting` |
| `Stop` | `done` |
| `StopFailure` | `failed` |
| `SessionEnd` | se borra el archivo |

### 2. App `Mascota.app` (Swift, SwiftUI + AppKit)

- **Ventana flotante:** `NSPanel` sin bordes y transparente, nivel flotante, en todos los escritorios,
  arrastrable. Recuerda su posición (`UserDefaults`). Muestra un globito corto
  («Claude terminó · vps-prod»), que desaparece a los pocos segundos.
- **Barra de menú:** `NSStatusItem` con la mascota en miniatura, animada. Menú: mostrar/ocultar la ventana,
  sesiones activas (CLI · proyecto · estado), mascota de cada CLI, abrir al iniciar sesión, salir.
- **Lectura de estado:** vigila `~/.mascota/estado/` (DispatchSource sobre el directorio y un sondeo de respaldo
  cada 1 s). Descarta los archivos con más de 30 min sin cambios (sesiones colgadas).
- **Agregación:** cuando hay varias sesiones gana la más urgente: `waiting` > `failed` > `running` > `done` > `idle`.
- **Animación visible:**
  - `running` → fila `running` (laptop).
  - `waiting` → fila `waiting` (❓).
  - `failed` → fila `failed`.
  - `done` → fila `waving` una vez; luego `idle`.
- **Visibilidad:** aparece al llegar cualquier evento. Se oculta sola tras 3 minutos sin sesiones en
  `running`/`waiting`. La barra de menú queda siempre.
- **Arranque:** `SMAppService.mainApp` para abrir al iniciar sesión.

### 3. Mascotas

- Mismo formato que Codex v2: carpeta con `pet.json` (`spriteVersionNumber: 2`) y una hoja de sprites de
  1536×2288 (8 columnas × 11 filas, celdas de 192×208).
- `scripts/instalar-mascotas.sh` extrae las hojas incluidas en `ChatGPT.app` (`app.asar`) a
  `~/.mascota/mascotas/<id>/`. Son solo para uso personal en esta Mac y no se suben al repo.
- La app también lee `~/.codex/pets/`, donde queda la mascota propia de Claude que se hará después
  con la skill `hatch-pet`.
- Filas y duraciones, según el contrato de Codex:
  - idle 6
  - running-right 8, running-left 8
  - waving 4
  - jumping 5
  - failed 8
  - waiting 6
  - running 6
  - review 6
- Esta primera versión no usa las filas 9 y 10 (mirar al cursor).

## Construcción

- Swift Package (`swift build`, solo Command Line Tools, sin Xcode). `scripts/empaquetar.sh` arma
  `Mascota.app` (Info.plist con `LSUIElement`, sin ícono en el Dock) y la copia a `~/Applications`.
- Lógica pura (mapeo de eventos, agregación, temporizadores, lectura de `pet.json`) en un target aparte,
  con pruebas unitarias.
- Hook con pruebas en shell: JSON de ejemplo → archivo de estado esperado.

## Fuera de alcance (por ahora)

- Mirar al cursor (filas 9 y 10), sonidos (ya los ponen los hooks existentes), clic para enfocar la terminal.
