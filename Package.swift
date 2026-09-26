// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Mascota",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MascotaCore"),
        .executableTarget(name: "Mascota", dependencies: ["MascotaCore"]),
        .testTarget(
            name: "MascotaCoreTests",
            dependencies: ["MascotaCore"],
            // Solo Command Line Tools: sin esto, las compilaciones incrementales a veces no encuentran las macros de swift-testing.
            swiftSettings: [.unsafeFlags(["-plugin-path", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"])]
        ),
    ]
)
