import AppKit
import MascotaCore

/// Lleva al usuario a la terminal de Ghostty de una sesión (con el AppleScript de Ghostty 1.3+).
/// Claude: carpeta real del proceso `claude` + título con su símbolo. Codex: carpeta que reportó el hook.
/// Si no la encuentra, al menos trae Ghostty al frente.
enum EnfocarTerminal {
    static func ir(a sesion: Sesion) {
        DispatchQueue.global(qos: .userInitiated).async {
            let carpeta = sesion.pid.flatMap(carpetaDeProceso) ?? sesion.cwd
            let lista = Terminales.leer(osascript("""
                tell application "Ghostty"
                  -- Dentro de Ghostty, `tab` es una pestaña, no el tabulador: se usa su código.
                  set sep to character id 9
                  set salida to ""
                  repeat with t in terminals
                    set salida to salida & (id of t) & sep & (name of t) & sep & (working directory of t) & linefeed
                  end repeat
                  return salida
                end tell
                """) ?? "")
            if let id = Terminales.elegir(lista, cli: sesion.cli, carpeta: carpeta) {
                _ = osascript("""
                    tell application "Ghostty"
                      focus (first terminal whose id is "\(id)")
                      activate
                    end tell
                    """)
            } else {
                _ = osascript(#"tell application "Ghostty" to activate"#)
            }
        }
    }

    /// Carpeta de trabajo actual de un proceso (`lsof -d cwd`).
    private static func carpetaDeProceso(_ pid: Int32) -> String? {
        correr("/usr/sbin/lsof", ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"])?
            .split(separator: "\n").first { $0.hasPrefix("n") }.map { String($0.dropFirst()) }
    }

    private static func osascript(_ guion: String) -> String? {
        correr("/usr/bin/osascript", ["-e", guion])
    }

    private static func correr(_ ruta: String, _ argumentos: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ruta)
        p.arguments = argumentos
        let salida = Pipe()
        p.standardOutput = salida
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let datos = salida.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? String(decoding: datos, as: UTF8.self) : nil
    }
}
