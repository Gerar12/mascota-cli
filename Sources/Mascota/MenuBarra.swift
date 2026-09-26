import AppKit
import MascotaCore
import ServiceManagement

/// Ícono animado en la barra de menú y su menú.
@MainActor
final class MenuBarra: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    weak var app: AppDelegate?

    override init() {
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func mostrarCuadro(_ imagen: CGImage?) {
        guard let imagen else { return }
        item.button?.image = NSImage(cgImage: imagen, size: NSSize(width: 17, height: 18))
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let app else { return }
        menu.removeAllItems()
        let visible = app.panel.isVisible
        menu.addItem(accion(visible ? "Ocultar mascota" : "Mostrar mascota", #selector(alternarPanel)))
        menu.addItem(.separator())

        let ahora = Date()
        let sesiones = Agregador.vigentes(app.sesiones, ahora: ahora)
        if sesiones.isEmpty {
            menu.addItem(NSMenuItem(title: "Sin sesiones activas", action: nil, keyEquivalent: ""))
        }
        for s in sesiones.sorted(by: { $0.ts > $1.ts }) {
            menu.addItem(NSMenuItem(title: Textos.globo(s, estado: Agregador.estadoEfectivo(s, ahora: ahora)),
                                    action: nil, keyEquivalent: ""))
        }
        menu.addItem(.separator())
        for cli in ["claude", "codex"] {
            let sub = NSMenu()
            for m in app.catalogo {
                let it = accion(m.nombre, #selector(elegirMascota(_:)))
                it.representedObject = [cli, m.id]
                it.state = app.mascotaId(cli) == m.id ? .on : .off
                sub.addItem(it)
            }
            let raiz = NSMenuItem(title: "Mascota de \(cli == "codex" ? "Codex" : "Claude")", action: nil, keyEquivalent: "")
            raiz.submenu = sub
            menu.addItem(raiz)
        }
        let login = accion("Abrir al iniciar sesión", #selector(alternarLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(accion("Salir", #selector(salir)))
    }

    private func accion(_ titulo: String, _ sel: Selector) -> NSMenuItem {
        let it = NSMenuItem(title: titulo, action: sel, keyEquivalent: "")
        it.target = self
        return it
    }

    @objc private func alternarPanel() { app?.alternarPanelManual() }

    @objc private func elegirMascota(_ it: NSMenuItem) {
        guard let par = it.representedObject as? [String] else { return }
        app?.elegirMascota(cli: par[0], id: par[1])
    }

    @objc private func alternarLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { NSLog("Mascota: no pude cambiar el inicio de sesión: \(error)") }
    }

    @objc private func salir() { NSApp.terminate(nil) }
}
