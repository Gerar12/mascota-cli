import AppKit

/// Recorta celdas de 192x208 de una hoja de sprites de Codex, con caché.
final class HojaSprites {
    static let ancho = 192, alto = 208
    private let imagen: CGImage
    private var cache: [Int: CGImage] = [:]

    init?(url: URL) {
        guard let img = NSImage(contentsOf: url),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        imagen = cg
    }

    func celda(fila: Int, columna: Int) -> CGImage? {
        let clave = fila * 16 + columna
        if let c = cache[clave] { return c }
        let rect = CGRect(x: columna * Self.ancho, y: fila * Self.alto, width: Self.ancho, height: Self.alto)
        let c = imagen.cropping(to: rect)
        cache[clave] = c
        return c
    }
}
