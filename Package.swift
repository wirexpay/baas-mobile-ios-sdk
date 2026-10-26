// swift-tools-version:5.9
import PackageDescription

let version = "0.3.15"

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
            checksum: "4f6c986c391cb1a6cd1675ed7dcaa18768c22100ab9c04cf1c883427af590030"
        ),
    ]
)
