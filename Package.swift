// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "wisper-clone",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WisperClone", targets: ["wisper-clone"])
    ],
    dependencies: [
        // Local speech-to-text (Parakeet on the Neural Engine).
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.3")
    ],
    targets: [
        .executableTarget(
            name: "wisper-clone",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "wisper-cloneTests",
            dependencies: ["wisper-clone"],
            swiftSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
                ])
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
