import Foundation
import MascotaCore

/// Controla el lector de voz de Mascota (carpeta `voz/` del repo, instalada con `instalar-hooks.py --voz`):
/// archivo OFF para silenciar, `proveedor` con la voz elegida y los comandos de `~/.mascota/voz/bin`.
/// Si no está instalado, la mascota no muestra nada de voz.
enum ControlVoz {
    static let carpeta = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".mascota/voz")
    private static let bin = carpeta.appendingPathComponent("bin")
    private static let off = carpeta.appendingPathComponent("OFF")
    private static let archivoProveedor = carpeta.appendingPathComponent("proveedor")
    private static let log = carpeta.appendingPathComponent("voz.log")

    static var disponible: Bool {
        FileManager.default.isExecutableFile(atPath: bin.appendingPathComponent("despachador.sh").path)
    }
    static var silenciada: Bool { FileManager.default.fileExists(atPath: off.path) }

    static var proveedor: String {
        let texto = (try? String(contentsOf: archivoProveedor, encoding: .utf8)) ?? ""
        let id = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? "eleven" : id
    }

    /// Lee el final del log de voz para saber si ElevenLabs se quedó sin créditos.
    static var elevenSinCreditos: Bool {
        guard let h = FileHandle(forReadingAtPath: log.path) else { return false }
        defer { try? h.close() }
        let fin = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: fin > 65_536 ? fin - 65_536 : 0)
        let texto = String(decoding: (try? h.readToEnd()) ?? Data(), as: UTF8.self)
        return Voz.elevenSinCreditos(log: texto)
    }

    static func elegir(proveedor id: String) {
        try? (id + "\n").write(to: archivoProveedor, atomically: true, encoding: .utf8)
    }

    static func silenciar(_ si: Bool) {
        if si {
            FileManager.default.createFile(atPath: off.path, contents: nil)
            callar()
        } else {
            try? FileManager.default.removeItem(at: off)
        }
    }

    /// Corta la voz que suena y vacía la cola.
    static func callar() { correr("callar.sh") }

    /// Vuelve a tocar el último audio guardado (sin gastar créditos); si no hay, re-sintetiza el último texto.
    static func repetirUltimo() { correr("repetir.sh") }

    private static func correr(_ comando: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [bin.appendingPathComponent(comando).path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}
