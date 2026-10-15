// swift-tools-version:5.9
import PackageDescription

let version = "0.3.7"

let package = Package(
    name: "WirexMobileSDK",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "WirexMobileSDK", targets: ["WirexMobileSDK"]),
    ],
    targets: [
        .binaryTarget(
            name: "WirexMobileSDK",
            url: "https://github.com/wirexpay/baas-mobile-ios-sdk/releases/download/\(version)/WirexMobileSDK.xcframework.zip",
            checksum: "f19d49bf1ebab1fb12355b4950607ad561b5a8be33d5ae3a5c61c0e32859bdcc"
        ),
    ]
)
