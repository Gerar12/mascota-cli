# Mascota CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mascota animada flotante + barra de menú en macOS que refleja el estado de Claude Code y Codex CLI.

**Architecture:** Un hook de shell común escribe un JSON por sesión en `~/.mascota/estado/`. Una app AppKit (Swift Package, sin Xcode) sondea ese directorio cada 0,5 s, agrega el estado más urgente y anima una hoja de sprites en formato Codex v2 dentro de un `NSPanel` flotante y un `NSStatusItem`. La lógica pura vive en `MascotaCore` con pruebas (swift-testing).

**Tech Stack:** Swift 6.4 (Command Line Tools), AppKit, swift-testing, `/bin/sh` + `plutil` para el hook, `python3` para editar JSON de configuración, `npx @electron/asar` para extraer sprites.

**Spec:** `docs/superpowers/specs/2026-09-26-mascota-cli-design.md`

## Global Constraints

- macOS 14+ (`platforms: [.macOS(.v14)]`), solo Command Line Tools: nada que requiera Xcode.
- El hook: nunca imprime en stdout, siempre `exit 0`, < 50 ms, escritura atómica (`tmp` + `mv`).
- Directorio de datos: `~/.mascota/` (`estado/`, `mascotas/`, `pet-hook.sh`); sobreescribible con `MASCOTA_DIR` en pruebas.
- Hooks existentes del usuario (TTS, Orca, keep-awake, gmail) no se tocan; respaldo con fecha antes de editar `~/.claude/settings.json` y `~/.codex/hooks.json`.
- Prioridad: `waiting` > `failed` > `running` > `done`. Caducidad de sesión: 30 min. `failed` con más de 60 s cuenta como `done`. Ocultar tras 3 min sin `running`/`waiting`.
- Celda 192×208; filas: idle 0, waving 3, jumping 4, failed 5, waiting 6, running 7, review 8.
- Sprites de ChatGPT.app solo en `~/.mascota/mascotas/` (uso personal), nunca en el repo.
- Textos de la UI en español.

## Desviación del spec

- Sin DispatchSource: basta el sondeo de 0,5 s (pocos archivos, coste despreciable). YAGNI.

## Reparto

- **Claude:** Tareas 1–4 y 8–9 (`Package.swift`, `Sources/`, `Tests/`, `scripts/empaquetar.sh`).
- **Codex (en paralelo):** Tareas 5–7 (`hooks/`, `scripts/instalar-*.{sh,py}`, `tests/shell/`). Sin archivos compartidos.

## Estructura de archivos

```
Package.swift
Sources/MascotaCore/Sesion.swift          modelo + lectura del directorio de estado
Sources/MascotaCore/Agregador.swift       prioridad, caducidad, visibilidad
Sources/MascotaCore/Animaciones.swift     filas, duraciones, cuadro por tiempo, textos del globo
Sources/MascotaCore/CatalogoMascotas.swift lectura de pet.json
Sources/Mascota/main.swift                arranque NSApplication
Sources/Mascota/AppDelegate.swift         bucle de estado/animación, preferencias
Sources/Mascota/HojaSprites.swift         recorte de celdas (CGImage) con caché
Sources/Mascota/PanelMascota.swift        NSPanel flotante + globo
Sources/Mascota/MenuBarra.swift           NSStatusItem + menú
Tests/MascotaCoreTests/*.swift
hooks/pet-hook.sh
scripts/instalar-hooks.py
scripts/instalar-mascotas.sh
scripts/empaquetar.sh
tests/shell/test-pet-hook.sh
tests/shell/test-instalar-hooks.sh
```

---

### Task 1: Paquete + modelo `Sesion` y lector del directorio

**Files:**
- Create: `Package.swift`, `Sources/MascotaCore/Sesion.swift`, `Sources/Mascota/main.swift` (placeholder mínimo), `Tests/MascotaCoreTests/SesionTests.swift`

**Interfaces:**
- Produces: `enum EstadoAgente: String, Codable { running, waiting, done, failed }`; `struct Sesion { cli, session, project: String; state: EstadoAgente; ts: TimeInterval; var nombreCLI: String }`; `enum LectorEstado { static func leer(directorio: URL) -> [Sesion] }`

- [ ] **Step 1: Package.swift**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mascota",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MascotaCore"),
        .executableTarget(name: "Mascota", dependencies: ["MascotaCore"]),
        .testTarget(name: "MascotaCoreTests", dependencies: ["MascotaCore"]),
    ]
)
```

`Sources/Mascota/main.swift` temporal: `import MascotaCore` + `print("mascota")`.

- [ ] **Step 2: Prueba que falla**

```swift
import Foundation
import Testing
@testable import MascotaCore

@Test func leeSesionesValidasEIgnoraBasura() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try #"{"cli":"claude","session":"a1","project":"vps-prod","state":"running","ts":1790000000}"#
        .write(to: dir.appendingPathComponent("claude-a1.json"), atomically: true, encoding: .utf8)
    try "no es json".write(to: dir.appendingPathComponent("roto.json"), atomically: true, encoding: .utf8)
    try "{}".write(to: dir.appendingPathComponent(".claude-a1.123"), atomically: true, encoding: .utf8)

    let sesiones = LectorEstado.leer(directorio: dir)

    #expect(sesiones == [Sesion(cli: "claude", session: "a1", project: "vps-prod", state: .running, ts: 1_790_000_000)])
    #expect(sesiones[0].nombreCLI == "Claude")
}

