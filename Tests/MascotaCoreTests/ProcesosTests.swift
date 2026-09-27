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

@Test func detectaVozSonando() {
    #expect(Procesos.hayVozSonando(salidaPs: "??       afplay\nttys001  codex"))
    #expect(Procesos.hayVozSonando(salidaPs: "??       /usr/bin/say"))
    #expect(Procesos.hayVozSonando(salidaPs: "ttys001  codex\n??  sayhello") == false)
}

@Test func estadoDeVoz() {
    #expect(Voz.estado(silenciada: true, sonando: true) == .silenciada)
    #expect(Voz.estado(silenciada: false, sonando: true) == .hablando)
    #expect(Voz.estado(silenciada: false, sonando: false) == .normal)
}
