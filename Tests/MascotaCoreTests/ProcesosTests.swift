import Testing
@testable import MascotaCore

@Test func elevenSinCreditosSegunElUltimoIntento() {
    let sin = "ELEVEN OK (x)\nEDGE OK\nELEVEN FAIL (401, 5 chars): {\"code\":\"quota_exceeded\"}\nEDGE OK"
    #expect(Voz.elevenSinCreditos(log: sin))
    #expect(Voz.elevenSinCreditos(log: sin + "\nELEVEN OK (Daniela)") == false)
    #expect(Voz.elevenSinCreditos(log: "ELEVEN FAIL (000, timeout)") == false)
    #expect(Voz.elevenSinCreditos(log: "") == false)
}