@Test func directorioInexistenteDevuelveVacio() {
    #expect(LectorEstado.leer(directorio: URL(fileURLWithPath: "/no/existe")) == [])
}
```

- [ ] **Step 3:** `swift test` → FAIL (no compila: `Sesion` no existe).

- [ ] **Step 4: Implementación**

```swift
import Foundation

public enum EstadoAgente: String, Codable, Sendable {
    case running, waiting, done, failed
}

public struct Sesion: Codable, Equatable, Sendable {
    public let cli: String
    public let session: String
    public let project: String
    public let state: EstadoAgente
    public let ts: TimeInterval

    public init(cli: String, session: String, project: String, state: EstadoAgente, ts: TimeInterval) {
        self.cli = cli; self.session = session; self.project = project; self.state = state; self.ts = ts
    }

    public var nombreCLI: String { cli == "codex" ? "Codex" : "Claude" }
}

public enum LectorEstado {
    public static func leer(directorio: URL) -> [Sesion] {
        let archivos = (try? FileManager.default.contentsOfDirectory(
            at: directorio, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return archivos
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let datos = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(Sesion.self, from: datos)
            }
    }
}
```

- [ ] **Step 5:** `swift test` → PASS.
- [ ] **Step 6:** `git add -A && git commit -m "Modelo de sesión y lector del directorio de estado"`

### Task 2: Agregador (prioridad, caducidad, visibilidad)

**Files:**
- Create: `Sources/MascotaCore/Agregador.swift`, `Tests/MascotaCoreTests/AgregadorTests.swift`

**Interfaces:**
- Consumes: `Sesion`, `EstadoAgente`
- Produces: `enum Agregador { static func principal(_ s: [Sesion], ahora: Date) -> Sesion?; static func estadoEfectivo(_ s: Sesion, ahora: Date) -> EstadoAgente; static func vigentes(_ s: [Sesion], ahora: Date) -> [Sesion]; static func debeMostrarse(_ s: [Sesion], ahora: Date) -> Bool }`

- [ ] **Step 1: Pruebas que fallan**

```swift
import Foundation
import Testing
@testable import MascotaCore

private let t0: TimeInterval = 1_790_000_000
private func s(_ id: String, _ e: EstadoAgente, hace: TimeInterval, cli: String = "claude") -> Sesion {
    Sesion(cli: cli, session: id, project: "p", state: e, ts: t0 - hace)
}
private let ahora = Date(timeIntervalSince1970: t0)

@Test func ganaElMasUrgente() {
    let lista = [s("a", .running, hace: 1), s("b", .waiting, hace: 50), s("c", .done, hace: 0)]
    #expect(Agregador.principal(lista, ahora: ahora)?.session == "b")
}

@Test func empateGanaElMasReciente() {
    let lista = [s("a", .running, hace: 10), s("b", .running, hace: 2)]
    #expect(Agregador.principal(lista, ahora: ahora)?.session == "b")
}

@Test func sesionesDeMasDe30MinutosSeIgnoran() {
    #expect(Agregador.principal([s("a", .waiting, hace: 31 * 60)], ahora: ahora) == nil)
}

@Test func failedViejoCuentaComoDone() {
    let viejo = s("a", .failed, hace: 61)
    #expect(Agregador.estadoEfectivo(viejo, ahora: ahora) == .done)
    #expect(Agregador.estadoEfectivo(s("b", .failed, hace: 5), ahora: ahora) == .failed)
    let lista = [viejo, s("c", .running, hace: 100)]
    #expect(Agregador.principal(lista, ahora: ahora)?.session == "c")
}

@Test func visibilidad() {
    #expect(Agregador.debeMostrarse([], ahora: ahora) == false)
    #expect(Agregador.debeMostrarse([s("a", .running, hace: 600)], ahora: ahora))
    #expect(Agregador.debeMostrarse([s("a", .done, hace: 60)], ahora: ahora))
    #expect(Agregador.debeMostrarse([s("a", .done, hace: 181)], ahora: ahora) == false)
}
```

- [ ] **Step 2:** `swift test` → FAIL (`Agregador` no existe).

- [ ] **Step 3: Implementación**

```swift
import Foundation

public enum Agregador {
    public static let caducidad: TimeInterval = 30 * 60
    public static let vidaDeFailed: TimeInterval = 60
    public static let ocultarTras: TimeInterval = 3 * 60

    public static func vigentes(_ sesiones: [Sesion], ahora: Date) -> [Sesion] {
        sesiones.filter { ahora.timeIntervalSince1970 - $0.ts < caducidad }
    }

    public static func estadoEfectivo(_ s: Sesion, ahora: Date) -> EstadoAgente {
        if s.state == .failed, ahora.timeIntervalSince1970 - s.ts > vidaDeFailed { return .done }
        return s.state
    }

    static func prioridad(_ e: EstadoAgente) -> Int {
        switch e {
        case .waiting: 4
        case .failed: 3
        case .running: 2
        case .done: 1
        }
    }

    public static func principal(_ sesiones: [Sesion], ahora: Date) -> Sesion? {
        vigentes(sesiones, ahora: ahora).max {
            (prioridad(estadoEfectivo($0, ahora: ahora)), $0.ts) < (prioridad(estadoEfectivo($1, ahora: ahora)), $1.ts)
        }
    }

