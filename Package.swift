// swift-tools-version:5.9
import PackageDescription

let version = "0.3.13"

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
            checksum: "a5a366f1a119c82d5ce156c702b78779d2a32c7501c2d12c4ee08181066fe221"
        ),
    ]
)
