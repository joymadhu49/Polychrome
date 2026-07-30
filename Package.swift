// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ChromeProfiles",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ChromeProfiles",
            path: "Sources/ChromeProfiles"
        ),
        .testTarget(
            name: "ChromeProfilesTests",
            dependencies: ["ChromeProfiles"],
            path: "Tests/ChromeProfilesTests"
        )
    ]
)
