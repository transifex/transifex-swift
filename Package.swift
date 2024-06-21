// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "transifex",
    platforms: [
        .iOS(.v12),
        .watchOS(.v4),
        .tvOS(.v12),
        .macOS(.v10_13)
    ],
    products: [
        .library(
            name: "Transifex",
            targets: ["Transifex"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "TransifexObjCRuntime"
        ),
        .target(
            name: "Transifex",
            dependencies: [ "TransifexObjCRuntime" ],
            exclude: [ "TXNativeExtensions.swift" ],
            resources: [
                .copy("Localizable.stringsdict")
            ]
        ),
        .testTarget(
            name: "TransifexTests",
            dependencies: [
                "Transifex",
            ]
        ),
        .testTarget(
            name: "TransifexObjCTests",
            dependencies: [
                "Transifex",
                "TransifexObjCRuntime",
            ]
        ),
    ]
)
