import AppKit
import MascotaCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let panel = PanelMascota()
    let menu = MenuBarra()
    private(set) var sesiones: [Sesion] = []
    private(set) var catalogo: [MascotaDef] = []
    private var hojas: [String: HojaSprites] = [:]
    private var ultimaFirma = ""
    private var cambio = Date.distantPast
    private var ocultoManual = false
    private var ultimoSondeo = Date.distantPast

    private let raiz = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".mascota")

    func applicationDidFinishLaunching(_ n: Notification) {
        menu.app = self
        catalogo = CatalogoMascotas.cargar(directorios: [
            raiz.appendingPathComponent("mascotas"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/pets"),
        ])
        Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    func mascotaId(_ cli: String) -> String {
        UserDefaults.standard.string(forKey: "mascota.\(cli)") ?? "null-signal"
    }

    func elegirMascota(cli: String, id: String) {
        UserDefaults.standard.set(id, forKey: "mascota.\(cli)")
    }

    func alternarPanelManual() {
        ocultoManual = panel.isVisible
        if ocultoManual { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    private func hoja(_ cli: String) -> HojaSprites? {
        let id = mascotaId(cli)
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
            sesiones = LectorEstado.leer(directorio: raiz.appendingPathComponent("estado"))
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
        let cuadro = hoja(principal?.cli ?? "claude")?
            .celda(fila: anim.fila, columna: Animaciones.cuadro(anim, tiempo: desdeCambio))
        panel.mostrarCuadro(cuadro)
        menu.mostrarCuadro(cuadro)

        let mostrarGlobo = principal != nil && (estado == .waiting || estado == .failed || desdeCambio < 6)
        panel.mostrarGlobo(mostrarGlobo ? principal.map { Textos.globo($0, estado: estado!) } : nil)

        let debe = Agregador.debeMostrarse(sesiones, ahora: ahora) && !ocultoManual
        if debe && !panel.isVisible { panel.orderFrontRegardless() }
        if !debe && panel.isVisible && !ocultoManual { panel.orderOut(nil) }
    }
}
