import Foundation
import Testing
@testable import MascotaCore

@Test func despiertaMientrasTrabajanYQuinceMinutosDespues() {
    let ahora = Date(timeIntervalSince1970: 1_790_000_000)
    #expect(Energia.mantenerDespierta(trabajando: true, ultimaVezTrabajando: nil, ahora: ahora))
    #expect(Energia.mantenerDespierta(trabajando: false, ultimaVezTrabajando: ahora.addingTimeInterval(-60), ahora: ahora))
    #expect(Energia.mantenerDespierta(trabajando: false, ultimaVezTrabajando: ahora.addingTimeInterval(-901), ahora: ahora) == false)
    #expect(Energia.mantenerDespierta(trabajando: false, ultimaVezTrabajando: nil, ahora: ahora) == false)
}

@Test func trabajandoEsRunningOWaiting() {
    let t: TimeInterval = 1_790_000_000
    let ahora = Date(timeIntervalSince1970: t)
    let s = { (e: EstadoAgente) in Sesion(cli: "codex", session: "x", project: "p", state: e, ts: t - 1) }
    #expect(Energia.hayTrabajo([s(.running)], ahora: ahora))
    #expect(Energia.hayTrabajo([s(.waiting)], ahora: ahora))
    #expect(Energia.hayTrabajo([s(.done), s(.failed)], ahora: ahora) == false)
}
