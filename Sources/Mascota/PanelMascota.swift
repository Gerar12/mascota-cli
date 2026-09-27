import AppKit
import MascotaCore

/// Vista de la mascota: arrastrar mueve la ventana; un clic sin arrastrar abre el menú.
final class VistaSprite: NSView {
    var alHacerClic: ((NSEvent) -> Void)?
    var alTerminarArrastre: (() -> Void)?
    private var arrastro = false

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { arrastro = false }

    override func mouseDragged(with event: NSEvent) {
        guard !arrastro else { return }
        arrastro = true
        window?.performDrag(with: event)      // bloquea hasta soltar el mouse
        alTerminarArrastre?()
    }

    override func mouseUp(with event: NSEvent) {
        if !arrastro { alHacerClic?(event) }
    }
}

/// Ventana flotante sin bordes con la mascota y un globo de íconos encima.
final class PanelMascota: NSPanel {
    let sprite = VistaSprite()
    private let globo = GloboEstado()
    /// Tamaños que ofrece el menú (ancho del sprite en puntos); Mediana es el mismo de Codex.
    static let tamanos: [(nombre: String, ancho: CGFloat)] = [("Chica", 56), ("Mediana", 80), ("Grande", 112), ("Muy grande", 144)]
    private(set) var anchoSprite: CGFloat = 80
    private var tamSprite: NSSize {
        NSSize(width: anchoSprite, height: (anchoSprite * 208 / 192).rounded())
    }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 220, height: 130),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Por encima de la barra de menú, como la mascota de ChatGPT.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false

        let fondo = NSView(frame: contentRect(forFrameRect: frame))
        sprite.wantsLayer = true
        sprite.layer?.contentsGravity = .resizeAspect
        sprite.layer?.magnificationFilter = .nearest

        globo.isHidden = true

        fondo.addSubview(sprite)
        fondo.addSubview(globo)
        contentView = fondo

        if !setFrameUsingName("MascotaPanel"), let pantalla = NSScreen.main?.visibleFrame {
            setFrameOrigin(NSPoint(x: pantalla.maxX - 240, y: pantalla.maxY - 140))
        }
        let guardado = CGFloat(UserDefaults.standard.double(forKey: "tamano"))
        cambiarTamano(guardado > 0 ? guardado : 80)
    }

    /// Cambia el tamaño de la mascota dejando fijo el centro de abajo, para que no salte de lugar.
    func cambiarTamano(_ ancho: CGFloat) {
        anchoSprite = ancho
        UserDefaults.standard.set(Double(ancho), forKey: "tamano")
        let t = tamSprite
        let tamPanel = NSSize(width: max(220, t.width + 40), height: t.height + 40)
        setFrame(NSRect(x: (frame.midX - tamPanel.width / 2).rounded(), y: frame.minY,
                        width: tamPanel.width, height: tamPanel.height), display: true)
        contentView?.frame = NSRect(origin: .zero, size: tamPanel)
        sprite.frame = NSRect(x: ((tamPanel.width - t.width) / 2).rounded(), y: 0, width: t.width, height: t.height)
        if !globo.isHidden { colocarGlobo() }
        guardarCasa()
    }

    /// Lugar donde el usuario dejó la mascota: los paseos salen de aquí y vuelven aquí.
    private(set) var casa = NSPoint.zero
    var altoSprite: CGFloat { tamSprite.height }

    func guardarCasa() {
        casa = frame.origin
        saveFrame(usingName: "MascotaPanel")
    }

    /// Mueve la ventana a `dx` puntos de su casa (paseos); 0 = en casa.
    func ponerDesplazamiento(_ dx: CGFloat) {
        let destino = NSPoint(x: (casa.x + dx).rounded(), y: casa.y)
        if frame.origin != destino { setFrameOrigin(destino) }
    }

    private func colocarGlobo() {
        // El globo se apoya justo encima de la cabeza, sea cual sea la mascota o el tamaño.
        let cabeza = (tamSprite.height * (1 - aireSuperior)).rounded()
        globo.setFrameOrigin(NSPoint(x: ((frame.width - globo.frame.width) / 2).rounded(), y: cabeza + 4))
    }

    override var canBecomeKey: Bool { false }

    /// Sin esto macOS empuja la ventana debajo de la barra de menú al arrastrarla hacia arriba.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    /// Fracción vacía arriba del dibujo de la animación actual (ver HojaSprites.aireSuperior).
    private var aireSuperior: CGFloat = 0

    func mostrarCuadro(_ imagen: CGImage?, aireSuperior: CGFloat) {
        sprite.layer?.contents = imagen
        if aireSuperior != self.aireSuperior {
            self.aireSuperior = aireSuperior
            if !globo.isHidden { colocarGlobo() }
        }
    }

    func mostrarGlobo(_ chips: [Chip]?) {
        guard let chips, !chips.isEmpty else { globo.isHidden = true; return }
        globo.mostrar(chips)
        colocarGlobo()
        globo.isHidden = false
    }
}
