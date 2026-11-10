// swift-tools-version: 6.2
import PackageDescription

// Everything the app and the `dontsleep` command share: the power assertion, the session
// that holds it, and the socket the two talk over. It has no interface of its own, which
// keeps it testable with `swift test`.
let package = Package(
    name: "DontSleepKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DontSleepKit", targets: ["DontSleepKit"]),
    ],
    targets: [
        .target(name: "DontSleepKit", linkerSettings: [.linkedFramework("IOKit")]),
        .testTarget(name: "DontSleepKitTests", dependencies: ["DontSleepKit"]),
    ],
    swiftLanguageModes: [.v6]
)
