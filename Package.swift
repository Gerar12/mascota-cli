// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Mascota",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MascotaCore"),
        .executableTarget(name: "Mascota", dependencies: ["MascotaCore"]),
        .testTarget(name: "MascotaCoreTests", dependencies: ["MascotaCore"]),
    ]
)
