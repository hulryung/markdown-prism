// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MarkdownPrism",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "MarkdownPrism",
            path: "Sources/MarkdownPrism",
            exclude: [
                "Info.plist"
            ],
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "MarkdownPrismTests",
            dependencies: ["MarkdownPrism"],
            path: "Tests/MarkdownPrismTests"
        )
    ]
)
