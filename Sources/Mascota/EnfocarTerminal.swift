import AppKit
import MascotaCore

/// Lleva al usuario a la terminal de una sesión.
/// - Terminal.app e iTerm2: pestaña exacta por su tty (la anota el hook).
/// - Ghostty (AppleScript 1.3+, sin tty): Claude por la carpeta real del proceso `claude` + título con su
///   símbolo; Codex por la carpeta que reportó el hook. Si no la encuentra, trae la app al frente.
enum EnfocarTerminal {
    static func ir(a sesion: Sesion) {
        DispatchQueue.global(qos: .userInitiated).async {
            switch sesion.terminal {
            case "Apple_Terminal":
                if let tty = sesion.tty, osascript(porTty(tty, app: "Terminal")) == "ok\n" { return }
                _ = osascript(#"tell application "Terminal" to activate"#)
                return
            case "iTerm.app":
                if let tty = sesion.tty, osascript(porTty(tty, app: "iTerm2")) == "ok\n" { return }
                _ = osascript(#"tell application id "com.googlecode.iterm2" to activate"#)
                return
            default:
                break
            }
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

    /// AppleScript que busca la pestaña (Terminal.app) o sesión (iTerm2) con esa tty, la trae al frente y
    /// devuelve "ok". La tty solo trae [A-Za-z0-9] (el hook la filtra), así que se puede meter en el texto.
    /// Comprueba `running` para no abrir la app si no está.
    private static func porTty(_ tty: String, app: String) -> String {
        let ruta = "/dev/" + tty.filter { $0.isLetter || $0.isNumber }
        if app == "Terminal" {
            return """
                tell application "Terminal"
                  if not running then return "no"
                  repeat with w in windows
                    repeat with t in tabs of w
                      if tty of t is "\(ruta)" then
                        if miniaturized of w then set miniaturized of w to false
                        set selected of t to true
                        set index of w to 1
                        activate
                        return "ok"
                      end if
                    end repeat
                  end repeat
                end tell
                return "no"
                """
        }
        return """
            tell application id "com.googlecode.iterm2"
              if not running then return "no"
              repeat with w in windows
                repeat with t in tabs of w
                  repeat with s in sessions of t
                    if tty of s is "\(ruta)" then
                      select w
                      select t
                      select s
                      activate
                      return "ok"
                    end if
                  end repeat
                end repeat
              end repeat
            end tell
            return "no"
            """
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
