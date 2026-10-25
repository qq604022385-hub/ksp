// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KankeCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "KankeCore", targets: ["KankeCore"])],
    targets: [
        .target(name: "KankeCore"),
        .testTarget(name: "KankeCoreTests", dependencies: ["KankeCore"], resources: [.process("Fixtures")])
    ]
)
