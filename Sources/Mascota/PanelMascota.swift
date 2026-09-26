import AppKit
import MascotaCore

/// Vista de la mascota: arrastrar mueve la ventana; un clic sin arrastrar abre el menú.
final class VistaSprite: NSView {
    var alHacerClic: ((NSEvent) -> Void)?
    private var arrastro = false

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { arrastro = false }

    override func mouseDragged(with event: NSEvent) {
        guard !arrastro else { return }
        arrastro = true
        window?.performDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if !arrastro { alHacerClic?(event) }
    }
}

/// Ventana flotante sin bordes con la mascota y un globo de íconos encima.
final class PanelMascota: NSPanel {
    let sprite = VistaSprite()
    private let globo = GloboEstado()
    static let tamSprite = NSSize(width: 80, height: 87)

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 220, height: 130),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false

        let fondo = NSView(frame: contentRect(forFrameRect: frame))
        sprite.wantsLayer = true
        sprite.layer?.contentsGravity = .resizeAspect
        sprite.layer?.magnificationFilter = .nearest
        sprite.frame = NSRect(x: (220 - Self.tamSprite.width) / 2, y: 0,
                              width: Self.tamSprite.width, height: Self.tamSprite.height)

        globo.isHidden = true

        fondo.addSubview(sprite)
        fondo.addSubview(globo)
        contentView = fondo

        if !setFrameUsingName("MascotaPanel"), let pantalla = NSScreen.main?.visibleFrame {
            setFrameOrigin(NSPoint(x: pantalla.maxX - 240, y: pantalla.maxY - 140))
        }
        setFrameAutosaveName("MascotaPanel")
    }

    override var canBecomeKey: Bool { false }

    func mostrarCuadro(_ imagen: CGImage?) { sprite.layer?.contents = imagen }

    func mostrarGlobo(_ chips: [Chip]?) {
        guard let chips, !chips.isEmpty else { globo.isHidden = true; return }
        globo.mostrar(chips)
        // La celda del sprite tiene aire transparente arriba: el globo se apoya casi sobre la cabeza.
        globo.setFrameOrigin(NSPoint(x: ((220 - globo.frame.width) / 2).rounded(), y: Self.tamSprite.height - 4))
        globo.isHidden = false
    }
}
