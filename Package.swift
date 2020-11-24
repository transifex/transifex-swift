// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TransifexNative",
    platforms: [
        .iOS(.v10)
    ],
    products: [
        .library(
            name: "TransifexNative",
            targets: ["TransifexNative"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "TransifexNativeObjCRuntime",
            dependencies: []
        ),
        .target(
            name: "TransifexNative",
            dependencies: [ "TransifexNativeObjCRuntime" ],
            resources: [
                .copy("Localizable.stringsdict")
            ]
        ),
        .testTarget(
            name: "TransifexNativeTests",
            dependencies: [
                "TransifexNative",
            ]
        ),
        .testTarget(
            name: "TransifexNativeObjCTests",
            dependencies: [
                "TransifexNativeObjCRuntime",
            ]
        ),
    ]
)
