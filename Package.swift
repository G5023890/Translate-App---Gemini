// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TranslateGemini",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "TranslateGemini"
        )
    ]
)
