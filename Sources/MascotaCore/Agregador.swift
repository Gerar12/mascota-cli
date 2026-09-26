import Foundation

public enum Agregador {
    public static let caducidad: TimeInterval = 30 * 60
    public static let vidaDeFailed: TimeInterval = 60
    public static let ocultarTras: TimeInterval = 3 * 60

    public static func vigentes(_ sesiones: [Sesion], ahora: Date) -> [Sesion] {
        sesiones.filter { ahora.timeIntervalSince1970 - $0.ts < caducidad }
    }

    public static func estadoEfectivo(_ s: Sesion, ahora: Date) -> EstadoAgente {
        if s.state == .failed, ahora.timeIntervalSince1970 - s.ts > vidaDeFailed { return .done }
        return s.state
    }

    static func prioridad(_ e: EstadoAgente) -> Int {
        switch e {
        case .waiting: 4
        case .failed: 3
        case .running: 2
        case .done: 1
        }
    }

    public static func principal(_ sesiones: [Sesion], ahora: Date) -> Sesion? {
        vigentes(sesiones, ahora: ahora).max {
            (prioridad(estadoEfectivo($0, ahora: ahora)), $0.ts) < (prioridad(estadoEfectivo($1, ahora: ahora)), $1.ts)
        }
    }

    public static func debeMostrarse(_ sesiones: [Sesion], ahora: Date) -> Bool {
        let v = vigentes(sesiones, ahora: ahora)
        if v.contains(where: { $0.state == .running || $0.state == .waiting }) { return true }
        guard let ultima = v.map(\.ts).max() else { return false }
        return ahora.timeIntervalSince1970 - ultima < ocultarTras
    }
}
