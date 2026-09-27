public enum Voz {
    /// Proveedores que ofrece el menú; el valor se guarda en ~/.claude/tts/proveedor.
    public static let proveedores: [(id: String, nombre: String)] = [
        ("eleven", "ElevenLabs (Daniela)"),
        ("edge", "Gratis (edge-tts, Dalia)"),
        ("local", "Local (Mónica, sin internet)"),
    ]
}
