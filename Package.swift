// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Owl",
    platforms: [.macOS("27.0")],
    targets: [
        // Pure model + geometry, no AppKit. Unit-tested.
        .target(name: "OwlCore"),
        // The menu-bar app.
        .executableTarget(
            name: "Owl",
            dependencies: ["OwlCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)],
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Carbon"),
            ]
        ),
        // Debug/test CLI that drives the running app over a unix socket.
        .executableTarget(name: "owlctl", dependencies: ["OwlCore"]),
        .testTarget(name: "OwlCoreTests", dependencies: ["OwlCore"]),
    ]
)
