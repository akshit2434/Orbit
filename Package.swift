// swift-tools-version: 6.0

import Foundation
import PackageDescription

let infoPlistPath = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Support/Info.plist")
    .path

let package = Package(
    name: "Orbit",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Orbit", targets: ["Orbit"])
    ],
    targets: [
        .executableTarget(
            name: "Orbit",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlistPath
                ])
            ]
        ),
        .testTarget(name: "OrbitTests", dependencies: ["Orbit"]),
    ]
)
