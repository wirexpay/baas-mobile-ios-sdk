// swift-tools-version:5.9
import PackageDescription

let version = "0.3.1"

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
            checksum: "52550b971e9d2cd67a2afe62e503589c34e0c7fafb894b15dc8586fcbe7c0a06"
        ),
    ]
)
