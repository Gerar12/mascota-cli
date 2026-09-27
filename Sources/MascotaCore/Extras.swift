import Foundation

// MARK: Cuota de Codex

public struct CuotaCodex: Equatable, Sendable {
    public let porcentaje: Double
    public let reinicio: Date

    public var titulo: String { "Codex · \(Int(porcentaje.rounded())) % de la semana" }

    public func detalle(calendario: Calendar = .current, locale: Locale = Locale(identifier: "es_MX")) -> String {
        "Se reinicia el " + Cuota.fechaCorta(reinicio, calendario: calendario, locale: locale)
    }
}

public enum Cuota {
    /// "sáb 3, 12:13"
    public static func fechaCorta(_ d: Date, calendario: Calendar = .current, locale: Locale = Locale(identifier: "es_MX")) -> String {
        let f = DateFormatter()
        f.calendar = calendario
        f.timeZone = calendario.timeZone
        f.locale = locale
        f.dateFormat = "EEE d, HH:mm"
        return f.string(from: d).replacingOccurrences(of: ".", with: "")
    }

    private struct Limites: Decodable {
        struct Ventana: Decodable { let used_percent: Double; let resets_at: Double }
        let primary: Ventana?
    }

    /// Último `rate_limits` de un registro de sesión de Codex (JSONL).
    public static func leer(_ registro: String) -> CuotaCodex? {
        for linea in registro.split(separator: "\n").reversed() where linea.contains("\"rate_limits\"") {
            guard let rango = linea.range(of: "\"rate_limits\":") else { continue }
            // Aísla el objeto rate_limits contando llaves.
            var nivel = 0
            var fin = rango.upperBound
            for i in linea[rango.upperBound...].indices {
                let c = linea[i]
                if c == "{" { nivel += 1 } else if c == "}" { nivel -= 1; if nivel == 0 { fin = linea.index(after: i); break } }
            }
            guard let datos = String(linea[rango.upperBound..<fin]).data(using: .utf8),
                  let l = try? JSONDecoder().decode(Limites.self, from: datos), let p = l.primary else { continue }
            return CuotaCodex(porcentaje: p.used_percent, reinicio: Date(timeIntervalSince1970: p.resets_at))
        }
        return nil
    }
}

// MARK: Cuota de Claude (de la barra de estado de Claude Code)

public struct VentanaCuota: Equatable, Sendable {
    public let porcentaje: Double
    public let reinicio: Date
}

public struct CuotaClaude: Equatable, Sendable {
    public let cincoHoras: VentanaCuota
    public let semana: VentanaCuota

    public var titulo: String {
        "Claude · \(Int(cincoHoras.porcentaje.rounded())) % (5 h) · \(Int(semana.porcentaje.rounded())) % semana"
    }
}

extension Cuota {
    private struct Barra: Decodable {
        struct Ventana: Decodable { let used_percentage: Double; let resets_at: Double }
        struct Limites: Decodable { let five_hour: Ventana?; let seven_day: Ventana? }
        let rate_limits: Limites?
    }

    /// Lee `rate_limits` del JSON que Claude Code le pasa a su barra de estado.
    public static func leerClaude(_ datos: Data) -> CuotaClaude? {
        guard let b = try? JSONDecoder().decode(Barra.self, from: datos),
              let cinco = b.rate_limits?.five_hour, let semana = b.rate_limits?.seven_day else { return nil }
        func v(_ w: Barra.Ventana) -> VentanaCuota {
            VentanaCuota(porcentaje: w.used_percentage, reinicio: Date(timeIntervalSince1970: w.resets_at))
        }
        return CuotaClaude(cincoHoras: v(cinco), semana: v(semana))
    }
}

// MARK: No molestar

public enum NoMolestar {
    public enum Opcion: Equatable, Sendable { case minutos(Int), hastaManana }

    public static func hasta(_ o: Opcion, ahora: Date, calendario: Calendar = .current) -> Date {
        switch o {
        case .minutos(let m):
            return ahora.addingTimeInterval(TimeInterval(m * 60))
        case .hastaManana:
            let manana = calendario.date(byAdding: .day, value: 1, to: ahora)!
            return calendario.date(bySettingHour: 8, minute: 0, second: 0, of: manana)!
        }
    }

    public static func activo(hasta: Date?, ahora: Date) -> Bool {
        guard let hasta else { return false }
        return ahora < hasta
    }
}

// MARK: Avisos de permiso

public enum Avisos {
    /// Sesiones del usuario que empezaron a pedir permiso desde la última vez (y el conjunto actual que espera).
    public static func permisosNuevos(_ sesiones: [Sesion], yaAvisadas: Set<String>) -> (nuevas: [Sesion], esperando: Set<String>) {
        let esperando = Agregador.delUsuario(sesiones).filter { $0.state == .waiting }
        let ids = Set(esperando.map { "\($0.cli)-\($0.session)" })
        return (esperando.filter { !yaAvisadas.contains("\($0.cli)-\($0.session)") }, ids)
    }
}

// MARK: Caricias

/// Detecta que el usuario «acaricia» a la mascota: vaivén del cursor encima de ella.
public struct Caricia: Sendable {
    public static let cambiosNecesarios = 3
    public static let ventana: TimeInterval = 2
    private var ultimaX: Double?
    private var direccion = 0
    private var cambios: [TimeInterval] = []

    public init() {}

    /// Registra una posición del cursor; devuelve true cuando completa una caricia.
    public mutating func registrar(x: Double, encima: Bool, t: TimeInterval) -> Bool {
        // Fuera de la mascota no cuenta, pero tampoco borra lo acumulado (con el cursor rápido
        // es fácil salirse un instante); la ventana de tiempo descarta lo viejo.
        guard encima else { return false }
        defer { ultimaX = x }
        guard let antes = ultimaX, abs(x - antes) >= 3 else { return false }
        let nueva = x > antes ? 1 : -1
        if direccion != 0, nueva != direccion { cambios.append(t) }
        direccion = nueva
        cambios.removeAll { t - $0 > Self.ventana }
        if cambios.count >= Self.cambiosNecesarios { cambios.removeAll(); return true }
        return false
    }
}

// MARK: Saludo al volver

public enum Saludo {
    public static let ausencia: TimeInterval = 5 * 60

    /// Tras más de 5 min sin tocar mouse ni teclado, el primer movimiento se saluda.
    public static func debeSaludar(inactivoAntes: TimeInterval, inactivoAhora: TimeInterval) -> Bool {
        inactivoAntes >= ausencia && inactivoAhora < 2
    }
}

// MARK: Autodiagnóstico

public enum Diagnostico {
    /// Margen entre lo que escribe Codex en su registro y el último aviso que llegó a la mascota.
    public static let margen: TimeInterval = 120

    /// Codex está trabajando (escribe en su registro, con una terminal abierta) pero sus hooks no avisan
    /// a la mascota: se actualizó y cambió algo, o pide volver a aprobar los hooks.
    public static func codexCallado(ultimoRegistro: Date?, ultimoAviso: Date?, codexAbierto: Bool) -> Bool {
        guard codexAbierto, let registro = ultimoRegistro else { return false }
        guard let aviso = ultimoAviso else { return true }
        return registro.timeIntervalSince(aviso) > margen
    }
}