    public static func debeMostrarse(_ sesiones: [Sesion], ahora: Date) -> Bool {
        let v = vigentes(sesiones, ahora: ahora)
        if v.contains(where: { $0.state == .running || $0.state == .waiting }) { return true }
        guard let ultima = v.map(\.ts).max() else { return false }
        return ahora.timeIntervalSince1970 - ultima < ocultarTras
    }
}
```

- [ ] **Step 4:** `swift test` → PASS.
- [ ] **Step 5:** `git commit -am "Agregador de estado"` (con `git add` de los archivos nuevos).

### Task 3: Animaciones y textos del globo

**Files:**
- Create: `Sources/MascotaCore/Animaciones.swift`, `Tests/MascotaCoreTests/AnimacionesTests.swift`

**Interfaces:**
- Consumes: `EstadoAgente`, `Sesion`
- Produces: `struct Animacion { fila: Int; duraciones: [TimeInterval]; var total: TimeInterval }`; `enum Animaciones { static let idle, waving, jumping, failed, waiting, running, review: Animacion; static func para(estado: EstadoAgente?, desdeCambio: TimeInterval) -> Animacion; static func cuadro(_ a: Animacion, tiempo: TimeInterval) -> Int }`; `enum Textos { static func globo(_ s: Sesion, estado: EstadoAgente) -> String }`

- [ ] **Step 1: Pruebas que fallan**

```swift
import Testing
@testable import MascotaCore

@Test func estadoAFila() {
    #expect(Animaciones.para(estado: .running, desdeCambio: 0).fila == 7)
    #expect(Animaciones.para(estado: .waiting, desdeCambio: 0).fila == 6)
    #expect(Animaciones.para(estado: .failed, desdeCambio: 0).fila == 5)
    #expect(Animaciones.para(estado: nil, desdeCambio: 0).fila == 0)
}

@Test func doneSaludaDosVecesYLuegoIdle() {
    let w = Animaciones.waving.total
    #expect(Animaciones.para(estado: .done, desdeCambio: w * 2 - 0.01).fila == 3)
    #expect(Animaciones.para(estado: .done, desdeCambio: w * 2 + 0.01).fila == 0)
}

@Test func cuadroSegunTiempo() {
    let idle = Animaciones.idle  // 0.28, 0.11, 0.11, 0.14, 0.14, 0.32
    #expect(Animaciones.cuadro(idle, tiempo: 0) == 0)
    #expect(Animaciones.cuadro(idle, tiempo: 0.30) == 1)
    #expect(Animaciones.cuadro(idle, tiempo: 1.0) == 5)
    #expect(Animaciones.cuadro(idle, tiempo: idle.total + 0.01) == 0)
}

@Test func textoDelGlobo() {
    let s = Sesion(cli: "codex", session: "x", project: "vps-prod", state: .done, ts: 0)
    #expect(Textos.globo(s, estado: .done) == "Codex terminó · vps-prod")
    #expect(Textos.globo(s, estado: .waiting) == "Codex necesita permiso · vps-prod")
}
```

- [ ] **Step 2:** `swift test` → FAIL.

- [ ] **Step 3: Implementación**

```swift
import Foundation

public struct Animacion: Equatable, Sendable {
    public let fila: Int
    public let duraciones: [TimeInterval]
    public var total: TimeInterval { duraciones.reduce(0, +) }
}

public enum Animaciones {
    private static func fila(_ n: Int, _ cuadros: Int, cada: TimeInterval, ultimo: TimeInterval) -> Animacion {
        Animacion(fila: n, duraciones: Array(repeating: cada, count: cuadros - 1) + [ultimo])
    }

    public static let idle = Animacion(fila: 0, duraciones: [0.28, 0.11, 0.11, 0.14, 0.14, 0.32])
    public static let waving = fila(3, 4, cada: 0.14, ultimo: 0.28)
    public static let jumping = fila(4, 5, cada: 0.14, ultimo: 0.28)
    public static let failed = fila(5, 8, cada: 0.14, ultimo: 0.24)
    public static let waiting = fila(6, 6, cada: 0.15, ultimo: 0.26)
    public static let running = fila(7, 6, cada: 0.12, ultimo: 0.22)
    public static let review = fila(8, 6, cada: 0.15, ultimo: 0.28)

    public static func para(estado: EstadoAgente?, desdeCambio: TimeInterval) -> Animacion {
        switch estado {
        case .running: running
        case .waiting: waiting
        case .failed: failed
        case .done: desdeCambio < waving.total * 2 ? waving : idle
        case nil: idle
        }
    }

