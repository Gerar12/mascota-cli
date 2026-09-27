import Testing
@testable import MascotaCore

@Test func detectaCodexConTerminal() {
    let servicio = """
    ??       /Users/x/.codex/packages/app-server-daemon/bin/codex
    ttys000  claude
    """
    #expect(Procesos.hayCodexConTerminal(salidaPs: servicio) == false)
    #expect(Procesos.hayCodexConTerminal(salidaPs: servicio + "\nttys001  codex\n"))
    #expect(Procesos.hayCodexConTerminal(salidaPs: " ttys002 /Users/x/.local/bin/codex"))
    #expect(Procesos.hayCodexConTerminal(salidaPs: "ttys003  codex-code-mode-host") == false)
}


@Test func elevenSinCreditosSegunElUltimoIntento() {
    let sin = "ELEVEN OK (x)\nEDGE OK\nELEVEN FAIL (401, 5 chars): {\"code\":\"quota_exceeded\"}\nEDGE OK"
    #expect(Voz.elevenSinCreditos(log: sin))
    #expect(Voz.elevenSinCreditos(log: sin + "\nELEVEN OK (Daniela)") == false)
    #expect(Voz.elevenSinCreditos(log: "ELEVEN FAIL (000, timeout)") == false)
    #expect(Voz.elevenSinCreditos(log: "") == false)
}
