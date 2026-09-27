public enum Voz {
    /// Proveedores que ofrece el menú; el valor se guarda en ~/.claude/tts/proveedor.
    public static let proveedores: [(id: String, nombre: String)] = [
        ("eleven", "ElevenLabs (Daniela)"),
        ("edge", "Gratis (edge-tts, Dalia)"),
        ("local", "Local (Mónica, sin internet)"),
    ]

    /// ¿El último intento con ElevenLabs en el log del lector de voz falló por falta de créditos?
    public static func elevenSinCreditos(log: String) -> Bool {
        guard let ultimo = log.split(separator: "\n").last(where: {
            $0.hasPrefix("ELEVEN OK") || $0.hasPrefix("ELEVEN FAIL")
        }) else { return false }
        return ultimo.contains("quota_exceeded")
    }
}
