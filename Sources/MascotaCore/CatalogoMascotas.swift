import Foundation

public struct MascotaDef: Equatable, Sendable {
    public let id: String
    public let nombre: String
    public let hoja: URL
}

public enum CatalogoMascotas {
    private struct Manifiesto: Decodable {
        let id: String
        let displayName: String
        let spritesheetPath: String
    }

    public static func cargar(directorios: [URL]) -> [MascotaDef] {
        var vistos = Set<String>()
        var resultado: [MascotaDef] = []
        let fm = FileManager.default
        for dir in directorios {
            let carpetas = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for carpeta in carpetas {
                guard let datos = try? Data(contentsOf: carpeta.appendingPathComponent("pet.json")),
                      let m = try? JSONDecoder().decode(Manifiesto.self, from: datos) else { continue }
                let hoja = carpeta.appendingPathComponent(m.spritesheetPath)
                guard fm.fileExists(atPath: hoja.path), vistos.insert(m.id).inserted else { continue }
                resultado.append(MascotaDef(id: m.id, nombre: m.displayName, hoja: hoja))
            }
        }
        return resultado.sorted { $0.nombre < $1.nombre }
    }
}
