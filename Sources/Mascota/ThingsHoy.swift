import AppKit

/// Primera tarea abierta de la lista «Hoy» de Things 3 (solo si Things está abierto; nunca lo abre).
@MainActor
final class ThingsHoy {
    private(set) var tarea: (id: String, nombre: String)?
    private(set) var pendientes = 0

    private var abierto: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.culturedcode.ThingsMac").isEmpty
    }

    func refrescar() {
        guard abierto else { tarea = nil; pendientes = 0; return }
        Task.detached {
            let salida = Self.osascript("""
                tell application "Things3"
                  set sep to character id 9
                  set ts to to dos of list "Hoy" whose status is open
                  if (count of ts) is 0 then return ""
                  set t to item 1 of ts
                  return (id of t) & sep & (name of t) & sep & ((count of ts) as text)
                end tell
                """) ?? ""
            let partes = salida.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\t")
            await MainActor.run {
                if partes.count == 3 {
                    self.tarea = (partes[0], partes[1])
                    self.pendientes = Int(partes[2]) ?? 0
                } else {
                    self.tarea = nil
                    self.pendientes = 0
                }
            }
        }
    }

    func completar() {
        guard let id = tarea?.id else { return }
        Task.detached {
            _ = Self.osascript(#"tell application "Things3" to set status of to do id "\#(id)" to completed"#)
            await MainActor.run { self.refrescar() }
        }
    }

    func abrir() {
        guard let id = tarea?.id, let url = URL(string: "things:///show?id=\(id)") else { return }
        NSWorkspace.shared.open(url)
    }

    nonisolated private static func osascript(_ guion: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", guion]
        let salida = Pipe()
        p.standardOutput = salida
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let datos = salida.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? String(decoding: datos, as: UTF8.self) : nil
    }
}
