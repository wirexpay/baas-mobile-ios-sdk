// swift-tools-version:5.9
import PackageDescription

let version = "0.3.14"

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
            checksum: "29b7b11de2ce65728e34d0fc6d6886c2526f47acb63c1ca371ed5ed1bb829707"
        ),
    ]
)
