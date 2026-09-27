public enum Procesos {
    /// Recibe la salida de `ps -axo tty=,comm=`. ¿Hay algún `codex` con terminal? El servicio de fondo no tiene (`??`).
    public static func hayCodexConTerminal(salidaPs: String) -> Bool {
        salidaPs.split(separator: "\n").contains { linea in
            // `ps` alinea columnas con varios espacios: "ttys001  codex".
            let partes = linea.split(whereSeparator: \.isWhitespace)
            guard partes.count >= 2, partes[0] != "??" else { return false }
            let comando = partes.dropFirst().joined(separator: " ")
            return comando == "codex" || comando.hasSuffix("/codex")
        }
    }
}