    public static func cuadro(_ a: Animacion, tiempo: TimeInterval) -> Int {
        let t = tiempo.truncatingRemainder(dividingBy: a.total)
        var acumulado: TimeInterval = 0
        for (i, d) in a.duraciones.enumerated() {
            acumulado += d
            if t < acumulado { return i }
        }
        return a.duraciones.count - 1
    }
}

public enum Textos {
    public static func globo(_ s: Sesion, estado: EstadoAgente) -> String {
        let verbo = switch estado {
        case .running: "trabajando"
        case .waiting: "necesita permiso"
        case .done: "terminó"
        case .failed: "falló"
        }
        return "\(s.nombreCLI) \(verbo) · \(s.project)"
    }
}
```

- [ ] **Step 4:** `swift test` → PASS.
- [ ] **Step 5:** commit "Animaciones y textos del globo".

### Task 4: Catálogo de mascotas (`pet.json`)

**Files:**
- Create: `Sources/MascotaCore/CatalogoMascotas.swift`, `Tests/MascotaCoreTests/CatalogoMascotasTests.swift`

**Interfaces:**
- Produces: `struct MascotaDef { id: String; nombre: String; hoja: URL }`; `enum CatalogoMascotas { static func cargar(directorios: [URL]) -> [MascotaDef] }` (ordenadas por nombre, primer id gana).

- [ ] **Step 1: Pruebas que fallan**

```swift
import Foundation
import Testing
@testable import MascotaCore

private func crearMascota(_ raiz: URL, _ carpeta: String, id: String, nombre: String, conHoja: Bool = true) throws {
    let d = raiz.appendingPathComponent(carpeta)
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    let json = #"{"id":"\#(id)","displayName":"\#(nombre)","spriteVersionNumber":2,"spritesheetPath":"spritesheet.webp"}"#
    try json.write(to: d.appendingPathComponent("pet.json"), atomically: true, encoding: .utf8)
    if conHoja { try Data([0]).write(to: d.appendingPathComponent("spritesheet.webp")) }
}

@Test func cargaMascotasDeVariosDirectorios() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let a = tmp.appendingPathComponent("a"), b = tmp.appendingPathComponent("b")
    try crearMascota(a, "null-signal", id: "null-signal", nombre: "Null Signal")
    try crearMascota(a, "rota", id: "rota", nombre: "Rota", conHoja: false)
    try crearMascota(b, "otra", id: "null-signal", nombre: "Duplicada")
    try crearMascota(b, "cangrejo", id: "cangrejo", nombre: "Cangrejo")

    let m = CatalogoMascotas.cargar(directorios: [a, b, URL(fileURLWithPath: "/no/existe")])

    #expect(m.map(\.id) == ["cangrejo", "null-signal"])
    #expect(m[1].nombre == "Null Signal")
    #expect(m[1].hoja.lastPathComponent == "spritesheet.webp")
}
```

- [ ] **Step 2:** `swift test` → FAIL.

- [ ] **Step 3: Implementación**

```swift
import Foundation

public struct MascotaDef: Equatable, Sendable {
    public let id: String
    public let nombre: String
    public let hoja: URL
}

public enum CatalogoMascotas {
    private struct Manifiesto: Decodable {
        let id: String
        let displayName: String
        let spritesheetPath: String
    }

    public static func cargar(directorios: [URL]) -> [MascotaDef] {
        var vistos = Set<String>()
        var resultado: [MascotaDef] = []
        let fm = FileManager.default
        for dir in directorios {
            let carpetas = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for carpeta in carpetas {
                guard let datos = try? Data(contentsOf: carpeta.appendingPathComponent("pet.json")),
                      let m = try? JSONDecoder().decode(Manifiesto.self, from: datos) else { continue }
                let hoja = carpeta.appendingPathComponent(m.spritesheetPath)
                guard fm.fileExists(atPath: hoja.path), vistos.insert(m.id).inserted else { continue }
                resultado.append(MascotaDef(id: m.id, nombre: m.displayName, hoja: hoja))
            }
        }
        return resultado.sorted { $0.nombre < $1.nombre }
    }
}
```

- [ ] **Step 4:** `swift test` → PASS.
- [ ] **Step 5:** commit "Catálogo de mascotas".

### Task 5 (Codex): Hook `pet-hook.sh` + pruebas

**Files:**
- Create: `hooks/pet-hook.sh` (ejecutable), `tests/shell/test-pet-hook.sh` (ejecutable)

**Interfaces:**
- Produces: `pet-hook.sh <claude|codex>` leyendo el JSON del hook por stdin (`hook_event_name`, `session_id`, `cwd`); escribe `$MASCOTA_DIR/estado/<cli>-<session>.json` con el formato que lee `Sesion` (Task 1): `{"cli","session","project","state","ts"}`.

- [ ] **Step 1: Prueba que falla** (`tests/shell/test-pet-hook.sh`)

```sh
#!/bin/sh
set -u
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
HOOK="$RAIZ/hooks/pet-hook.sh"
export MASCOTA_DIR=$(mktemp -d)
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
```

- [ ] **Step 2:** `sh tests/shell/test-pet-hook.sh` → FAIL (no existe el hook).

- [ ] **Step 3: Implementación** (`hooks/pet-hook.sh`)

```sh
#!/bin/sh
# Hook de Mascota CLI para Claude Code y Codex. Uso: pet-hook.sh <claude|codex>, JSON del hook por stdin.
# Nunca imprime nada y siempre sale con 0: no debe molestar al CLI.
cli=$(printf '%s' "${1:-claude}" | tr -cd 'a-z')
dir="${MASCOTA_DIR:-$HOME/.mascota}/estado"
entrada=$(cat)
campo() { printf '%s' "$entrada" | plutil -extract "$1" raw -o - - 2>/dev/null; }

evento=$(campo hook_event_name)
sesion=$(campo session_id | tr -cd 'A-Za-z0-9._-')
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

