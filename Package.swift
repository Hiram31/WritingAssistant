// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "WritingAssistant",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "WritingAssistant", targets: ["WritingAssistant"])
    ],
    targets: [
        .executableTarget(name: "WritingAssistant")
    ]
)
