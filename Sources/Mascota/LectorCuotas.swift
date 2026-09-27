import Foundation
import MascotaCore

/// Lee las cuotas: Claude de la copia de su barra de estado (~/.mascota/claude-barra.json) y Codex de
/// sus registros de sesión más recientes (~/.codex/sessions/AAAA/MM/DD/*.jsonl).
enum LectorCuotas {
    private static let casa = FileManager.default.homeDirectoryForCurrentUser

    static func claude() -> CuotaClaude? {
        guard let datos = try? Data(contentsOf: casa.appendingPathComponent(".mascota/claude-barra.json")) else { return nil }
        return Cuota.leerClaude(datos)
    }

    static func codex() -> CuotaCodex? {
        let fm = FileManager.default
        let base = casa.appendingPathComponent(".codex/sessions")
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd"
        var archivos: [(URL, Date)] = []
        for dias in 0..<8 {
            let dia = base.appendingPathComponent(f.string(from: Date().addingTimeInterval(-86_400 * Double(dias))))
            for u in (try? fm.contentsOfDirectory(at: dia, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            where u.pathExtension == "jsonl" {
                let fecha = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                archivos.append((u, fecha))
            }
            if archivos.count >= 5 { break }
        }
        for (u, _) in archivos.sorted(by: { $0.1 > $1.1 }).prefix(5) {
            if let c = Cuota.leer(final(de: u)) { return c }
        }
        return nil
    }

    /// Últimos 256 KB de un archivo (los registros pueden ser grandes).
    private static func final(de url: URL) -> String {
        guard let h = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? h.close() }
        let fin = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: fin > 262_144 ? fin - 262_144 : 0)
        return String(decoding: (try? h.readToEnd()) ?? Data(), as: UTF8.self)
    }
}
