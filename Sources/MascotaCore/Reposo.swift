import Foundation

/// Una celda de la hoja de sprites.
public struct Celda: Equatable, Sendable {
    public let fila: Int
    public let columna: Int
    public init(fila: Int, columna: Int) { self.fila = fila; self.columna = columna }
}

/// Hacia dónde mira la mascota: 16 direcciones en sentido horario desde arriba (filas 9 y 10).
public enum Mirada {
    /// dx a la derecha y dy hacia arriba, desde el centro de la mascota. nil si el punto está encima de ella.
    public static func celda(dx: Double, dy: Double, zonaMuerta: Double = 20) -> Celda? {
        guard (dx * dx + dy * dy).squareRoot() >= zonaMuerta else { return nil }
        var grados = atan2(dx, dy) * 180 / .pi
        if grados < 0 { grados += 360 }
        let indice = Int((grados + 11.25) / 22.5) % 16
        return Celda(fila: 9 + indice / 8, columna: indice % 8)
    }
}

/// Lo que hace la mascota cuando nadie trabaja.
public enum AccionReposo: Equatable, Sendable {
    case descansar, saltar, saludar, mirarAlrededor
    case pasear(dx: Double)
}

/// Un instante de un paseo: cuánto se alejó de su casa y qué fila anima (nil = parado, en reposo).
public struct Paso: Equatable, Sendable {
    public let desplazamiento: Double
    public let fila: Int?
}

public enum Reposo {
    public static let velocidad: Double = 50          // puntos por segundo
    public static let pausa: Double = 1.2             // parado en el punto más lejano
    public static let cuadroMirada: Double = 0.18     // por dirección al mirar alrededor

    /// Elige una travesura con dos números al azar en [0, 1).
    public static func elegir(_ r: Double, _ r2: Double) -> AccionReposo {
        switch r {
        case ..<0.30: return .descansar
        case ..<0.60:
            // r2 elige el lado (izquierda < 0.5 ≤ derecha) y, alejándose de 0.5, la distancia: 60 a 140 pt.
            let distancia = (60 + 80 * abs(2 * r2 - 1)).rounded()
            return .pasear(dx: r2 < 0.5 ? -distancia : distancia)
        case ..<0.75: return .saltar
        case ..<0.90: return .saludar
        default: return .mirarAlrededor
        }
    }

    /// Segundos hasta la siguiente travesura.
    public static func espera(_ r: Double) -> TimeInterval { 10 + 15 * r }

    public static func duracion(_ a: AccionReposo) -> TimeInterval {
        switch a {
        case .descansar: 0
        case .saltar: Animaciones.jumping.total
        case .saludar: Animaciones.waving.total * 2
        case .mirarAlrededor: 16 * cuadroMirada
        case .pasear(let dx): 2 * abs(dx) / velocidad + pausa
        }
    }

    /// Paseo de ida, pausa y vuelta a casa. Fila 1 = caminar a la derecha, 2 = a la izquierda.
    public static func paseo(dx: Double, t: TimeInterval) -> Paso? {
        let ida = abs(dx) / velocidad
        let derecha = dx > 0
        switch t {
        case ..<ida: return Paso(desplazamiento: dx * t / ida, fila: derecha ? 1 : 2)
        case ..<(ida + pausa): return Paso(desplazamiento: dx, fila: nil)
        case ..<(2 * ida + pausa): return Paso(desplazamiento: dx * (1 - (t - ida - pausa) / ida), fila: derecha ? 2 : 1)
        default: return nil
        }
    }
}
