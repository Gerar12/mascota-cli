/// Una terminal (o split) de Ghostty, como la describe su AppleScript.
public struct TerminalGhostty: Equatable, Sendable {
    public let id: String
    public let nombre: String
    public let carpeta: String

    public init(id: String, nombre: String, carpeta: String) {
        self.id = id; self.nombre = nombre; self.carpeta = carpeta
    }

    /// Claude Code pone en el título un símbolo (✳, ◐, ✶…) antes del tema de la sesión.
    var pareceClaude: Bool {
        guard let c = nombre.unicodeScalars.first else { return false }
        return !(c.properties.isAlphabetic || c.properties.numericType != nil || c == " ")
    }
}

public enum Terminales {
    /// Lee líneas "id<TAB>nombre<TAB>carpeta".
    public static func leer(_ salida: String) -> [TerminalGhostty] {
        salida.split(separator: "\n").compactMap { linea in
            let partes = linea.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            return partes.count == 3 ? TerminalGhostty(id: partes[0], nombre: partes[1], carpeta: partes[2]) : nil
        }
    }

    /// Terminal de la sesión: misma carpeta y, si hay varias, la que parece de Claude (para Claude)
    /// o la que no (para Codex). nil si ninguna está en esa carpeta.
    public static func elegir(_ terminales: [TerminalGhostty], cli: String, carpeta: String?) -> String? {
        guard let carpeta else { return nil }
        func normal(_ r: String) -> String { r.count > 1 && r.hasSuffix("/") ? String(r.dropLast()) : r }
        let enCarpeta = terminales.filter { normal($0.carpeta) == normal(carpeta) }
        let preferida = enCarpeta.first { $0.pareceClaude == (cli == "claude") }
        return (preferida ?? enCarpeta.first)?.id
    }
}
