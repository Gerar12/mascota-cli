import AppKit

/// Ventana flotante sin bordes con la mascota y un globo de texto encima.
final class PanelMascota: NSPanel {
    private let sprite = NSView()
    private let globo = NSTextField(labelWithString: "")
    static let tamSprite = NSSize(width: 80, height: 87)

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 220, height: 130),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false

        let fondo = NSView(frame: contentRect(forFrameRect: frame))
        sprite.wantsLayer = true
        sprite.layer?.contentsGravity = .resizeAspect
        sprite.layer?.magnificationFilter = .nearest
        sprite.frame = NSRect(x: (220 - Self.tamSprite.width) / 2, y: 0,
                              width: Self.tamSprite.width, height: Self.tamSprite.height)

        globo.font = .systemFont(ofSize: 11, weight: .medium)
        globo.textColor = .white
        globo.alignment = .center
        globo.wantsLayer = true
        globo.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        globo.layer?.cornerRadius = 8
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

    func mostrarGlobo(_ texto: String?) {
        guard let texto else { globo.isHidden = true; return }
        globo.stringValue = "  \(texto)  "
        globo.sizeToFit()
        let ancho = min(globo.frame.width + 8, 216)
        globo.frame = NSRect(x: (220 - ancho) / 2, y: Self.tamSprite.height + 6, width: ancho, height: 22)
        globo.isHidden = false
    }
}
