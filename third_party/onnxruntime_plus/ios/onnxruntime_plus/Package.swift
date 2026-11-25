// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "onnxruntime_plus",
    platforms: [
        .iOS("11.0")
    ],
    products: [
        .library(name: "onnxruntime-plus", targets: ["onnxruntime_plus"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .binaryTarget(
            name: "onnxruntimeC",
            // ONNX Runtime 1.22.0 from the Microsoft.ML.OnnxRuntime NuGet package
            // (runtimes/ios/native); see KOVER_PATCH.md.
            path: "onnxruntime.xcframework.zip"
        ),
        .target(
            name: "onnxruntime_plus",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                "onnxruntimeC"
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                // The Dart side looks the C API up at runtime, so keep it linked.
                .unsafeFlags(["-weak_framework", "CoreML", "-Wl,-u,_OrtGetApiBase"])
            ]
        )
    ]
)