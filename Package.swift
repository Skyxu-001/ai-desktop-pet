// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LocalDesktopPet",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "PetCore", targets: ["PetCore"]),
        .executable(name: "PetProbe", targets: ["PetProbe"]),
        .executable(name: "DesktopPet", targets: ["DesktopPet"])
    ],
    targets: [
        .target(name: "PetCore"),
        .target(name: "PetModel", dependencies: ["PetCore"]),
        .target(name: "PetUI", dependencies: ["PetCore"]),
        .executableTarget(name: "PetProbe", dependencies: ["PetCore", "PetModel"]),
        .target(name: "PetRuntime", dependencies: ["PetCore"]),
        .executableTarget(name: "DesktopPet", dependencies: ["PetCore", "PetModel", "PetRuntime", "PetUI"]),
        .testTarget(name: "PetCoreTests", dependencies: ["PetCore"]),
        .testTarget(name: "PetRuntimeTests", dependencies: ["PetRuntime"]),
        .testTarget(name: "PetModelTests", dependencies: ["PetModel", "PetCore"]),
        .testTarget(name: "PetAppTests", dependencies: ["DesktopPet", "PetUI", "PetCore"])
    ]
)
