import Foundation

public enum Agregador {
    public static let caducidad: TimeInterval = 30 * 60
    public static let vidaDeFailed: TimeInterval = 60

    /// Las sesiones con proceso conocido valen mientras el proceso viva (se filtra con `separarPorProceso`);
    /// las demás caducan a los 30 min.
    public static func vigentes(_ sesiones: [Sesion], ahora: Date) -> [Sesion] {
        sesiones.filter { $0.pid != nil || ahora.timeIntervalSince1970 - $0.ts < caducidad }
    }

    /// Separa las sesiones cuyo proceso ya terminó (terminal cerrada); las que no tienen pid cuentan como vivas.
    public static func separarPorProceso(_ sesiones: [Sesion], estaVivo: (Int32) -> Bool) -> (vivas: [Sesion], muertas: [Sesion]) {
        var vivas: [Sesion] = [], muertas: [Sesion] = []
        for s in sesiones {
            if let pid = s.pid, !estaVivo(pid) { muertas.append(s) } else { vivas.append(s) }
        }
        return (vivas, muertas)
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

    /// Visible mientras haya alguna sesión abierta de Claude o Codex.
    public static func debeMostrarse(_ sesiones: [Sesion], ahora: Date) -> Bool {
        !vigentes(sesiones, ahora: ahora).isEmpty
    }
}
