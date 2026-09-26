import Foundation

public struct Animacion: Equatable, Sendable {
    public let fila: Int
    public let duraciones: [TimeInterval]
    public var total: TimeInterval { duraciones.reduce(0, +) }
}

public enum Animaciones {
    private static func fila(_ n: Int, _ cuadros: Int, cada: TimeInterval, ultimo: TimeInterval) -> Animacion {
        Animacion(fila: n, duraciones: Array(repeating: cada, count: cuadros - 1) + [ultimo])
    }

    public static let idle = Animacion(fila: 0, duraciones: [0.28, 0.11, 0.11, 0.14, 0.14, 0.32])
    public static let waving = fila(3, 4, cada: 0.14, ultimo: 0.28)
    public static let jumping = fila(4, 5, cada: 0.14, ultimo: 0.28)
    public static let failed = fila(5, 8, cada: 0.14, ultimo: 0.24)
    public static let waiting = fila(6, 6, cada: 0.15, ultimo: 0.26)
    public static let running = fila(7, 6, cada: 0.12, ultimo: 0.22)
    public static let review = fila(8, 6, cada: 0.15, ultimo: 0.28)

    public static func para(estado: EstadoAgente?, desdeCambio: TimeInterval) -> Animacion {
        switch estado {
        case .running: running
        case .waiting: waiting
        case .failed: failed
        case .done: desdeCambio < waving.total * 2 ? waving : idle
        case nil: idle
        }
    }

    public static func cuadro(_ a: Animacion, tiempo: TimeInterval) -> Int {
        let t = tiempo.truncatingRemainder(dividingBy: a.total)
        var acumulado: TimeInterval = 0
        for (i, d) in a.duraciones.enumerated() {
            acumulado += d
            if t < acumulado { return i }
        }
        return a.duraciones.count - 1
    }
}

public enum Textos {
    public static func globo(_ s: Sesion, estado: EstadoAgente) -> String {
        let verbo = switch estado {
        case .running: "trabajando"
        case .waiting: "necesita permiso"
        case .done: "terminó"
        case .failed: "falló"
        }
        return "\(s.nombreCLI) \(verbo) · \(s.project)"
    }
}
