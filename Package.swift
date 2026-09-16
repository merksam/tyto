// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Tyto",
    platforms: [.macOS("27.0")],
    targets: [
        // Pure model + geometry, no AppKit. Unit-tested.
        .target(name: "TytoCore"),
        // The menu-bar app.
        .executableTarget(
            name: "Tyto",
            dependencies: ["TytoCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)],
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Carbon"),
            ]
        ),
        // Debug/test CLI that drives the running app over a unix socket.
        .executableTarget(name: "tytoctl", dependencies: ["TytoCore"]),
        .testTarget(name: "TytoCoreTests", dependencies: ["TytoCore"]),
    ]
)
