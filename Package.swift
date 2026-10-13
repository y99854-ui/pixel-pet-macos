// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "PixelPetMac",
    platforms: [.macOS(.v12)],
    products: [.executable(name: "PixelPet", targets: ["PixelPet"])],
    targets: [
        .target(name: "PixelPetCore", resources: [.process("Resources")]),
        .executableTarget(name: "PixelPet", dependencies: ["PixelPetCore"]),
        .testTarget(name: "PixelPetCoreTests", dependencies: ["PixelPetCore"])
    ]
)
