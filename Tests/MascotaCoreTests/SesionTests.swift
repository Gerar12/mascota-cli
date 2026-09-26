import Foundation
import Testing
@testable import MascotaCore

@Test func leeSesionesValidasEIgnoraBasura() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try #"{"cli":"claude","session":"a1","project":"vps-prod","state":"running","ts":1790000000}"#
        .write(to: dir.appendingPathComponent("claude-a1.json"), atomically: true, encoding: .utf8)
    try "no es json".write(to: dir.appendingPathComponent("roto.json"), atomically: true, encoding: .utf8)
    try "{}".write(to: dir.appendingPathComponent(".claude-a1.123"), atomically: true, encoding: .utf8)

    let sesiones = LectorEstado.leer(directorio: dir)

    #expect(sesiones == [Sesion(cli: "claude", session: "a1", project: "vps-prod", state: .running, ts: 1_790_000_000)])
    #expect(sesiones[0].nombreCLI == "Claude")
}

@Test func directorioInexistenteDevuelveVacio() {
    #expect(LectorEstado.leer(directorio: URL(fileURLWithPath: "/no/existe")) == [])
}
