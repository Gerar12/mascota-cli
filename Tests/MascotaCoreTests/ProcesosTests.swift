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
