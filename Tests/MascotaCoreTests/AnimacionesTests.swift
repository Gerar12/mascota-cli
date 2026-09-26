import Foundation
import Testing
@testable import MascotaCore

@Test func estadoAFila() {
    #expect(Animaciones.para(estado: .running, desdeCambio: 0).fila == 7)
    #expect(Animaciones.para(estado: .waiting, desdeCambio: 0).fila == 6)
    #expect(Animaciones.para(estado: .failed, desdeCambio: 0).fila == 5)
    #expect(Animaciones.para(estado: nil, desdeCambio: 0).fila == 0)
}

@Test func doneSaludaDosVecesYLuegoIdle() {
    let w = Animaciones.waving.total
    #expect(Animaciones.para(estado: .done, desdeCambio: w * 2 - 0.01).fila == 3)
    #expect(Animaciones.para(estado: .done, desdeCambio: w * 2 + 0.01).fila == 0)
}

@Test func cuadroSegunTiempo() {
    let idle = Animaciones.idle  // 0.28, 0.11, 0.11, 0.14, 0.14, 0.32
    #expect(Animaciones.cuadro(idle, tiempo: 0) == 0)
    #expect(Animaciones.cuadro(idle, tiempo: 0.30) == 1)
    #expect(Animaciones.cuadro(idle, tiempo: 1.0) == 5)
    #expect(Animaciones.cuadro(idle, tiempo: idle.total + 0.01) == 0)
}

@Test func textoDelGlobo() {
    let s = Sesion(cli: "codex", session: "x", project: "vps-prod", state: .done, ts: 0)
    #expect(Textos.globo(s, estado: .done) == "Codex terminó · vps-prod")
    #expect(Textos.globo(s, estado: .waiting) == "Codex necesita permiso · vps-prod")
}

@Test func chipsDelGlobo() {
    let t: TimeInterval = 1_790_000_000
    let ahora = Date(timeIntervalSince1970: t)
    let lista = [
        Sesion(cli: "codex", session: "b", project: "p", state: .waiting, ts: t - 5),
        Sesion(cli: "claude", session: "a", project: "p", state: .running, ts: t - 1),
        Sesion(cli: "claude", session: "c", project: "p", state: .failed, ts: t - 120),
        Sesion(cli: "claude", session: "viejo", project: "p", state: .done, ts: t - 40 * 60),
    ]
    #expect(Textos.chips(lista, ahora: ahora) == [
        Chip(cli: "claude", estado: .done),
        Chip(cli: "claude", estado: .running),
        Chip(cli: "codex", estado: .waiting),
    ])
    #expect(Textos.chips([], ahora: ahora) == [])
}
