import Foundation
import Testing
@testable import MascotaCore

private let t0: TimeInterval = 1_790_000_000
private func s(_ id: String, _ e: EstadoAgente, hace: TimeInterval, cli: String = "claude") -> Sesion {
    Sesion(cli: cli, session: id, project: "p", state: e, ts: t0 - hace)
}
private let ahora = Date(timeIntervalSince1970: t0)

@Test func ganaElMasUrgente() {
    let lista = [s("a", .running, hace: 1), s("b", .waiting, hace: 50), s("c", .done, hace: 0)]
    #expect(Agregador.principal(lista, ahora: ahora)?.session == "b")
}

@Test func empateGanaElMasReciente() {
    let lista = [s("a", .running, hace: 10), s("b", .running, hace: 2)]
    #expect(Agregador.principal(lista, ahora: ahora)?.session == "b")
}

@Test func sesionesDeMasDe30MinutosSeIgnoran() {
    #expect(Agregador.principal([s("a", .waiting, hace: 31 * 60)], ahora: ahora) == nil)
}

@Test func failedViejoCuentaComoDone() {
    let viejo = s("a", .failed, hace: 61)
    #expect(Agregador.estadoEfectivo(viejo, ahora: ahora) == .done)
    #expect(Agregador.estadoEfectivo(s("b", .failed, hace: 5), ahora: ahora) == .failed)
    let lista = [viejo, s("c", .running, hace: 100)]
    #expect(Agregador.principal(lista, ahora: ahora)?.session == "c")
}

@Test func visibilidad() {
    #expect(Agregador.debeMostrarse([], ahora: ahora) == false)
    #expect(Agregador.debeMostrarse([s("a", .running, hace: 600)], ahora: ahora))
    #expect(Agregador.debeMostrarse([s("a", .done, hace: 60)], ahora: ahora))
    #expect(Agregador.debeMostrarse([s("a", .done, hace: 181)], ahora: ahora) == false)
}
