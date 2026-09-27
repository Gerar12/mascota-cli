import Foundation
import Testing
@testable import MascotaCore

@Test func leeLaCuotaDeCodexDelRegistro() {
    let registro = """
    {"type":"event","payload":{"rate_limits":{"limit_id":"codex","primary":{"used_percent":21.0,"window_minutes":10080,"resets_at":1791051235}}}}
    {"type":"otro"}
    {"type":"event","payload":{"rate_limits":{"limit_id":"codex","primary":{"used_percent":43.5,"window_minutes":10080,"resets_at":1791051235},"secondary":null}}}
    """
    let c = Cuota.leer(registro)!
    #expect(c.porcentaje == 43.5)
    #expect(c.reinicio == Date(timeIntervalSince1970: 1_791_051_235))
    #expect(Cuota.leer("nada") == nil)
}

@Test func textoDeLaCuota() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/Mexico_City")!
    let c = CuotaCodex(porcentaje: 43.4, reinicio: Date(timeIntervalSince1970: 1_791_051_235))
    #expect(c.titulo == "Codex · 43 % de la semana")
    #expect(c.detalle(calendario: cal, locale: Locale(identifier: "es_MX")).hasPrefix("Se reinicia el sáb 3"))
}

@Test func hastaCuandoNoMolestar() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let ahora = Date(timeIntervalSince1970: 1_790_000_000)   // 2026-09-22 14:13 UTC
    #expect(NoMolestar.hasta(.minutos(30), ahora: ahora, calendario: cal) == ahora.addingTimeInterval(1800))
    let manana = NoMolestar.hasta(.hastaManana, ahora: ahora, calendario: cal)
    let diaSiguiente = cal.date(byAdding: .day, value: 1, to: ahora)!
    #expect(cal.component(.hour, from: manana) == 8)
    #expect(cal.component(.day, from: manana) == cal.component(.day, from: diaSiguiente))
    #expect(NoMolestar.activo(hasta: ahora.addingTimeInterval(5), ahora: ahora))
    #expect(NoMolestar.activo(hasta: ahora, ahora: ahora) == false)
    #expect(NoMolestar.activo(hasta: nil, ahora: ahora) == false)
}

@Test func avisaSoloLosPermisosNuevosDelUsuario() {
    let s = { (id: String, e: EstadoAgente, auto: Bool?) in
        Sesion(cli: "claude", session: id, project: "p", state: e, ts: 1, auto: auto) }
    let lista = [s("a", .waiting, nil), s("b", .waiting, nil), s("c", .running, nil), s("d", .waiting, true)]
    let (nuevas, esperando) = Avisos.permisosNuevos(lista, yaAvisadas: ["claude-a"])
    #expect(nuevas.map(\.session) == ["b"])
    #expect(esperando == ["claude-a", "claude-b"])
}

@Test func caricias() {
    var c = Caricia()
    // Vaivén sobre la mascota: 4 cambios de dirección en menos de 1.5 s.
    let xs: [Double] = [0, 20, 40, 20, 0, 20, 40, 20, 0, 20]
    var feliz = false
    for (i, x) in xs.enumerated() { feliz = c.registrar(x: x, encima: true, t: Double(i) * 0.1) || feliz }
    #expect(feliz)
    // Salirse un instante del borde no reinicia la cuenta: 3 vaivenes en 2 s bastan.
    var conSalida = Caricia()
    var feliz2 = false
    let pasos: [(Double, Bool)] = [(0, true), (30, true), (60, false), (30, true), (0, true), (30, true), (60, true), (30, true)]
    for (i, p) in pasos.enumerated() { feliz2 = conSalida.registrar(x: p.0, encima: p.1, t: Double(i) * 0.15) || feliz2 }
    #expect(feliz2)
    var lenta = Caricia()
    var nada = false
    for (i, x) in xs.enumerated() { nada = lenta.registrar(x: x, encima: true, t: Double(i) * 0.6) || nada }
    #expect(nada == false)
}

@Test func saludoAlVolver() {
    #expect(Saludo.debeSaludar(inactivoAntes: 400, inactivoAhora: 0.3))
    #expect(Saludo.debeSaludar(inactivoAntes: 100, inactivoAhora: 0.3) == false)
    #expect(Saludo.debeSaludar(inactivoAntes: 400, inactivoAhora: 50) == false)
}

@Test func leeLaCuotaDeClaudeDeLaBarraDeEstado() {
    let json = #"{"model":{},"rate_limits":{"five_hour":{"used_percentage":5,"resets_at":1790481000},"seven_day":{"used_percentage":20,"resets_at":1790758800}}}"#
    let c = Cuota.leerClaude(Data(json.utf8))!
    #expect(c.cincoHoras == VentanaCuota(porcentaje: 5, reinicio: Date(timeIntervalSince1970: 1_790_481_000)))
    #expect(c.semana.porcentaje == 20)
    #expect(c.titulo == "Claude · 5 % (5 h) · 20 % semana")
    #expect(Cuota.leerClaude(Data("{}".utf8)) == nil)
}

@Test func detectaQueCodexNoAvisa() {
    let t = Date(timeIntervalSince1970: 1_790_000_000)
    // Codex escribió en su registro 5 min después del último aviso, con una terminal abierta: está callado.
    #expect(Diagnostico.codexCallado(ultimoRegistro: t, ultimoAviso: t.addingTimeInterval(-300), codexAbierto: true))
    #expect(Diagnostico.codexCallado(ultimoRegistro: t, ultimoAviso: nil, codexAbierto: true))
    // Aviso reciente, sin terminal de Codex o sin registros: todo bien.
    #expect(Diagnostico.codexCallado(ultimoRegistro: t, ultimoAviso: t.addingTimeInterval(-60), codexAbierto: true) == false)
    #expect(Diagnostico.codexCallado(ultimoRegistro: t, ultimoAviso: nil, codexAbierto: false) == false)
    #expect(Diagnostico.codexCallado(ultimoRegistro: nil, ultimoAviso: nil, codexAbierto: true) == false)
}
