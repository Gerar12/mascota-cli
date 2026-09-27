import Foundation
import MascotaCore

/// Lee las sesiones de ~/.mascota/estado y olvida las de terminales que ya se cerraron.
@MainActor
final class SondeoSesiones {
    private(set) var sesiones: [Sesion] = []
    private let dir: URL
    private var ultimoPs = (cuando: Date.distantPast, codex: false)

    init(raiz: URL) { dir = raiz.appendingPathComponent("estado") }

    func actualizar(_ ahora: Date) {
        // Terminal cerrada sin SessionEnd: el proceso ya no existe, se olvida la sesión.
        let (vivas, muertas) = Agregador.separarPorProceso(LectorEstado.leer(directorio: dir),
                                                           codexAbierto: codexAbierto(ahora)) { pid in
            kill(pid, 0) == 0 || errno == EPERM
        }
        for s in muertas {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(s.cli)-\(s.session).json"))
        }
        sesiones = vivas
    }

    /// ¿Hay alguna terminal con Codex? (proceso `codex` con terminal; el servicio de fondo no tiene).
    /// Se consulta cada 2 s porque lanza `ps`.
    private func codexAbierto(_ ahora: Date) -> Bool {
        guard ahora.timeIntervalSince(ultimoPs.cuando) >= 2 else { return ultimoPs.codex }
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axo", "tty=,comm="]
        let salida = Pipe()
        ps.standardOutput = salida
        if (try? ps.run()) != nil {
            let texto = String(decoding: salida.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            ps.waitUntilExit()
            ultimoPs = (ahora, Procesos.hayCodexConTerminal(salidaPs: texto))
        }
        return ultimoPs.codex
    }
}
