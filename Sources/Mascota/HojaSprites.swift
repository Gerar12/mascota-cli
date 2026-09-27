import AppKit
import MascotaCore

/// Recorta celdas de 192x208 de una hoja de sprites de Codex, con caché.
final class HojaSprites {
    static let ancho = 192, alto = 208
    private let imagen: CGImage
    private var cache: [Int: CGImage] = [:]
    private var aires: [Int: CGFloat] = [:]
    /// Las hojas v2 (11 filas) traen las 16 miradas; las v1 (9 filas) no.
    var tieneMiradas: Bool { imagen.height >= Self.alto * 11 }

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

    /// Fracción de la celda que queda vacía arriba del dibujo en toda la fila (la más alta de sus cuadros),
    /// para apoyar el globo sobre la cabeza sin que salte en cada cuadro.
    func aireSuperior(fila: Int) -> CGFloat {
        if let a = aires[fila] { return a }
        var minimo = Self.alto
        for col in 0..<8 {
            guard let c = celda(fila: fila, columna: col), let alfa = Self.alfa(c),
                  let y = Recorte.primeraFilaOpaca(alfa: alfa, ancho: Self.ancho, alto: Self.alto) else { continue }
            minimo = min(minimo, y)
        }
        let a = minimo == Self.alto ? 0 : CGFloat(minimo) / CGFloat(Self.alto)
        aires[fila] = a
        return a
    }

    private static func alfa(_ img: CGImage) -> [UInt8]? {
        var datos = [UInt8](repeating: 0, count: ancho * alto)
        let ok = datos.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: ancho, height: alto, bitsPerComponent: 8,
                                      bytesPerRow: ancho, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return false }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: ancho, height: alto))
            return true
        }
        return ok ? datos : nil
    }
}
