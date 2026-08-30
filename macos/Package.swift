// swift-tools-version: 6.2
import PackageDescription

// Native macOS operator shell (personal/local builds only — not App Store).
// Reuses the portable OpenPocketViewCore from the repository root package and
// supplies the Mac platform I/O: CoreBluetooth (BleLink), CoreWLAN (WiFiJoiner),
// Network.framework (DatalinkDriver), VideoToolbox (HevcDecoder).
//
// Non-sandboxed on purpose: CoreWLAN `associate` and SSID read are only viable
// outside the Mac App Store sandbox.
let package = Package(
    name: "OpenPocketCineMac",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "OpenPocketCineMac", targets: ["OpenPocketCineMac"]),
    ],
    dependencies: [
        .package(path: ".."),
    ],
    targets: [
        .executableTarget(
            name: "OpenPocketCineMac",
            dependencies: [
                .product(name: "OpenPocketViewCore", package: "OpenPocketCine"),
            ],
            // The iOS shell (ios/project.yml) compiles in Swift 5 language mode;
            // the ported files must keep that mode on Mac too.
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedFramework("CoreWLAN"),
            ]
        ),
    ]
)
