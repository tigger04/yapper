// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "yapper",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "YapperKit",
            targets: ["YapperKit"]
        ),
        .executable(
            name: "yapper",
            targets: ["yapper"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.30.2"),
        .package(url: "https://github.com/mlalma/MisakiSwift", exact: "1.0.6"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0"),
    ],
    targets: [
        .target(
            name: "YapperKit",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "MLXFFT", package: "mlx-swift"),
                .product(name: "MisakiSwift", package: "MisakiSwift"),
            ]
        ),
        .executableTarget(
            name: "yapper",
            dependencies: [
                "YapperKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "YapperKitTests",
            dependencies: ["YapperKit"],
            path: "Tests/regression/YapperKitTests"
        ),
    ]
)
