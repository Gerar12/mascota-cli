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
    /// Carpeta de trabajo que reportó el CLI (para encontrar su terminal).
    public let cwd: String?
    /// Encargo automático de otro agente (codex exec, claude -p, ayudantes de Codex): no sale en el menú.
    public let auto: Bool?
    /// Terminal del proceso (p. ej. "ttys003") y app de terminal (TERM_PROGRAM: ghostty, Apple_Terminal, iTerm.app).
    public let tty: String?
    public let terminal: String?

    public init(cli: String, session: String, project: String, state: EstadoAgente, ts: TimeInterval,
                pid: Int32? = nil, cwd: String? = nil, auto: Bool? = nil, tty: String? = nil, terminal: String? = nil) {
        self.cli = cli; self.session = session; self.project = project; self.state = state; self.ts = ts
        self.pid = pid; self.cwd = cwd; self.auto = auto; self.tty = tty; self.terminal = terminal
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
