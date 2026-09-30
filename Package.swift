// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ChromeProfiles",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Auto-updates. Pinned exactly: the sign_update tool that signs each release
        // (scripts/make-appcast.sh) comes from this same package, so the framework in
        // the app and the tool that signs its updates never drift apart.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .executableTarget(
            name: "ChromeProfiles",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/ChromeProfiles"
        ),
        .testTarget(
            name: "ChromeProfilesTests",
            dependencies: ["ChromeProfiles"],
            path: "Tests/ChromeProfilesTests"
        )
    ]
)
