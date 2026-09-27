/// Estado del lector de voz que se muestra en el globo.
public enum EstadoVoz: Equatable, Sendable {
    case normal, hablando, silenciada
}

public enum Voz {
    /// Proveedores que ofrece el menú; el valor se guarda en ~/.claude/tts/proveedor.
    public static let proveedores: [(id: String, nombre: String)] = [
        ("eleven", "ElevenLabs (Daniela)"),
        ("edge", "Gratis (edge-tts, Dalia)"),
        ("local", "Local (Mónica, sin internet)"),
    ]

    public static func estado(silenciada: Bool, sonando: Bool) -> EstadoVoz {
        if silenciada { return .silenciada }
        return sonando ? .hablando : .normal
    }
}
