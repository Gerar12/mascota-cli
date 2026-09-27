import AppKit
import MascotaCore

/// Notificaciones de permiso y No molestar (calla la voz, esconde el globo y los avisos por un rato).
@MainActor
final class ControlAvisos {
    let avisador = Avisador()
    private var avisadas: Set<String> = []

    var noMolestarHasta: Date? {
        get { UserDefaults.standard.object(forKey: "noMolestarHasta") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "noMolestarHasta") }
    }
    var noMolestar: Bool { NoMolestar.activo(hasta: noMolestarHasta, ahora: Date()) }

    /// Calla la voz (si estaba activa, se reactiva al terminar) y esconde el globo y los avisos.
    func activarNoMolestar(_ o: NoMolestar.Opcion) {
        if ControlVoz.disponible, !ControlVoz.silenciada {
            ControlVoz.silenciar(true)
            UserDefaults.standard.set(true, forKey: "noMolestarVoz")
        }
        noMolestarHasta = NoMolestar.hasta(o, ahora: Date())
    }

    func desactivarNoMolestar() {
        noMolestarHasta = nil
        if UserDefaults.standard.bool(forKey: "noMolestarVoz") {
            ControlVoz.silenciar(false)
            UserDefaults.standard.set(false, forKey: "noMolestarVoz")
        }
    }

    /// Termina No molestar si ya pasó su hora y notifica los permisos nuevos
    /// (si no estás ya en la terminal). `pose`: la mascota pidiendo permiso, para la notificación.
    func revisar(_ sesiones: [Sesion], ahora: Date, pose: CGImage?) {
        if let h = noMolestarHasta, ahora >= h { desactivarNoMolestar() }
        let (nuevas, esperando) = Avisos.permisosNuevos(sesiones, yaAvisadas: avisadas)
        avisador.retirar(Array(avisadas.subtracting(esperando)))
        avisadas = esperando
        let terminales: Set = ["com.mitchellh.ghostty", "com.apple.Terminal", "com.googlecode.iterm2"]
        let enTerminal = terminales.contains(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "")
        guard !noMolestar, !enTerminal else { return }
        for s in nuevas { avisador.avisar(s, imagen: pose) }
    }
}
