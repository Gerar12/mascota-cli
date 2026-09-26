import Foundation
import Testing
@testable import MascotaCore

private func crearMascota(_ raiz: URL, _ carpeta: String, id: String, nombre: String, conHoja: Bool = true) throws {
    let d = raiz.appendingPathComponent(carpeta)
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    let json = #"{"id":"\#(id)","displayName":"\#(nombre)","spriteVersionNumber":2,"spritesheetPath":"spritesheet.webp"}"#
    try json.write(to: d.appendingPathComponent("pet.json"), atomically: true, encoding: .utf8)
    if conHoja { try Data([0]).write(to: d.appendingPathComponent("spritesheet.webp")) }
}

@Test func cargaMascotasDeVariosDirectorios() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let a = tmp.appendingPathComponent("a"), b = tmp.appendingPathComponent("b")
    try crearMascota(a, "null-signal", id: "null-signal", nombre: "Null Signal")
    try crearMascota(a, "rota", id: "rota", nombre: "Rota", conHoja: false)
    try crearMascota(b, "otra", id: "null-signal", nombre: "Duplicada")
    try crearMascota(b, "cangrejo", id: "cangrejo", nombre: "Cangrejo")

    let m = CatalogoMascotas.cargar(directorios: [a, b, URL(fileURLWithPath: "/no/existe")])

    #expect(m.map(\.id) == ["cangrejo", "null-signal"])
    #expect(m[1].nombre == "Null Signal")
    #expect(m[1].hoja.lastPathComponent == "spritesheet.webp")
}
