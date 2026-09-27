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
    /// Proceso `claude` o `codex` de la terminal; nil si el hook no lo encontró.
    public let pid: Int32?

    public init(cli: String, session: String, project: String, state: EstadoAgente, ts: TimeInterval, pid: Int32? = nil) {
        self.cli = cli; self.session = session; self.project = project; self.state = state; self.ts = ts; self.pid = pid
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
