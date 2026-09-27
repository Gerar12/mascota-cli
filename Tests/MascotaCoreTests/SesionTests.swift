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

@Test func leeElPidCuandoViene() throws {
    let json = #"{"cli":"codex","session":"b","project":"p","state":"done","ts":1,"pid":4321}"#
    let s = try JSONDecoder().decode(Sesion.self, from: Data(json.utf8))
    #expect(s.pid == 4321)
}

@Test func leeLaCarpetaCuandoViene() throws {
    let json = #"{"cli":"codex","session":"b","project":"p","state":"done","ts":1,"cwd":"/Users/x/p"}"#
    #expect(try JSONDecoder().decode(Sesion.self, from: Data(json.utf8)).cwd == "/Users/x/p")
}
