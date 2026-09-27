import Testing
@testable import MascotaCore

private let lista = [
    TerminalGhostty(id: "A", nombre: "zsh", carpeta: "/Users/x"),
    TerminalGhostty(id: "B", nombre: "◐ Otra cosita", carpeta: "/Users/x"),
    TerminalGhostty(id: "C", nombre: "codex", carpeta: "/Users/x/proyecto"),
    TerminalGhostty(id: "D", nombre: "✳ Arreglar login", carpeta: "/Users/x/proyecto"),
]

@Test func claudePrefiereElTituloConSuSimbolo() {
    #expect(Terminales.elegir(lista, cli: "claude", carpeta: "/Users/x") == "B")
    #expect(Terminales.elegir(lista, cli: "claude", carpeta: "/Users/x/proyecto") == "D")
}

@Test func codexEvitaLasDeClaude() {
    #expect(Terminales.elegir(lista, cli: "codex", carpeta: "/Users/x/proyecto") == "C")
}

@Test func sinCoincidenciaDeCarpeta() {
    #expect(Terminales.elegir(lista, cli: "claude", carpeta: "/otra") == nil)
    #expect(Terminales.elegir(lista, cli: "claude", carpeta: nil) == nil)
    // Carpeta con barra final igual cuenta.
    #expect(Terminales.elegir(lista, cli: "codex", carpeta: "/Users/x/proyecto/") == "C")
}

@Test func leeLaSalidaDeAppleScript() {
    let salida = "A\tzsh\t/Users/x\nB\t◐ Otra cosita\t/Users/x\n\n"
    #expect(Terminales.leer(salida) == Array(lista.prefix(2)))
}