proyecto=$(basename "$(campo cwd)" 2>/dev/null | tr -d '"\\')
mkdir -p "$dir" 2>/dev/null
tmp="$dir/.$cli-$sesion.$$"
printf '{"cli":"%s","session":"%s","project":"%s","state":"%s","ts":%s}\n' \
  "$cli" "$sesion" "${proyecto:-?}" "$estado" "$(date +%s)" > "$tmp" 2>/dev/null \
  && mv -f "$tmp" "$archivo" 2>/dev/null
rm -f "$tmp" 2>/dev/null
exit 0
```

- [ ] **Step 4:** `chmod +x hooks/pet-hook.sh tests/shell/test-pet-hook.sh && sh tests/shell/test-pet-hook.sh` → `OK pet-hook`. Medir: `time (printf '{"hook_event_name":"Stop","session_id":"z","cwd":"/a"}' | MASCOTA_DIR=$(mktemp -d) hooks/pet-hook.sh claude)` < 50 ms.
- [ ] **Step 5:** commit "Hook de estado para Claude y Codex".

### Task 6 (Codex): Instalador de hooks

**Files:**
- Create: `scripts/instalar-hooks.py`, `tests/shell/test-instalar-hooks.sh`

**Interfaces:**
- Consumes: `hooks/pet-hook.sh` (Task 5).
- Produces: `python3 scripts/instalar-hooks.py [--claude RUTA] [--codex RUTA] [--destino-hook RUTA]` (por defecto `~/.claude/settings.json`, `~/.codex/hooks.json`, `~/.mascota/pet-hook.sh`). Copia el hook al destino (ejecutable), respalda cada JSON como `<archivo>.bak-mascota-<AAAAMMDD-HHMMSS>`, agrega un grupo por evento si su comando no está ya. Idempotente. `--desinstalar` quita solo esos grupos.

- [ ] **Step 1: Prueba que falla** (`tests/shell/test-instalar-hooks.sh`)

```sh
#!/bin/sh
set -eu
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d)
cat > "$T/settings.json" <<'EOF'
{"model":"x","hooks":{"Stop":[{"hooks":[{"type":"command","command":"/tts.sh"}]}]}}
EOF
cat > "$T/hooks.json" <<'EOF'
{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/codex-tts.sh"}]}]}}
EOF
correr() { python3 "$RAIZ/scripts/instalar-hooks.py" --claude "$T/settings.json" --codex "$T/hooks.json" --destino-hook "$T/bin/pet-hook.sh" "$@"; }
correr; correr   # dos veces: idempotente
python3 - "$T" <<'EOF'
import json, sys, os
t = sys.argv[1]
c = json.load(open(f"{t}/settings.json")); x = json.load(open(f"{t}/hooks.json"))
assert c["model"] == "x"
assert c["hooks"]["Stop"][0]["hooks"][0]["command"] == "/tts.sh"
def cmds(cfg, ev): return [h["command"] for g in cfg["hooks"].get(ev, []) for h in g["hooks"]]
for ev in ["UserPromptSubmit","PreToolUse","PostToolUse","SubagentStart","PermissionRequest","Stop","StopFailure","SessionEnd"]:
    assert sum("pet-hook.sh" in k and k.endswith(" claude") for k in cmds(c, ev)) == 1, ev
for ev in ["UserPromptSubmit","PreToolUse","PostToolUse","SubagentStart","PermissionRequest","Stop","SessionEnd"]:
    assert sum("pet-hook.sh" in k and k.endswith(" codex") for k in cmds(x, ev)) == 1, ev
assert os.access(f"{t}/bin/pet-hook.sh", os.X_OK)
assert any(n.startswith("settings.json.bak-mascota-") for n in os.listdir(t))
EOF
correr --desinstalar
python3 - "$T" <<'EOF'
import json, sys
t = sys.argv[1]
for f in ["settings.json", "hooks.json"]:
    assert "pet-hook.sh" not in open(f"{t}/{f}").read(), f
assert json.load(open(f"{t}/settings.json"))["hooks"]["Stop"][0]["hooks"][0]["command"] == "/tts.sh"
EOF
rm -rf "$T"; echo "OK instalar-hooks"
```

- [ ] **Step 2:** `sh tests/shell/test-instalar-hooks.sh` → FAIL.

- [ ] **Step 3: Implementación** (`scripts/instalar-hooks.py`)

```python
#!/usr/bin/env python3
"""Agrega (o quita) el hook de Mascota CLI en Claude Code y Codex sin tocar los demás hooks."""
import argparse, json, os, shutil, stat, time
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
EVENTOS = {
    "claude": ["UserPromptSubmit", "PreToolUse", "PostToolUse", "SubagentStart",
               "PermissionRequest", "Stop", "StopFailure", "SessionEnd"],
    "codex": ["UserPromptSubmit", "PreToolUse", "PostToolUse", "SubagentStart",
              "PermissionRequest", "Stop", "SessionEnd"],
}
CON_MATCHER = {"PreToolUse", "PostToolUse", "PermissionRequest"}


def es_nuestro(grupo):
    return any("pet-hook.sh" in h.get("command", "") for h in grupo.get("hooks", []))


def actualizar(ruta, cli, destino, quitar):
    ruta = Path(ruta).expanduser()
    cfg = json.loads(ruta.read_text()) if ruta.exists() else {}
    if ruta.exists():
        shutil.copy2(ruta, f"{ruta}.bak-mascota-{time.strftime('%Y%m%d-%H%M%S')}")
    hooks = cfg.setdefault("hooks", {})
    for evento in EVENTOS[cli]:
        grupos = [g for g in hooks.get(evento, []) if not es_nuestro(g)]
        if not quitar:
            h = {"type": "command", "command": f"/bin/sh '{destino}' {cli}", "timeout": 5}
            if cli == "claude":
                h["async"] = True
            grupo = {"hooks": [h]}
            if evento in CON_MATCHER:
                grupo["matcher"] = "*"
            grupos.append(grupo)
        if grupos:
            hooks[evento] = grupos
        else:
            hooks.pop(evento, None)
    ruta.parent.mkdir(parents=True, exist_ok=True)
    ruta.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--claude", default="~/.claude/settings.json")
    p.add_argument("--codex", default="~/.codex/hooks.json")
    p.add_argument("--destino-hook", default="~/.mascota/pet-hook.sh")
    p.add_argument("--desinstalar", action="store_true")
    a = p.parse_args()
    destino = Path(a.destino_hook).expanduser()
    if not a.desinstalar:
        destino.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(RAIZ / "hooks" / "pet-hook.sh", destino)
        destino.chmod(destino.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    actualizar(a.claude, "claude", destino, a.desinstalar)
    actualizar(a.codex, "codex", destino, a.desinstalar)
    print("Hooks de Mascota " + ("quitados" if a.desinstalar else "instalados"))


if __name__ == "__main__":
    main()
```

- [ ] **Step 4:** `sh tests/shell/test-instalar-hooks.sh` → `OK instalar-hooks`.
- [ ] **Step 5:** commit "Instalador de hooks". **No** correrlo contra los archivos reales: eso lo hace Claude en la Tarea 9.

### Task 7 (Codex): Instalador de mascotas desde ChatGPT.app

**Files:**
- Create: `scripts/instalar-mascotas.sh` (ejecutable)

**Interfaces:**
- Produces: `~/.mascota/mascotas/<id>/{pet.json,spritesheet.webp}` para cada `webview/assets/<id>-spritesheet-v<N>-<hash>.webp` de `/Applications/ChatGPT.app/Contents/Resources/app.asar`. `pet.json`: `{"id","displayName","description":"Mascota incluida en ChatGPT.","spriteVersionNumber":2|1,"spritesheetPath":"spritesheet.webp"}` (2 si la altura es 2288, 1 si es 1872; se omite con aviso si no es ninguna). `displayName`: id con guiones → espacios y Mayúscula Inicial (`null-signal` → `Null Signal`). Destino sobreescribible con `MASCOTA_DIR`.

- [ ] **Step 1: Implementación**

```sh
#!/bin/sh
# Copia las mascotas incluidas en ChatGPT.app a ~/.mascota/mascotas (solo uso personal en esta Mac).
set -eu
ASAR=/Applications/ChatGPT.app/Contents/Resources/app.asar
DESTINO="${MASCOTA_DIR:-$HOME/.mascota}/mascotas"
[ -f "$ASAR" ] || { echo "No encuentro ChatGPT.app" >&2; exit 1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
npx -y @electron/asar list "$ASAR" | grep -E '^/webview/assets/[a-z0-9-]+-spritesheet-v[0-9]+-[0-9a-f]+\.webp$' | while read -r ruta; do
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
done
```

- [ ] **Step 2:** Probar con destino temporal: `MASCOTA_DIR=$(mktemp -d) sh scripts/instalar-mascotas.sh` → lista "Instalada Null Signal", etc.; verificar `pet.json` de `null-signal` con `plutil -p` y que `sips -g pixelWidth` de su hoja dé 1536.
- [ ] **Step 3:** commit "Instalador de mascotas de ChatGPT".

### Task 8: App (hoja de sprites, panel flotante, barra de menú, bucle)

**Files:**
- Create: `Sources/Mascota/HojaSprites.swift`, `Sources/Mascota/PanelMascota.swift`, `Sources/Mascota/MenuBarra.swift`, `Sources/Mascota/AppDelegate.swift`
- Modify: `Sources/Mascota/main.swift`

**Interfaces:**
- Consumes: `LectorEstado.leer`, `Agregador.principal/estadoEfectivo/debeMostrarse`, `Animaciones.para/cuadro`, `Textos.globo`, `CatalogoMascotas.cargar` (Tasks 1–4).
- Produces: `Mascota` ejecutable que corre como app accesoria.

- [ ] **Step 1: `HojaSprites.swift`**

```swift
import AppKit

/// Recorta celdas de 192x208 de una hoja de sprites de Codex, con caché.
final class HojaSprites {
    static let ancho = 192, alto = 208
    private let imagen: CGImage
    private var cache: [Int: CGImage] = [:]

    init?(url: URL) {
        guard let img = NSImage(contentsOf: url),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        imagen = cg
    }

    func celda(fila: Int, columna: Int) -> CGImage? {
        let clave = fila * 16 + columna
        if let c = cache[clave] { return c }
        let rect = CGRect(x: columna * Self.ancho, y: fila * Self.alto, width: Self.ancho, height: Self.alto)
        let c = imagen.cropping(to: rect)
        cache[clave] = c
        return c
    }
}
```

- [ ] **Step 2: `PanelMascota.swift`**

```swift
import AppKit

/// Ventana flotante sin bordes con la mascota y un globo de texto encima.
final class PanelMascota: NSPanel {
    private let sprite = NSView()
    private let globo = NSTextField(labelWithString: "")
    static let tamSprite = NSSize(width: 80, height: 87)

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 220, height: 130),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false

        let fondo = NSView(frame: contentRect(forFrameRect: frame))
        sprite.wantsLayer = true
        sprite.layer?.contentsGravity = .resizeAspect
        sprite.layer?.magnificationFilter = .nearest
        sprite.frame = NSRect(x: (220 - Self.tamSprite.width) / 2, y: 0,
                              width: Self.tamSprite.width, height: Self.tamSprite.height)

        globo.font = .systemFont(ofSize: 11, weight: .medium)
        globo.textColor = .white
        globo.alignment = .center
        globo.wantsLayer = true
        globo.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        globo.layer?.cornerRadius = 8
        globo.isHidden = true

        fondo.addSubview(sprite)
        fondo.addSubview(globo)
        contentView = fondo

        if !setFrameUsingName("MascotaPanel"), let pantalla = NSScreen.main?.visibleFrame {
            setFrameOrigin(NSPoint(x: pantalla.maxX - 240, y: pantalla.maxY - 140))
        }
        setFrameAutosaveName("MascotaPanel")
    }

    override var canBecomeKey: Bool { false }

    func mostrarCuadro(_ imagen: CGImage?) { sprite.layer?.contents = imagen }

    func mostrarGlobo(_ texto: String?) {
        guard let texto else { globo.isHidden = true; return }
        globo.stringValue = "  \(texto)  "
        globo.sizeToFit()
        let ancho = min(globo.frame.width + 8, 216)
        globo.frame = NSRect(x: (220 - ancho) / 2, y: Self.tamSprite.height + 6, width: ancho, height: 22)
        globo.isHidden = false
    }
}
```

- [ ] **Step 3: `MenuBarra.swift`**

```swift
import AppKit
import MascotaCore
import ServiceManagement

/// Ícono animado en la barra de menú y su menú.
@MainActor
final class MenuBarra: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    weak var app: AppDelegate?

    override init() {
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func mostrarCuadro(_ imagen: CGImage?) {
        guard let imagen else { return }
        item.button?.image = NSImage(cgImage: imagen, size: NSSize(width: 17, height: 18))
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let app else { return }
        menu.removeAllItems()
        let visible = app.panel.isVisible
        menu.addItem(accion(visible ? "Ocultar mascota" : "Mostrar mascota", #selector(alternarPanel)))
        menu.addItem(.separator())

        let ahora = Date()
        let sesiones = Agregador.vigentes(app.sesiones, ahora: ahora)
        if sesiones.isEmpty {
            menu.addItem(NSMenuItem(title: "Sin sesiones activas", action: nil, keyEquivalent: ""))
        }
        for s in sesiones.sorted(by: { $0.ts > $1.ts }) {
            menu.addItem(NSMenuItem(title: Textos.globo(s, estado: Agregador.estadoEfectivo(s, ahora: ahora)),
                                    action: nil, keyEquivalent: ""))
        }
        menu.addItem(.separator())
        for cli in ["claude", "codex"] {
            let sub = NSMenu()
            for m in app.catalogo {
                let it = accion(m.nombre, #selector(elegirMascota(_:)))
                it.representedObject = [cli, m.id]
                it.state = app.mascotaId(cli) == m.id ? .on : .off
                sub.addItem(it)
            }
            let raiz = NSMenuItem(title: "Mascota de \(cli == "codex" ? "Codex" : "Claude")", action: nil, keyEquivalent: "")
            raiz.submenu = sub
            menu.addItem(raiz)
        }
        let login = accion("Abrir al iniciar sesión", #selector(alternarLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(accion("Salir", #selector(salir)))
    }

    private func accion(_ titulo: String, _ sel: Selector) -> NSMenuItem {
        let it = NSMenuItem(title: titulo, action: sel, keyEquivalent: "")
        it.target = self
        return it
    }

    @objc private func alternarPanel() { app?.alternarPanelManual() }

    @objc private func elegirMascota(_ it: NSMenuItem) {
        guard let par = it.representedObject as? [String] else { return }
        app?.elegirMascota(cli: par[0], id: par[1])
    }

    @objc private func alternarLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { NSLog("Mascota: no pude cambiar el inicio de sesión: \(error)") }
    }

    @objc private func salir() { NSApp.terminate(nil) }
}
```

- [ ] **Step 4: `AppDelegate.swift`**

```swift
import AppKit
import MascotaCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let panel = PanelMascota()
    let menu = MenuBarra()
    private(set) var sesiones: [Sesion] = []
    private(set) var catalogo: [MascotaDef] = []
    private var hojas: [String: HojaSprites] = [:]
    private var ultimaFirma = ""
    private var cambio = Date.distantPast
    private var ocultoManual = false
    private var ultimoSondeo = Date.distantPast

    private let raiz = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".mascota")

    func applicationDidFinishLaunching(_ n: Notification) {
        menu.app = self
        catalogo = CatalogoMascotas.cargar(directorios: [
            raiz.appendingPathComponent("mascotas"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/pets"),
        ])
        Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    func mascotaId(_ cli: String) -> String {
        UserDefaults.standard.string(forKey: "mascota.\(cli)") ?? "null-signal"
    }

    func elegirMascota(cli: String, id: String) {
        UserDefaults.standard.set(id, forKey: "mascota.\(cli)")
    }

    func alternarPanelManual() {
        ocultoManual = panel.isVisible
        if ocultoManual { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    private func hoja(_ cli: String) -> HojaSprites? {
        let id = mascotaId(cli)
        if let h = hojas[id] { return h }
        guard let def = catalogo.first(where: { $0.id == id }) ?? catalogo.first,
              let h = HojaSprites(url: def.hoja) else { return nil }
        hojas[id] = h
        return h
    }

    private func tick() {
        let ahora = Date()
        if ahora.timeIntervalSince(ultimoSondeo) >= 0.5 {
            ultimoSondeo = ahora
            sesiones = LectorEstado.leer(directorio: raiz.appendingPathComponent("estado"))
        }
        let principal = Agregador.principal(sesiones, ahora: ahora)
        let estado = principal.map { Agregador.estadoEfectivo($0, ahora: ahora) }

        let firma = principal.map { "\($0.cli)-\($0.session)-\(estado!.rawValue)-\($0.ts)" } ?? ""
        if firma != ultimaFirma {
            ultimaFirma = firma
            cambio = ahora
            if principal != nil { ocultoManual = false }
        }
        let desdeCambio = ahora.timeIntervalSince(cambio)

        let anim = Animaciones.para(estado: estado, desdeCambio: desdeCambio)
        let cuadro = hoja(principal?.cli ?? "claude")?
            .celda(fila: anim.fila, columna: Animaciones.cuadro(anim, tiempo: desdeCambio))
        panel.mostrarCuadro(cuadro)
        menu.mostrarCuadro(cuadro)

        let mostrarGlobo = principal != nil && (estado == .waiting || estado == .failed || desdeCambio < 6)
        panel.mostrarGlobo(mostrarGlobo ? principal.map { Textos.globo($0, estado: estado!) } : nil)

        let debe = Agregador.debeMostrarse(sesiones, ahora: ahora) && !ocultoManual
        if debe && !panel.isVisible { panel.orderFrontRegardless() }
        if !debe && panel.isVisible && !ocultoManual { panel.orderOut(nil) }
    }
}
```

- [ ] **Step 5: `main.swift`**

```swift
import AppKit

let app = NSApplication.shared
let delegado = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegado
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 6:** `swift build` sin errores; `swift test` sigue en verde.
- [ ] **Step 7: Prueba manual** (necesita Task 7 instalada): `swift run Mascota &`, luego
  `printf '{"hook_event_name":"PreToolUse","session_id":"demo","cwd":"/x/demo"}' | sh hooks/pet-hook.sh claude` → aparece el panel con la animación `running` y el globo «Claude trabajando · demo»; repetir con `PermissionRequest` (❓), `Stop` (saluda y queda en idle), `SessionEnd`. Arrastrar el panel y comprobar que conserva la posición al reiniciar.
- [ ] **Step 8:** commit "App: panel flotante, barra de menú y animación".

### Task 9: Empaquetar, instalar y prueba real

**Files:**
- Create: `scripts/empaquetar.sh`, `README.md`

- [ ] **Step 1: `scripts/empaquetar.sh`**

```sh
#!/bin/sh
# Compila Mascota.app y la instala en ~/Applications.
set -eu
RAIZ=$(cd "$(dirname "$0")/.." && pwd)
cd "$RAIZ"
swift build -c release
APP="$RAIZ/.build/Mascota.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Mascota "$APP/Contents/MacOS/Mascota"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.gcoder.mascota</string>
  <key>CFBundleName</key><string>Mascota</string>
  <key>CFBundleExecutable</key><string>Mascota</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
codesign --force --sign - "$APP"
mkdir -p "$HOME/Applications"
pkill -x Mascota 2>/dev/null || true
rm -rf "$HOME/Applications/Mascota.app"
cp -R "$APP" "$HOME/Applications/Mascota.app"
open "$HOME/Applications/Mascota.app"
echo "Mascota instalada en ~/Applications/Mascota.app"
```

- [ ] **Step 2:** `sh scripts/instalar-mascotas.sh && sh scripts/empaquetar.sh` → la app corre sin ícono en el Dock y con ícono en la barra de menú.
- [ ] **Step 3:** `python3 scripts/instalar-hooks.py` (hooks reales, con respaldo). Revisar el diff de `~/.claude/settings.json` y `~/.codex/hooks.json` contra su respaldo: solo se agregan grupos con `pet-hook.sh`. Si Codex pide confiar en los hooks nuevos, avisar al usuario.
- [ ] **Step 4: Prueba real:** abrir una sesión nueva de Claude y otra de Codex, pedir algo que use herramientas y ver `running` → `done`; provocar un permiso y ver `waiting`. Activar «Abrir al iniciar sesión» desde el menú.
- [ ] **Step 5: README** corto: qué es, instalar (`instalar-mascotas.sh`, `empaquetar.sh`, `instalar-hooks.py`), desinstalar (`instalar-hooks.py --desinstalar`, borrar la app y `~/.mascota`), y cómo agregar una mascota propia en `~/.codex/pets/`.
- [ ] **Step 6:** commit "Empaquetado, README e instalación".
