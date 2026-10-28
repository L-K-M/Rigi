// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Rigi",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RigiUI", targets: ["RigiUI"]),
        .executable(name: "RigiGallery", targets: ["RigiGallery"])
    ],
    targets: [
        .target(name: "RigiUI"),
        .executableTarget(name: "RigiGallery", dependencies: ["RigiUI"]),
        .testTarget(name: "RigiUITests", dependencies: ["RigiUI"])
    ]
)
