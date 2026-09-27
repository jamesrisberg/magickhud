// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "magickHUD",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "magickHUDKit", targets: ["magickHUDKit"]),
        .executable(name: "magickHUD", targets: ["magickHUD"]),
        // Installed as Contents/Helpers/magickhud: a distinct product name because magickHUD and
        // magickhud would collide on a case-insensitive volume.
        .executable(name: "magickHUDCLI", targets: ["magickHUDCLI"]),
    ],
    dependencies: [
        // Sibling checkout: ~/dev/hudkit next to ~/dev/magickhud.
        .package(path: "../hudkit"),
    ],
    targets: [
        // Pure core: presets, argv building, output naming, the batch runner, identify. No UI.
        .target(name: "magickHUDKit", path: "Sources/magickHUDKit"),
        .executableTarget(
            name: "magickHUD",
            dependencies: ["magickHUDKit", .product(name: "HUDKit", package: "hudkit")],
            path: "Sources/magickHUD",
            // Bundle files, assembled into the .app by hudkit/scripts/hud-build.sh.
            exclude: ["Resources"]
        ),
        // `magickhud <command> [key=value ...]`: a thin client for the control socket.
        .executableTarget(
            name: "magickHUDCLI",
            dependencies: ["magickHUDKit", .product(name: "HUDKit", package: "hudkit")],
            path: "Sources/magickHUDCLI"
        ),
        .testTarget(name: "magickHUDKitTests", dependencies: ["magickHUDKit"], path: "Tests/magickHUDKitTests"),
        // Host logic in the app target and the shipped manifest/settings schema/Info.plist.
        .testTarget(
            name: "magickHUDTests",
            dependencies: ["magickHUD", "magickHUDKit", .product(name: "HUDKit", package: "hudkit")],
            path: "Tests/magickHUDTests"
        ),
    ]
)
