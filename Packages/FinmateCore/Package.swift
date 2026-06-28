// swift-tools-version: 6.0
import PackageDescription

// FinmateCore — the platform-agnostic core of Finmate (M0 Foundations).
// Pure logic per docs/13-algorithms-and-calculations.md; no SwiftUI/UIKit so it
// builds and unit-tests on macOS via `swift test`, and links into the iOS app.
// Swift-tools 6.0 ⇒ Swift 6 language mode + strict concurrency by default.
let package = Package(
    name: "FinmateCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Shared", targets: ["Shared"]),
    ],
    targets: [
        .target(name: "Shared"),
        .target(name: "Domain", dependencies: ["Shared"]),
        .testTarget(name: "SharedTests", dependencies: ["Shared"]),
        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
    ]
)
