import Testing
@testable import MascotaCore

@Test func miradaSegunElCursor() {
    // dx a la derecha, dy hacia arriba (coordenadas de pantalla de macOS).
    #expect(Mirada.celda(dx: 0, dy: 100)! == Celda(fila: 9, columna: 0))      // arriba: 000
    #expect(Mirada.celda(dx: 100, dy: 0)! == Celda(fila: 9, columna: 4))      // derecha: 090
    #expect(Mirada.celda(dx: 0, dy: -100)! == Celda(fila: 10, columna: 0))    // abajo: 180
    #expect(Mirada.celda(dx: -100, dy: 0)! == Celda(fila: 10, columna: 4))    // izquierda: 270
    #expect(Mirada.celda(dx: 70, dy: 70)! == Celda(fila: 9, columna: 2))      // 045
    #expect(Mirada.celda(dx: -5, dy: 99)! == Celda(fila: 9, columna: 0))      // casi arriba, por la izquierda
    #expect(Mirada.celda(dx: 3, dy: 4) == nil)                                 // encima de la mascota
}

@Test func eligeTravesurasSegunElAzar() {
    #expect(Reposo.elegir(0.10, 0.5) == .descansar)
    #expect(Reposo.elegir(0.40, 0.0) == .pasear(dx: -140))
    #expect(Reposo.elegir(0.40, 0.99) == .pasear(dx: 138))
    #expect(Reposo.elegir(0.65, 0.5) == .saltar)
    #expect(Reposo.elegir(0.80, 0.5) == .saludar)
    #expect(Reposo.elegir(0.95, 0.5) == .mirarAlrededor)
    #expect(Reposo.espera(0) == 10 && Reposo.espera(1) == 25)
}

@Test func paseoDeIdaYVuelta() {
    // 100 pt a 50 pt/s: 2 s de ida, 1.2 s de pausa, 2 s de vuelta.
    #expect(Reposo.paseo(dx: 100, t: 1)! == Paso(desplazamiento: 50, fila: 1))
    #expect(Reposo.paseo(dx: 100, t: 2.5)! == Paso(desplazamiento: 100, fila: nil))
    let vuelta = Reposo.paseo(dx: 100, t: 4.2)!
    #expect(abs(vuelta.desplazamiento - 50) < 0.001 && vuelta.fila == 2)
    #expect(Reposo.paseo(dx: -100, t: 1)! == Paso(desplazamiento: -50, fila: 2))
    #expect(Reposo.paseo(dx: 100, t: 5.3) == nil)
}

@Test func duracionDeCadaTravesura() {
    #expect(Reposo.duracion(.saltar) == Animaciones.jumping.total)
    #expect(Reposo.duracion(.saludar) == Animaciones.waving.total * 2)
    #expect(Reposo.duracion(.mirarAlrededor) == 16 * 0.18)
    #expect(Reposo.duracion(.pasear(dx: 100)) == 5.2)
}
