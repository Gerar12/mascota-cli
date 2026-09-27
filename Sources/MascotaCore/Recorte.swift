public enum Recorte {
    /// Primera fila (desde arriba) con algún pixel visible (alfa > 32); nil si la imagen está vacía.
    public static func primeraFilaOpaca(alfa: [UInt8], ancho: Int, alto: Int) -> Int? {
        (0..<alto).first { y in (0..<ancho).contains { alfa[y * ancho + $0] > 32 } }
    }
}
