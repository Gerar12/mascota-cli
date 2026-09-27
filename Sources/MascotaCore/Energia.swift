import Foundation

/// Cuándo impedir que la Mac entre en reposo (la pantalla sí se apaga).
public enum Energia {
    /// Margen tras el último trabajo, como el antiguo keep-awake (15 min).
    public static let margen: TimeInterval = 15 * 60

    /// ¿Algún CLI está trabajando o esperando permiso?
    public static func hayTrabajo(_ sesiones: [Sesion], ahora: Date) -> Bool {
        Agregador.vigentes(sesiones, ahora: ahora).contains {
            let e = Agregador.estadoEfectivo($0, ahora: ahora)
            return e == .running || e == .waiting
        }
    }

    public static func mantenerDespierta(trabajando: Bool, ultimaVezTrabajando: Date?, ahora: Date) -> Bool {
        if trabajando { return true }
        guard let ultima = ultimaVezTrabajando else { return false }
        return ahora.timeIntervalSince(ultima) < margen
    }
}
