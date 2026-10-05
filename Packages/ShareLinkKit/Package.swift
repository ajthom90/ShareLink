// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ShareLinkKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ShareLinkKit", targets: ["ShareLinkKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/amosavian/AMSMB2.git", exact: "4.0.3"),
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(
            name: "ShareLinkKit",
            dependencies: [
                .product(name: "AMSMB2", package: "AMSMB2"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            resources: [.copy("Resources/Licenses")]
        ),
        .testTarget(name: "ShareLinkKitTests", dependencies: ["ShareLinkKit"]),
        .testTarget(name: "ShareLinkIntegrationTests", dependencies: ["ShareLinkKit"]),
    ]
)
