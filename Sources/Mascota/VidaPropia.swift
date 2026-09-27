import AppKit
import CoreGraphics
import MascotaCore

/// Lo que hace la mascota cuando nadie trabaja: te mira, pasea, hace travesuras, recibe caricias y
/// te saluda al volver. Solo mueve la ventana en los paseos (ida y vuelta a su casa).
@MainActor
final class VidaPropia {
    private let panel: PanelMascota
    /// Hoja de sprites de la mascota elegida (para saber si trae las 16 miradas).
    private let hoja: () -> HojaSprites?

    private var accion: AccionReposo?
    private var inicioAccion = Date()
    private var proximaAccion = Date().addingTimeInterval(Reposo.espera(.random(in: 0..<1)))
    private var ultimoRaton = NSPoint.zero
    private var ratonMovido = Date.distantPast
    private var caricia = Caricia()
    private var carinoHasta: Date?
    private var inactivoAntes: TimeInterval = 0

    init(panel: PanelMascota, hoja: @escaping () -> HojaSprites?) {
        self.panel = panel
        self.hoja = hoja
    }

    var activa: Bool {
        get { UserDefaults.standard.object(forKey: "vidaPropia") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "vidaPropia")
            if !newValue { terminar(Date()) }
        }
    }

    /// Corta la travesura sin mover la ventana y reinicia la cuenta para la siguiente.
    func cancelar() {
        accion = nil
        proximaAccion = Date().addingTimeInterval(Reposo.espera(.random(in: 0..<1)))
    }

    /// Termina la travesura en curso, regresa a casa y agenda la siguiente.
    func terminar(_ ahora: Date) {
        guard accion != nil else { return }
        accion = nil
        panel.ponerDesplazamiento(0)
        proximaAccion = ahora.addingTimeInterval(Reposo.espera(.random(in: 0..<1)))
    }

    /// Qué mostrar en reposo: animación y tiempo, o una celda fija (mirar).
    /// `desdeReposo`: segundos desde que la mascota quedó en reposo (para la animación idle).
    func cuadro(_ ahora: Date, desdeReposo: TimeInterval) -> (Animacion, TimeInterval, Celda?) {
        let reposo = (Animaciones.idle, desdeReposo, nil as Celda?)
        let puntero = NSEvent.mouseLocation

        // Caricias: vaivén del cursor sobre la mascota → saltito feliz con corazón.
        let encima = panel.rectSprite.insetBy(dx: -25, dy: -25).contains(puntero)
        if caricia.registrar(x: puntero.x, encima: encima, t: ahora.timeIntervalSinceReferenceDate) {
            cancelar()
            carinoHasta = ahora.addingTimeInterval(1.6)
            panel.mostrarCorazon()
        }
        if let h = carinoHasta {
            if ahora < h { return (Animaciones.jumping, 1.6 - h.timeIntervalSince(ahora), nil) }
            carinoHasta = nil
        }

        // Saludo al volver tras un rato sin tocar la Mac.
        let inactivo = Self.segundosInactivo()
        if Saludo.debeSaludar(inactivoAntes: inactivoAntes, inactivoAhora: inactivo) {
            cancelar()
            empezar(.saludar, ahora)
        }
        inactivoAntes = inactivo

        // Te mira si mueves el cursor cerca (solo si no está en medio de una travesura).
        let miradas = hoja()?.tieneMiradas ?? false
        if puntero != ultimoRaton { ultimoRaton = puntero; ratonMovido = ahora }
        if miradas, accion == nil, ahora.timeIntervalSince(ratonMovido) < 2.5 {
            let dx = puntero.x - panel.frame.midX
            let dy = puntero.y - (panel.frame.minY + panel.altoSprite / 2)
            if (dx * dx + dy * dy).squareRoot() < 350, let c = Mirada.celda(dx: dx, dy: dy) {
                return (Animaciones.idle, 0, c)
            }
        }

        if accion == nil, ahora >= proximaAccion {
            let a = Reposo.elegir(.random(in: 0..<1), .random(in: 0..<1))
            empezar(a == .mirarAlrededor && !miradas ? .saludar : a, ahora)
        }
        guard let a = accion else { return reposo }
        let t = ahora.timeIntervalSince(inicioAccion)
        if t >= Reposo.duracion(a) { terminar(ahora); return reposo }
        switch a {
        case .descansar:
            return reposo
        case .saltar:
            return (Animaciones.jumping, t, nil)
        case .saludar:
            return (Animaciones.waving, t, nil)
        case .mirarAlrededor:
            let i = min(15, Int(t / Reposo.cuadroMirada))
            return (Animaciones.idle, 0, Celda(fila: 9 + i / 8, columna: i % 8))
        case .pasear(let dx):
            guard let paso = Reposo.paseo(dx: dx, t: t) else { terminar(ahora); return reposo }
            panel.ponerDesplazamiento(paso.desplazamiento)
            switch paso.fila {
            case 1: return (Animaciones.caminarDerecha, t, nil)
            case 2: return (Animaciones.caminarIzquierda, t, nil)
            default: return reposo
            }
        }
    }

    private func empezar(_ a: AccionReposo, _ ahora: Date) {
        var a = a
        // Si el paseo se saldría de la pantalla, va hacia el otro lado.
        if case .pasear(let dx) = a, let pantalla = panel.screen?.visibleFrame {
            let x = panel.casa.x + dx
            if x < pantalla.minX || x + panel.frame.width > pantalla.maxX { a = .pasear(dx: -dx) }
        }
        accion = a
        inicioAccion = ahora
    }

    private static func segundosInactivo() -> TimeInterval {
        let tipos: [CGEventType] = [.mouseMoved, .keyDown, .leftMouseDown, .scrollWheel]
        return tipos.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }
}
