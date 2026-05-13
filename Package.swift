// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "langedaemon",
    products: [
        .executable(name: "langedaemon", targets: ["LangEDaemon"])
    ],
    targets: [
        .executableTarget(
            name: "LangEDaemon",
            path: "Sources/LangEDaemon"
        )
    ]
)
