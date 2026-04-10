// swift-tools-version: 6.0
// Lightweight SPM package for unit-testing the pure-Swift logic in SimpleMarkDown.
// The actual macOS app is built via SimpleMarkDown.xcodeproj / xcodebuild.

import PackageDescription

let package = Package(
    name: "SimpleMarkDown",
    products: [
        .library(name: "SimpleMarkDown", targets: ["SimpleMarkDown"]),
    ],
    targets: [
        .target(name: "SimpleMarkDown"),
        .testTarget(
            name: "SimpleMarkDownTests",
            dependencies: ["SimpleMarkDown"]
        ),
    ]
)
