import Foundation
import MascotaCore

/// Controla un lector de voz externo con la convención de ~/.claude/tts: archivo OFF para silenciar,
/// `proveedor` con la voz elegida, cola `queue/` de trabajos y `hooks/tts-dispatch.sh` que los reproduce.
/// Si esa carpeta no existe, la mascota no muestra nada de voz.
enum ControlVoz {
    private static let casa = FileManager.default.homeDirectoryForCurrentUser
    static let carpeta = casa.appendingPathComponent(".claude/tts")
    private static let off = carpeta.appendingPathComponent("OFF")
    private static let archivoProveedor = carpeta.appendingPathComponent("proveedor")
    private static let despachador = casa.appendingPathComponent(".claude/hooks/tts-dispatch.sh")
    private static let stop = casa.appendingPathComponent(".local/bin/stop")

    static var disponible: Bool { FileManager.default.fileExists(atPath: carpeta.path) }
    static var silenciada: Bool { FileManager.default.fileExists(atPath: off.path) }

    static var proveedor: String {
        let texto = (try? String(contentsOf: archivoProveedor, encoding: .utf8)) ?? ""
        let id = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? "eleven" : id
    }

    /// Lee el final del log del lector de voz para saber si ElevenLabs se quedó sin créditos.
    static var elevenSinCreditos: Bool {
        guard let h = FileHandle(forReadingAtPath: "/tmp/claude-tts.log") else { return false }
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

    /// Corta la voz que suena y vacía la cola (igual que el comando `stop`).
    static func callar() {
        if FileManager.default.isExecutableFile(atPath: stop.path) {
            correr(stop.path, [])
        } else {
            correr("/usr/bin/pkill", ["-x", "afplay"])
            correr("/usr/bin/pkill", ["-x", "say"])
        }
    }

    /// Vuelve a tocar el último audio guardado (sin gastar créditos); si no hay, re-sintetiza el último texto.
    static func repetirUltimo() {
        let fm = FileManager.default
        let archivos = (try? fm.contentsOfDirectory(at: carpeta, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        func fecha(_ u: URL) -> Date {
            (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        let mp3 = archivos.filter { $0.lastPathComponent.hasPrefix("last-") && $0.pathExtension == "mp3" }
            .max { fecha($0) < fecha($1) }
        let trabajo: String
        if let mp3 {
            trabajo = "PLAY\nmascota\n\(mp3.path)\n"
        } else if let texto = try? String(contentsOf: carpeta.appendingPathComponent("last.txt"), encoding: .utf8) {
            trabajo = "SPEAK\nglobal\n\(texto)\n"
        } else {
            return
        }
        let cola = carpeta.appendingPathComponent("queue")
        try? fm.createDirectory(at: cola, withIntermediateDirectories: true)
        let nombre = "\(Int(Date().timeIntervalSince1970 * 1_000_000_000))-mascota.job"
        try? trabajo.write(to: cola.appendingPathComponent(nombre), atomically: true, encoding: .utf8)
        correr("/bin/bash", [despachador.path])
    }

    private static func correr(_ ruta: String, _ argumentos: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ruta)
        p.arguments = argumentos
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}
