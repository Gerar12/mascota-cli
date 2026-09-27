import AppKit
import CoreGraphics
import IOKit.ps
import IOKit.pwr_mgt
import MascotaCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let panel = PanelMascota()
    let menu = MenuMascota()
    private(set) var sesiones: [Sesion] = []
    private(set) var catalogo: [MascotaDef] = []
    private var hojas: [String: HojaSprites] = [:]
    private var ultimaFirma = ""
    private var cambio = Date.distantPast
    private var ocultoManual = false
    private var ultimoSondeo = Date.distantPast

    private var ultimoPs = (cuando: Date.distantPast, codex: false)

    /// ¿Hay alguna terminal con Codex? (proceso `codex` con terminal; el servicio de fondo no tiene).
    /// Se consulta cada 2 s porque lanza `ps`.
    private func codexAbierto(_ ahora: Date) -> Bool {
        guard ahora.timeIntervalSince(ultimoPs.cuando) >= 2 else { return ultimoPs.codex }
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axo", "tty=,comm="]
        let salida = Pipe()
        ps.standardOutput = salida
        if (try? ps.run()) != nil {
            let texto = String(decoding: salida.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            ps.waitUntilExit()
            ultimoPs = (ahora, Procesos.hayCodexConTerminal(salidaPs: texto))
        }
        return ultimoPs.codex
    }

    // Energía: automático mientras trabajan y manual «siempre»; los dos SOLO con cargador (macOS ignora
    // PreventSystemSleep con batería).
    private let vigiliaTrabajo = Vigilia(tipo: kIOPMAssertionTypePreventSystemSleep,
                                         motivo: "Mascota: Claude o Codex están trabajando")
    private let vigiliaSiempre = Vigilia(tipo: kIOPMAssertionTypePreventSystemSleep,
                                         motivo: "Mascota: mantener despierta siempre")
    private var ultimaVezTrabajando: Date?
    private var ultimoCargador: Bool?

    var despiertaMientrasTrabajan: Bool {
        get { UserDefaults.standard.object(forKey: "energia.trabajo") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "energia.trabajo") }
    }
    var despiertaSiempre: Bool {
        get { UserDefaults.standard.bool(forKey: "energia.siempre") }
        set { UserDefaults.standard.set(newValue, forKey: "energia.siempre") }
    }

    /// ¿La Mac está conectada al cargador? Se consulta en cada sondeo: cambia en tiempo real.
    var conCargador: Bool {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let fuente = IOPSGetProvidingPowerSourceType(info).takeUnretainedValue() as String
        return fuente == kIOPMACPowerKey
    }

    private func actualizarEnergia(_ ahora: Date) {
        let trabajando = Energia.hayTrabajo(sesiones, ahora: ahora)
        if trabajando { ultimaVezTrabajando = ahora }
        let cargador = conCargador
        if cargador != ultimoCargador {
            ultimoCargador = cargador
            menu.actualizarEnergia(conCargador: cargador)     // también con el menú abierto
        }
        vigiliaTrabajo.poner(Energia.activa(preferencia: despiertaMientrasTrabajan, conCargador: cargador)
            && Energia.mantenerDespierta(trabajando: trabajando, ultimaVezTrabajando: ultimaVezTrabajando, ahora: ahora))
        vigiliaSiempre.poner(Energia.activa(preferencia: despiertaSiempre, conCargador: cargador))
    }

    // MARK: Vida propia (cuando nadie trabaja)

    var vidaPropia: Bool {
        get { UserDefaults.standard.object(forKey: "vidaPropia") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "vidaPropia")
            if !newValue { terminarAccion(Date()) }
        }
    }
    private var accion: AccionReposo?
    private var inicioAccion = Date()
    private var proximaAccion = Date().addingTimeInterval(Reposo.espera(.random(in: 0..<1)))
    private var ultimoRaton = NSPoint.zero
    private var ratonMovido = Date.distantPast

    func cambiarTamano(_ ancho: CGFloat) {
        terminarAccion(Date())
        panel.cambiarTamano(ancho)
    }

    /// Corta la travesura sin mover la ventana y reinicia la cuenta para la siguiente.
    private func cancelarAccion() {
        accion = nil
        proximaAccion = Date().addingTimeInterval(Reposo.espera(.random(in: 0..<1)))
    }

    /// Termina la travesura en curso, regresa a casa y agenda la siguiente.
    private func terminarAccion(_ ahora: Date) {
        guard accion != nil else { return }
        accion = nil
        panel.ponerDesplazamiento(0)
        proximaAccion = ahora.addingTimeInterval(Reposo.espera(.random(in: 0..<1)))
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

    /// Qué mostrar en reposo: animación y tiempo, o una celda fija (mirar).
    private func vida(_ ahora: Date) -> (Animacion, TimeInterval, Celda?) {
        let reposo = (Animaciones.idle, ahora.timeIntervalSince(cambio), nil as Celda?)
        // Caricias: vaivén del cursor sobre la mascota → saltito feliz con corazón.
        let puntero = NSEvent.mouseLocation
        if caricia.registrar(x: puntero.x, encima: panel.rectSprite.contains(puntero), t: ahora.timeIntervalSinceReferenceDate) {
            cancelarAccion()
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
            cancelarAccion()
            empezar(.saludar, ahora)
        }
        inactivoAntes = inactivo
        // Te mira si mueves el cursor cerca (solo si no está en medio de una travesura).
        let miradas = hoja()?.tieneMiradas ?? false
        let raton = NSEvent.mouseLocation
        if raton != ultimoRaton { ultimoRaton = raton; ratonMovido = ahora }
        if miradas, accion == nil, ahora.timeIntervalSince(ratonMovido) < 2.5 {
            let dx = raton.x - panel.frame.midX
            let dy = raton.y - (panel.frame.minY + panel.altoSprite / 2)
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
        if t >= Reposo.duracion(a) { terminarAccion(ahora); return reposo }
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
            guard let paso = Reposo.paseo(dx: dx, t: t) else { terminarAccion(ahora); return reposo }
            panel.ponerDesplazamiento(paso.desplazamiento)
            switch paso.fila {
            case 1: return (Animaciones.caminarDerecha, t, nil)
            case 2: return (Animaciones.caminarIzquierda, t, nil)
            default: return reposo
            }
        }
    }

    // MARK: Avisos, No molestar, Things, caricias y saludo

    let avisador = Avisador()
    let things = ThingsHoy()
    private var avisadas: Set<String> = []
    private var ultimoThings = Date()
    private var caricia = Caricia()
    private var carinoHasta: Date?
    private var inactivoAntes: TimeInterval = 0

    var noMolestarHasta: Date? {
        get { UserDefaults.standard.object(forKey: "noMolestarHasta") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "noMolestarHasta") }
    }
    var noMolestar: Bool { NoMolestar.activo(hasta: noMolestarHasta, ahora: Date()) }

    /// Activa No molestar: calla la voz (si estaba activa, se reactiva al terminar) y esconde el globo.
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

    /// Notifica los permisos nuevos (si no estás ya en la terminal ni en No molestar).
    private func revisarAvisos() {
        let (nuevas, esperando) = Avisos.permisosNuevos(sesiones, yaAvisadas: avisadas)
        avisador.retirar(Array(avisadas.subtracting(esperando)))
        avisadas = esperando
        let enTerminal = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.mitchellh.ghostty"
        guard !noMolestar, !enTerminal else { return }
        nuevas.forEach(avisador.avisar)
    }

    private static func segundosInactivo() -> TimeInterval {
        let tipos: [CGEventType] = [.mouseMoved, .keyDown, .leftMouseDown, .scrollWheel]
        return tipos.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    private let abierta = Date()
    /// Al abrir la app se muestra unos segundos aunque no haya sesiones, para saber que está corriendo.
    private func visibleAlAbrir(_ ahora: Date) -> Bool { ahora.timeIntervalSince(abierta) < 10 }

    private let raiz = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".mascota")

    func applicationDidFinishLaunching(_ n: Notification) {
        menu.app = self
        panel.sprite.alHacerClic = { [weak self] evento in
            guard let self else { return }
            NSMenu.popUpContextMenu(self.menu.menu, with: evento, for: self.panel.sprite)
        }
        // Al agarrarla se corta la travesura (sin regresarla) para que nada la mueva durante el arrastre;
        // al soltarla en otro lugar, el panel ya guardó esa casa nueva.
        panel.sprite.alPresionar = { [weak self] in
            self?.cancelarAccion()
            self?.panel.guardarCasa()     // si iba a medio paseo, se queda donde lo agarraste
        }
        panel.alMoverUsuario = { [weak self] in self?.cancelarAccion() }
        avisador.alTocar = { [weak self] clave in
            guard let s = self?.sesiones.first(where: { "\($0.cli)-\($0.session)" == clave }) else { return }
            EnfocarTerminal.ir(a: s)
        }
        avisador.pedirPermiso()
        things.refrescar()
        catalogo = CatalogoMascotas.cargar(directorios: [
            raiz.appendingPathComponent("mascotas"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/pets"),
        ])
        // En modo .common el reloj sigue con el menú abierto (si no, macOS lo pausa).
        let reloj = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(reloj, forMode: .common)
        panel.orderFrontRegardless()
        tick()
    }

    var mascotaId: String {
        UserDefaults.standard.string(forKey: "mascota") ?? "null-signal"
    }

    func elegirMascota(_ id: String) {
        UserDefaults.standard.set(id, forKey: "mascota")
    }

    func ocultarManual() {
        ocultoManual = true
        panel.orderOut(nil)
    }

    /// Abrir la app de nuevo (Finder, Spotlight u `open`) vuelve a mostrar la mascota.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        ocultoManual = false
        panel.orderFrontRegardless()
        return false
    }

    private func hoja() -> HojaSprites? {
        let id = mascotaId
        if let h = hojas[id] { return h }
        guard let def = catalogo.first(where: { $0.id == id }) ?? catalogo.first,
              let h = HojaSprites(url: def.hoja) else { return nil }
        hojas[id] = h
        return h
    }

    private func tick() {
        let ahora = Date()
        if ahora.timeIntervalSince(ultimoSondeo) >= 0.5 {
            ultimoSondeo = ahora
            let dir = raiz.appendingPathComponent("estado")
            // Terminal cerrada sin SessionEnd: el proceso ya no existe, se olvida la sesión.
            let (vivas, muertas) = Agregador.separarPorProceso(LectorEstado.leer(directorio: dir),
                                                               codexAbierto: codexAbierto(ahora)) { pid in
                kill(pid, 0) == 0 || errno == EPERM
            }
            for s in muertas {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(s.cli)-\(s.session).json"))
            }
            sesiones = vivas
            actualizarEnergia(ahora)
            revisarAvisos()
            if let h = noMolestarHasta, ahora >= h { desactivarNoMolestar() }
            if ahora.timeIntervalSince(ultimoThings) >= 60 { ultimoThings = ahora; things.refrescar() }
        }
        let principal = Agregador.principal(sesiones, ahora: ahora)
        let estado = principal.map { Agregador.estadoEfectivo($0, ahora: ahora) }

        let firma = principal.map { "\($0.cli)-\($0.session)-\(estado!.rawValue)-\($0.ts)" } ?? ""
        if firma != ultimaFirma {
            ultimaFirma = firma
            cambio = ahora
            if principal != nil { ocultoManual = false }
        }
        let desdeCambio = ahora.timeIntervalSince(cambio)

        var anim = Animaciones.para(estado: estado, desdeCambio: desdeCambio)
        var tiempo = desdeCambio
        var fija: Celda?
        let enReposo = estado == nil || (estado == .done && desdeCambio >= Animaciones.waving.total * 2)
        if enReposo && vidaPropia {
            (anim, tiempo, fija) = vida(ahora)
        } else {
            terminarAccion(ahora)          // a trabajar: deja la travesura y vuelve a casa
        }
        let h = hoja()
        let celda = fija ?? Celda(fila: anim.fila, columna: Animaciones.cuadro(anim, tiempo: tiempo))
        panel.mostrarCuadro(h?.celda(fila: celda.fila, columna: celda.columna),
                            aireSuperior: h?.aireSuperior(fila: anim.fila) ?? 0)

        let mostrarGlobo = !noMolestar && principal != nil && (estado == .waiting || estado == .failed || desdeCambio < 6)
        panel.mostrarGlobo(mostrarGlobo ? Textos.chips(sesiones, ahora: ahora) : nil)

        let debe = Agregador.debeMostrarse(sesiones, ahora: ahora) && !ocultoManual
        if debe && !panel.isVisible { panel.orderFrontRegardless() }
        if !debe && panel.isVisible && !ocultoManual && !visibleAlAbrir(ahora) { panel.orderOut(nil) }
    }
}
