import Foundation
import MascotaCore

/// Lee las sesiones de ~/.mascota/estado y olvida las de terminales que ya se cerraron.
@MainActor
final class SondeoSesiones {
    private(set) var sesiones: [Sesion] = []
    private let dir: URL
    private var ultimoPs = (cuando: Date.distantPast, codex: false)
    private var ultimaRevision = Date.distantPast

    /// Autodiagnóstico: Codex trabaja (escribe en sus registros, con una terminal abierta) pero sus
    /// hooks no avisan a la mascota. Se revisa cada minuto.
    private(set) var codexCallado = false

    /// Último aviso de Codex que llegó (se guarda: los archivos de estado se borran al cerrar la sesión).
    private var ultimoAvisoCodex: Date? {
        get { UserDefaults.standard.object(forKey: "diagnostico.ultimoAvisoCodex") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "diagnostico.ultimoAvisoCodex") }
    }

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
        if let ts = vivas.filter({ $0.cli == "codex" }).map(\.ts).max() {
            let aviso = Date(timeIntervalSince1970: ts)
            if aviso > (ultimoAvisoCodex ?? .distantPast) { ultimoAvisoCodex = aviso }
        }
        if ahora.timeIntervalSince(ultimaRevision) >= 60 {
            ultimaRevision = ahora
            codexCallado = Diagnostico.codexCallado(ultimoRegistro: LectorCuotas.ultimoRegistroCodex(),
                                                    ultimoAviso: ultimoAvisoCodex, codexAbierto: codexAbierto(ahora))
        }
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
