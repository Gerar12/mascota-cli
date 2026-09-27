# Mascota CLI

Mascota animada para macOS que muestra qué hacen **Claude Code** y **Codex CLI**: trabajando (laptop), pidiendo permiso (❓), terminó (saluda) o falló (ERROR). Vive en una ventana flotante que se arrastra y en la barra de menú.

## Instalar

```sh
sh scripts/instalar-mascotas.sh    # copia las mascotas de ChatGPT.app a ~/.mascota/mascotas (uso personal)
sh scripts/empaquetar.sh           # compila e instala ~/Applications/Mascota.app y la abre
python3 scripts/instalar-hooks.py  # agrega el hook a ~/.claude/settings.json y ~/.codex/hooks.json (con respaldo)
```

Codex solo ejecuta hooks confiables: la primera vez, abre `codex` y aprueba los hooks nuevos de `pet-hook.sh` (o revísalos con `/hooks`).

Desde el menú de la barra: mostrar/ocultar, sesiones activas, mascota de cada CLI y «Abrir al iniciar sesión».

## Desinstalar

```sh
python3 scripts/instalar-hooks.py --desinstalar
rm -rf ~/Applications/Mascota.app ~/.mascota
```

## Mascota propia

Cualquier mascota con el formato de Codex v2 (`pet.json` + hoja de sprites de 1536×2288, celdas de 192×208) en `~/.codex/pets/<id>/` o `~/.mascota/mascotas/<id>/` aparece en el menú. Se pueden crear con la skill `hatch-pet` de Codex. `python3 scripts/dibujar-clawd.py` dibuja a Clawd (el cangrejito de Claude Code) en pixel art y lo deja en `~/.codex/pets/clawd`.

## Cómo funciona

`hooks/pet-hook.sh` escribe `~/.mascota/estado/<cli>-<sesión>.json` en cada evento; la app lo lee cada 0,5 s y muestra el estado más urgente (permiso > error > trabajando > terminó). El hook anota el pid del proceso `claude`/`codex`: al cerrar una terminal su ícono desaparece, y al cerrar la última se oculta la mascota.

## Desarrollo

- `swift test`: lógica pura en `Sources/MascotaCore`.
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
