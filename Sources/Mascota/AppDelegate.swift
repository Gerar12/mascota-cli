import AppKit
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

        let anim = Animaciones.para(estado: estado, desdeCambio: desdeCambio)
        let h = hoja()
        let cuadro = h?.celda(fila: anim.fila, columna: Animaciones.cuadro(anim, tiempo: desdeCambio))
        panel.mostrarCuadro(cuadro, aireSuperior: h?.aireSuperior(fila: anim.fila) ?? 0)

        let mostrarGlobo = principal != nil && (estado == .waiting || estado == .failed || desdeCambio < 6)
        panel.mostrarGlobo(mostrarGlobo ? Textos.chips(sesiones, ahora: ahora) : nil)

        let debe = Agregador.debeMostrarse(sesiones, ahora: ahora) && !ocultoManual
        if debe && !panel.isVisible { panel.orderFrontRegardless() }
        if !debe && panel.isVisible && !ocultoManual && !visibleAlAbrir(ahora) { panel.orderOut(nil) }
    }
}
