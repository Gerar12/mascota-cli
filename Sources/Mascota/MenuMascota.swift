import AppKit
import MascotaCore
import ServiceManagement

/// Menú que se abre al hacer clic en la mascota.
@MainActor
final class MenuMascota: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    weak var app: AppDelegate?

    override init() {
        super.init()
        menu.delegate = self
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let app else { return }
        menu.removeAllItems()
        menu.addItem(accion("Ocultar mascota", #selector(ocultar)))
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
        let sub = NSMenu()
        for m in app.catalogo {
            let it = accion(m.nombre, #selector(elegirMascota(_:)))
            it.representedObject = m.id
            it.state = app.mascotaId == m.id ? .on : .off
            sub.addItem(it)
        }
        let raiz = NSMenuItem(title: "Mascota", action: nil, keyEquivalent: "")
        raiz.submenu = sub
        menu.addItem(raiz)
        let tam = NSMenu()
        for (nombre, ancho) in PanelMascota.tamanos {
            let it = accion(nombre, #selector(elegirTamano(_:)))
            it.representedObject = ancho
            it.state = app.panel.anchoSprite == ancho ? .on : .off
            tam.addItem(it)
        }
        let raizTam = NSMenuItem(title: "Tamaño", action: nil, keyEquivalent: "")
        raizTam.submenu = tam
        menu.addItem(raizTam)
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

    @objc private func ocultar() { app?.ocultarManual() }

    @objc private func elegirMascota(_ it: NSMenuItem) {
        guard let id = it.representedObject as? String else { return }
        app?.elegirMascota(id)
    }

    @objc private func elegirTamano(_ it: NSMenuItem) {
        guard let ancho = it.representedObject as? CGFloat else { return }
        app?.panel.cambiarTamano(ancho)
    }

    @objc private func alternarLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { NSLog("Mascota: no pude cambiar el inicio de sesión: \(error)") }
    }

    @objc private func salir() { NSApp.terminate(nil) }
}
