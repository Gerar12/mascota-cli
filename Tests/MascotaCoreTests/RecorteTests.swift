import Testing
@testable import MascotaCore

@Test func primeraFilaConDibujo() {
    // 3x4: filas 0 y 1 transparentes, fila 2 con un pixel opaco.
    var alfa = [UInt8](repeating: 0, count: 12)
    alfa[2 * 3 + 1] = 255
    #expect(Recorte.primeraFilaOpaca(alfa: alfa, ancho: 3, alto: 4) == 2)
    #expect(Recorte.primeraFilaOpaca(alfa: [UInt8](repeating: 0, count: 12), ancho: 3, alto: 4) == nil)
    // Casi transparente (restos de antialias) no cuenta.
    var tenue = [UInt8](repeating: 0, count: 12)
    tenue[0] = 10
    #expect(Recorte.primeraFilaOpaca(alfa: tenue, ancho: 3, alto: 4) == nil)
}
