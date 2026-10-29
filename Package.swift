// swift-tools-version:5.9
import PackageDescription

let version = "0.3.16"

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
            checksum: "b0bfd6247cdc9f5ea8f99b84676092e2152ff316f08e5eba9a7bc46691cc1fc4"
        ),
    ]
)
