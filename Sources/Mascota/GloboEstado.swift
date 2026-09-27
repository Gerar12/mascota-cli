import AppKit
import MascotaCore

/// Pastilla de vidrio oscuro con un indicador por sesión: logo del CLI + estado.
final class GloboEstado: NSView {
    static let alto: CGFloat = 22
    private static let naranjaClaude = NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1)

    private let fondo = NSVisualEffectView()
    private let pila = NSStackView()
    private var actuales: [Chip] = []
    private var vozActual: EstadoVoz?

    init() {
        super.init(frame: .zero)
        fondo.material = .hudWindow
        fondo.blendingMode = .behindWindow
        fondo.state = .active
        fondo.wantsLayer = true
        fondo.layer?.cornerRadius = Self.alto / 2
        fondo.layer?.masksToBounds = true
        fondo.layer?.borderWidth = 0.5
        fondo.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        pila.orientation = .horizontal
        pila.alignment = .centerY
        pila.spacing = 7
        pila.edgeInsets = NSEdgeInsets(top: 0, left: 9, bottom: 0, right: 9)
        addSubview(fondo)
        addSubview(pila)
    }

    required init?(coder: NSCoder) { fatalError("no se usa") }

    /// Rehace los indicadores solo si cambiaron, para no reiniciar sus animaciones.
    func mostrar(_ chips: [Chip], voz: EstadoVoz?) {
        guard chips != actuales || voz != vozActual else { return }
        actuales = chips
        vozActual = voz
        pila.arrangedSubviews.forEach { $0.removeFromSuperview() }
        var vistas = chips.map(Self.vista)
        if let v = Self.vistaVoz(voz) { vistas.append(v) }
        for (i, v) in vistas.enumerated() {
            if i > 0 { pila.addArrangedSubview(Self.separador()) }
            pila.addArrangedSubview(v)
        }
        frame.size = NSSize(width: pila.fittingSize.width, height: Self.alto)
        fondo.frame = bounds
        pila.frame = bounds
    }

    /// Bocina animada mientras el lector de voz habla; tachada y tenue si está silenciado.
    private static func vistaVoz(_ voz: EstadoVoz?) -> NSView? {
        switch voz {
        case .hablando:
            let v = simbolo("speaker.wave.2.fill", .white)
            v.addSymbolEffect(.variableColor.iterative, options: .repeating)
            return v
        case .silenciada:
            return simbolo("speaker.slash.fill", NSColor.white.withAlphaComponent(0.45))
        case .normal, nil:
            return nil
        }
    }

    private static func vista(_ chip: Chip) -> NSView {
        let logo = chip.cli == "codex"
            ? logoOriginal("codex.svg", .white) ?? simbolo("terminal", .white)
            : logoOriginal("claude.png", naranjaClaude) ?? simbolo("asterisk", naranjaClaude, peso: .heavy)
        let estado: NSImageView
        switch chip.estado {
        case .running:
            estado = simbolo("ellipsis", .white)
            estado.addSymbolEffect(.variableColor.iterative, options: .repeating)
        case .waiting:
            estado = simbolo("hand.raised.fill", .systemOrange)
            estado.addSymbolEffect(.pulse, options: .repeating)
        case .done:
            estado = simbolo("checkmark", .systemGreen, peso: .heavy)
        case .failed:
            estado = simbolo("exclamationmark.triangle.fill", .systemRed)
        }
        let par = NSStackView(views: [logo, estado])
        par.spacing = 3
        return par
    }

    /// Logo instalado por scripts/instalar-mascotas.sh en ~/.mascota/iconos, pintado como plantilla.
    private static func logoOriginal(_ archivo: String, _ color: NSColor) -> NSImageView? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".mascota/iconos/\(archivo)")
        guard let original = NSImage(contentsOf: url), let img = sinMargen(original) else { return nil }
        img.isTemplate = true
        img.size = NSSize(width: 14, height: 14)
        let v = NSImageView(image: img)
        v.contentTintColor = color
        v.imageScaling = .scaleProportionallyUpOrDown
        v.widthAnchor.constraint(equalToConstant: 14).isActive = true
        v.heightAnchor.constraint(equalToConstant: 14).isActive = true
        return v
    }

    /// Recorta el margen transparente para que logos de fuentes distintas midan lo mismo.
    private static func sinMargen(_ imagen: NSImage, lado: Int = 96) -> NSImage? {
        guard let ctx = CGContext(data: nil, width: lado, height: lado, bitsPerComponent: 8, bytesPerRow: lado * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        imagen.draw(in: NSRect(x: 0, y: 0, width: lado, height: lado))
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = ctx.makeImage(), let datos = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var minX = lado, minY = lado, maxX = -1, maxY = -1
        for y in 0..<lado {
            for x in 0..<lado where datos[(y * lado + x) * 4 + 3] > 16 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // Cuadrado centrado en el contenido, para no deformar el logo.
        let tam = max(maxX - minX, maxY - minY) + 1
        let cx = (minX + maxX + 1) / 2, cy = (minY + maxY + 1) / 2
        let rect = CGRect(x: cx - tam / 2, y: cy - tam / 2, width: tam, height: tam)
        guard let recorte = cg.cropping(to: rect) else { return nil }
        return NSImage(cgImage: recorte, size: NSSize(width: 14, height: 14))
    }

    private static func simbolo(_ nombre: String, _ color: NSColor, peso: NSFont.Weight = .bold) -> NSImageView {
        let conf = NSImage.SymbolConfiguration(pointSize: 11, weight: peso)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let img = NSImage(systemSymbolName: nombre, accessibilityDescription: nil)?.withSymbolConfiguration(conf)
        let v = NSImageView(image: img ?? NSImage())
        v.setContentHuggingPriority(.required, for: .horizontal)
        return v
    }

    private static func separador() -> NSView {
        let v = NSBox()
        v.boxType = .custom
        v.borderWidth = 0
        v.fillColor = NSColor.white.withAlphaComponent(0.2)
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 11).isActive = true
        return v
    }
}
