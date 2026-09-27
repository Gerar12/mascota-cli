import AppKit
import MascotaCore
import ServiceManagement

/// Menú que se abre al hacer clic en la mascota.
@MainActor
final class MenuMascota: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    /// Elementos de Energía del menú actual, para cambiarlos en vivo si se conecta o desconecta el cargador.
    private var energia: (encabezado: NSMenuItem, opciones: [NSMenuItem])?

    /// Sin cargador las opciones no se pueden tocar (conservan su ✓ para reactivarse al conectarlo).
    func actualizarEnergia(conCargador: Bool) {
        guard let energia else { return }
        energia.encabezado.title = Energia.titulo(conCargador: conCargador)
        for it in energia.opciones {
            it.isEnabled = conCargador
            if #available(macOS 14.4, *) { it.subtitle = conCargador ? nil : "Conecta el cargador para usarlo" }
        }
    }
    weak var app: AppDelegate?

    override init() {
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false      // para poder deshabilitar las opciones de energía sin cargador
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let app else { return }
        menu.removeAllItems()

        // Una sola línea fija; la lista (que puede crecer mucho) vive en el submenú.
        let ahora = Date()
        // Solo las terminales del usuario: los encargos automáticos se ven en el globo, no aquí.
        let sesiones = Agregador.delUsuario(Agregador.vigentes(app.sesiones, ahora: ahora))
            .sorted { ($0.cli, $1.ts) < ($1.cli, $0.ts) }
        if sesiones.isEmpty {
            menu.addItem(accion("Sin sesiones abiertas", nil, icono: "moon.zzz"))
        } else {
            menu.addItem(submenu("Sesiones · \(sesiones.count)", icono: "terminal", sesiones.map { s in
                let estado = Agregador.estadoEfectivo(s, ahora: ahora)
                let it = accion(s.project, #selector(irASesion(_:)), icono: Self.iconoEstado(estado))
                it.representedObject = s
                let detalle = "\(s.nombreCLI) · \(Textos.verbo(estado))"
                if #available(macOS 14.4, *) { it.subtitle = detalle } else { it.title = "\(s.project) — \(detalle)" }
                return it
            }))
        }

        if ControlVoz.disponible {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: "Voz"))
            let leer = accion("Leer respuestas", #selector(alternarVoz), icono: "speaker.wave.2")
            leer.state = ControlVoz.silenciada ? .off : .on
            menu.addItem(leer)
            let sinCreditos = ControlVoz.elevenSinCreditos
            menu.addItem(submenu("Voz", icono: "waveform", Voz.proveedores.map { p in
                let nombre = p.id == "eleven" && sinCreditos ? "\(p.nombre) · sin créditos" : p.nombre
                let it = accion(nombre, #selector(elegirVoz(_:)))
                it.representedObject = p.id
                it.state = ControlVoz.proveedor == p.id ? .on : .off
                return it
            }))
            menu.addItem(accion("Repetir lo último", #selector(repetir), icono: "arrow.counterclockwise"))
            menu.addItem(accion("Callar ahora", #selector(callar), icono: "stop.fill"))
        }

        menu.addItem(.separator())
        let encabezado = NSMenuItem.sectionHeader(title: "Energía")
        menu.addItem(encabezado)
        let trabajo = accion("Despierta mientras trabajan", #selector(alternarEnergiaTrabajo), icono: "cup.and.saucer")
        trabajo.state = app.despiertaMientrasTrabajan ? .on : .off
        trabajo.toolTip = "Con el cargador conectado, la Mac no entra en reposo mientras Claude o Codex trabajan (y 15 min después). La pantalla sí se apaga."
        menu.addItem(trabajo)
        let siempre = accion("Despierta siempre", #selector(alternarEnergiaSiempre), icono: "moon.stars")
        siempre.state = app.despiertaSiempre ? .on : .off
        siempre.toolTip = "Con el cargador conectado, la Mac no entra en reposo hasta que lo apagues. Con batería no hace nada. La pantalla sí se apaga; cerrar la tapa la duerme igual."
        menu.addItem(siempre)
        energia = (encabezado, [trabajo, siempre])
        actualizarEnergia(conCargador: app.conCargador)

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Apariencia"))
        menu.addItem(submenu("Mascota", icono: "pawprint", app.catalogo.map { m in
            let it = accion(m.nombre, #selector(elegirMascota(_:)))
            it.representedObject = m.id
            it.state = app.mascotaId == m.id ? .on : .off
            return it
        }))
        menu.addItem(submenu("Tamaño", icono: "arrow.up.left.and.arrow.down.right", PanelMascota.tamanos.map { t in
            let it = accion(t.nombre, #selector(elegirTamano(_:)))
            it.representedObject = t.ancho
            it.state = app.panel.anchoSprite == t.ancho ? .on : .off
            return it
        }))
        let vida = accion("Vida propia", #selector(alternarVida), icono: "sparkles")
        vida.state = app.vidaPropia ? .on : .off
        vida.toolTip = "Cuando nadie trabaja: te mira, pasea un poquito y hace travesuras."
        menu.addItem(vida)
        menu.addItem(accion("Ocultar mascota", #selector(ocultar), icono: "eye.slash"))

        menu.addItem(.separator())
        let login = accion("Abrir al iniciar sesión", #selector(alternarLogin), icono: "power")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        let salir = accion("Salir de Mascota", #selector(salir))
        salir.keyEquivalent = "q"
        menu.addItem(salir)
    }

    private static func iconoEstado(_ e: EstadoAgente) -> String {
        switch e {
        case .running: "ellipsis.circle"
        case .waiting: "hand.raised"
        case .done: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        }
    }

    private func submenu(_ titulo: String, icono: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let raiz = NSMenuItem(title: titulo, action: nil, keyEquivalent: "")
        raiz.image = NSImage(systemSymbolName: icono, accessibilityDescription: nil)
        let sub = NSMenu()
        items.forEach(sub.addItem)
        raiz.submenu = sub
        return raiz
    }

    @objc private func irASesion(_ it: NSMenuItem) {
        guard let s = it.representedObject as? Sesion else { return }
        EnfocarTerminal.ir(a: s)
    }

    private func accion(_ titulo: String, _ sel: Selector?, icono: String? = nil) -> NSMenuItem {
        let it = NSMenuItem(title: titulo, action: sel, keyEquivalent: "")
        it.target = self
        if let icono { it.image = NSImage(systemSymbolName: icono, accessibilityDescription: nil) }
        return it
    }

    @objc private func ocultar() { app?.ocultarManual() }

    @objc private func elegirMascota(_ it: NSMenuItem) {
        guard let id = it.representedObject as? String else { return }
        app?.elegirMascota(id)
    }

    @objc private func elegirTamano(_ it: NSMenuItem) {
        guard let ancho = it.representedObject as? CGFloat else { return }
        app?.cambiarTamano(ancho)
    }

    @objc private func alternarVoz() { ControlVoz.silenciar(!ControlVoz.silenciada) }

    @objc private func elegirVoz(_ it: NSMenuItem) {
        guard let id = it.representedObject as? String else { return }
        ControlVoz.elegir(proveedor: id)
    }

    @objc private func repetir() { ControlVoz.repetirUltimo() }

    @objc private func callar() { ControlVoz.callar() }

    @objc private func alternarEnergiaTrabajo() { app?.despiertaMientrasTrabajan.toggle() }

    @objc private func alternarEnergiaSiempre() { app?.despiertaSiempre.toggle() }

    @objc private func alternarVida() { app?.vidaPropia.toggle() }

    @objc private func alternarLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { NSLog("Mascota: no pude cambiar el inicio de sesión: \(error)") }
    }

    @objc private func salir() { NSApp.terminate(nil) }
}
