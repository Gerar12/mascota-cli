import AppKit
import MascotaCore
import ServiceManagement

/// Menú que se abre al hacer clic en la mascota.
@MainActor
final class MenuMascota: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    /// Elementos de Energía del menú actual, para cambiarlos en vivo si se conecta o desconecta el cargador.
    private var energia: (encabezado: NSMenuItem?, opciones: [NSMenuItem])?

    /// Sin cargador las opciones no se pueden tocar (conservan su ✓ para reactivarse al conectarlo).
    func actualizarEnergia(conCargador: Bool) {
        guard let energia else { return }
        energia.encabezado?.title = Energia.titulo(conCargador: conCargador)
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
        let ahora = Date()
        let hora = DateFormatter()
        hora.dateFormat = "HH:mm"

        // ── De un vistazo ──
        // Sesiones: una línea fija; la lista (que puede crecer mucho) vive en el submenú.
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
        // Tu tarea de hoy en Things (solo si Things está abierto), recortada para no ensanchar el menú.
        app.things.refrescar()
        if let t = app.things.tarea {
            let hoy = submenu("Hoy: \(Self.recortar(t.nombre, 35))", icono: "checklist", [
                accion("Marcar como hecha", #selector(completarTarea), icono: "checkmark.circle"),
                accion("Abrir en Things", #selector(abrirTarea), icono: "arrow.up.forward.app"),
            ])
            hoy.toolTip = t.nombre + (app.things.pendientes > 1 ? " (\(app.things.pendientes) pendientes)" : "")
            menu.addItem(hoy)
        }
        // Cuota en una línea; el detalle de los reinicios, en el submenú.
        let claude = LectorCuotas.claude(), codex = LectorCuotas.codex()
        var partes: [String] = []
        var detalle: [NSMenuItem] = []
        if let c = claude {
            partes.append("Claude \(Int(c.cincoHoras.porcentaje.rounded())) %")
            detalle.append(linea("Claude · \(Int(c.cincoHoras.porcentaje.rounded())) % de 5 h",
                                 "se reinicia a las \(hora.string(from: c.cincoHoras.reinicio))"))
            detalle.append(linea("Claude · \(Int(c.semana.porcentaje.rounded())) % de la semana",
                                 "se reinicia el \(Cuota.fechaCorta(c.semana.reinicio))"))
        }
        if let x = codex {
            partes.append("Codex \(Int(x.porcentaje.rounded())) %")
            detalle.append(linea(x.titulo, x.detalle().replacingOccurrences(of: "Se reinicia", with: "se reinicia")))
        }
        if !partes.isEmpty {
            menu.addItem(submenu("Cuota · " + partes.joined(separator: " · "), icono: "gauge.with.dots.needle.33percent", detalle))
        }

        // ── Lo del día a día ──
        menu.addItem(.separator())
        if ControlVoz.disponible {
            let leer = accion("Leer respuestas", #selector(alternarVoz), icono: "speaker.wave.2")
            leer.state = ControlVoz.silenciada ? .off : .on
            menu.addItem(leer)
        }
        let titulo = app.noMolestar ? "No molestar · hasta las \(hora.string(from: app.noMolestarHasta!))" : "No molestar"
        var opciones = [
            opcionNoMolestar("30 minutos", .minutos(30)),
            opcionNoMolestar("1 hora", .minutos(60)),
            opcionNoMolestar("Hasta mañana (8:00)", .hastaManana),
        ]
        if app.noMolestar { opciones.append(accion("Desactivar", #selector(desactivarNoMolestar), icono: "bell")) }
        let nm = submenu(titulo, icono: app.noMolestar ? "moon.fill" : "moon", opciones)
        nm.state = app.noMolestar ? .on : .off
        menu.addItem(nm)
        let trabajo = accion("Despierta mientras trabajan", #selector(alternarEnergiaTrabajo), icono: "cup.and.saucer")
        trabajo.state = app.despiertaMientrasTrabajan ? .on : .off
        trabajo.toolTip = "Con el cargador conectado, la Mac no entra en reposo mientras Claude o Codex trabajan (y 15 min después). La pantalla sí se apaga."
        menu.addItem(trabajo)

        // ── Todo lo demás ──
        menu.addItem(.separator())
        var mas: [NSMenuItem] = []
        if ControlVoz.disponible {
            let sinCreditos = ControlVoz.elevenSinCreditos
            mas.append(.sectionHeader(title: "Voz"))
            mas.append(submenu("Voz de lectura", icono: "waveform", Voz.proveedores.map { p in
                let nombre = p.id == "eleven" && sinCreditos ? "\(p.nombre) · sin créditos" : p.nombre
                let it = accion(nombre, #selector(elegirVoz(_:)))
                it.representedObject = p.id
                it.state = ControlVoz.proveedor == p.id ? .on : .off
                return it
            }))
            mas.append(accion("Repetir lo último", #selector(repetir), icono: "arrow.counterclockwise"))
            mas.append(accion("Callar ahora", #selector(callar), icono: "stop.fill"))
            mas.append(.separator())
        }
        mas.append(.sectionHeader(title: "Apariencia"))
        mas.append(submenu("Mascota", icono: "pawprint", app.catalogo.map { m in
            let it = accion(m.nombre, #selector(elegirMascota(_:)))
            it.representedObject = m.id
            it.state = app.mascotaId == m.id ? .on : .off
            return it
        }))
        mas.append(submenu("Tamaño", icono: "arrow.up.left.and.arrow.down.right", PanelMascota.tamanos.map { t in
            let it = accion(t.nombre, #selector(elegirTamano(_:)))
            it.representedObject = t.ancho
            it.state = app.panel.anchoSprite == t.ancho ? .on : .off
            return it
        }))
        let vida = accion("Vida propia", #selector(alternarVida), icono: "sparkles")
        vida.state = app.vidaPropia ? .on : .off
        vida.toolTip = "Cuando nadie trabaja: te mira, pasea un poquito y hace travesuras."
        mas.append(vida)
        mas.append(accion("Ocultar mascota", #selector(ocultar), icono: "eye.slash"))
        mas.append(.separator())
        mas.append(.sectionHeader(title: "Mac"))
        let siempre = accion("Despierta siempre", #selector(alternarEnergiaSiempre), icono: "moon.stars")
        siempre.state = app.despiertaSiempre ? .on : .off
        siempre.toolTip = "Con el cargador conectado, la Mac no entra en reposo hasta que lo apagues. Con batería no hace nada. La pantalla sí se apaga; cerrar la tapa la duerme igual."
        mas.append(siempre)
        let login = accion("Abrir al iniciar sesión", #selector(alternarLogin), icono: "power")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        mas.append(login)
        let raizMas = submenu("Más", icono: "ellipsis.circle", mas)
        raizMas.submenu?.autoenablesItems = false
        menu.addItem(raizMas)

        energia = (nil, [trabajo, siempre])
        actualizarEnergia(conCargador: app.conCargador)

        let salir = accion("Salir de Mascota", #selector(salir))
        salir.keyEquivalent = "q"
        menu.addItem(salir)
    }

    /// Línea informativa con subtítulo (macOS 14.4+) o todo junto.
    private func linea(_ titulo: String, _ detalle: String) -> NSMenuItem {
        let it = accion(titulo, #selector(nada))
        if #available(macOS 14.4, *) { it.subtitle = detalle } else { it.title = "\(titulo) — \(detalle)" }
        return it
    }

    private static func recortar(_ texto: String, _ largo: Int) -> String {
        texto.count <= largo ? texto : String(texto.prefix(largo - 1)).trimmingCharacters(in: .whitespaces) + "…"
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

    private func opcionNoMolestar(_ titulo: String, _ o: NoMolestar.Opcion) -> NSMenuItem {
        let it = accion(titulo, #selector(activarNoMolestar(_:)))
        it.representedObject = CajaOpcion(o)
        return it
    }

    @objc private func activarNoMolestar(_ it: NSMenuItem) {
        guard let caja = it.representedObject as? CajaOpcion else { return }
        app?.activarNoMolestar(caja.opcion)
    }

    @objc private func desactivarNoMolestar() { app?.desactivarNoMolestar() }

    @objc private func completarTarea() { app?.things.completar() }

    @objc private func abrirTarea() { app?.things.abrir() }

    @objc private func nada() {}

    @objc private func alternarLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { NSLog("Mascota: no pude cambiar el inicio de sesión: \(error)") }
    }

    @objc private func salir() { NSApp.terminate(nil) }
}

/// Envoltorio para guardar una opción de No molestar en `representedObject`.
private final class CajaOpcion: NSObject {
    let opcion: NoMolestar.Opcion
    init(_ o: NoMolestar.Opcion) { opcion = o }
}
