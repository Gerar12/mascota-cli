import AppKit
import MascotaCore

/// Conecta las piezas: lee las sesiones, decide qué animación mostrar y deja a cada controlador lo suyo
/// (energía, avisos, vida propia). Corre un reloj a 20 cuadros por segundo.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let panel = PanelMascota()
    let menu = MenuMascota()
    let energia = ControlEnergia()
    let avisos = ControlAvisos()
    private(set) lazy var vida = VidaPropia(panel: panel) { [unowned self] in self.hoja() }
    private(set) var catalogo: [MascotaDef] = []

    private let raiz = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".mascota")
    private lazy var sondeo = SondeoSesiones(raiz: raiz)
    var sesiones: [Sesion] { sondeo.sesiones }
    var codexCallado: Bool { sondeo.codexCallado }

    private var hojas: [String: HojaSprites] = [:]
    private var ultimaFirma = ""
    private var cambio = Date.distantPast
    private var ocultoManual = false
    private var ultimoSondeo = Date.distantPast
    private let abierta = Date()

    func applicationDidFinishLaunching(_ n: Notification) {
        menu.app = self
        panel.sprite.alHacerClic = { [weak self] evento in
            guard let self else { return }
            NSMenu.popUpContextMenu(self.menu.menu, with: evento, for: self.panel.sprite)
        }
        // Al agarrarla se corta la travesura (sin regresarla) para que nada la mueva durante el arrastre;
        // al soltarla en otro lugar, el panel ya guardó esa casa nueva.
        panel.sprite.alPresionar = { [weak self] in
            self?.vida.cancelar()
            self?.panel.guardarCasa()     // si iba a medio paseo, se queda donde lo agarraste
        }
        panel.alMoverUsuario = { [weak self] in self?.vida.cancelar() }
        energia.alCambiarCargador = { [weak self] cargador in self?.menu.actualizarEnergia(conCargador: cargador) }
        avisos.avisador.alTocar = { [weak self] clave in
            guard let s = self?.sesiones.first(where: { "\($0.cli)-\($0.session)" == clave }) else { return }
            EnfocarTerminal.ir(a: s)
        }
        avisos.avisador.pedirPermiso()
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

    /// Abrir la app de nuevo (Finder, Spotlight u `open`) vuelve a mostrar la mascota.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        ocultoManual = false
        panel.orderFrontRegardless()
        return false
    }

    // MARK: Preferencias que usa el menú

    var mascotaId: String { UserDefaults.standard.string(forKey: "mascota") ?? "null-signal" }

    func elegirMascota(_ id: String) { UserDefaults.standard.set(id, forKey: "mascota") }

    func cambiarTamano(_ ancho: CGFloat) {
        vida.terminar(Date())
        panel.cambiarTamano(ancho)
    }

    func ocultarManual() {
        ocultoManual = true
        panel.orderOut(nil)
    }

    // MARK: Reloj

    private func hoja() -> HojaSprites? {
        let id = mascotaId
        if let h = hojas[id] { return h }
        guard let def = catalogo.first(where: { $0.id == id }) ?? catalogo.first,
              let h = HojaSprites(url: def.hoja) else { return nil }
        hojas = [id: h]          // solo la mascota elegida en memoria
        return h
    }

    /// Al abrir la app se muestra unos segundos aunque no haya sesiones, para saber que está corriendo.
    private func visibleAlAbrir(_ ahora: Date) -> Bool { ahora.timeIntervalSince(abierta) < 10 }

    private func tick() {
        let ahora = Date()
        if ahora.timeIntervalSince(ultimoSondeo) >= 0.5 {
            ultimoSondeo = ahora
            sondeo.actualizar(ahora)
            energia.actualizar(sesiones, ahora: ahora)
            avisos.revisar(sesiones, ahora: ahora,
                           pose: hoja()?.celda(fila: Animaciones.waiting.fila, columna: 0))   // pidiendo permiso
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
        if enReposo && vida.activa {
            (anim, tiempo, fija) = vida.cuadro(ahora, desdeReposo: desdeCambio)
        } else {
            vida.terminar(ahora)          // a trabajar: deja la travesura y vuelve a casa
        }
        let h = hoja()
        let celda = fija ?? Celda(fila: anim.fila, columna: Animaciones.cuadro(anim, tiempo: tiempo))
        panel.mostrarCuadro(h?.celda(fila: celda.fila, columna: celda.columna),
                            aireSuperior: h?.aireSuperior(fila: anim.fila) ?? 0)

        let mostrarGlobo = !avisos.noMolestar && principal != nil
            && (estado == .waiting || estado == .failed || desdeCambio < 6)
        panel.mostrarGlobo(mostrarGlobo ? Textos.chips(sesiones, ahora: ahora) : nil)

        let debe = Agregador.debeMostrarse(sesiones, ahora: ahora) && !ocultoManual
        if debe && !panel.isVisible { panel.orderFrontRegardless() }
        if !debe && panel.isVisible && !ocultoManual && !visibleAlAbrir(ahora) { panel.orderOut(nil) }
    }
}
