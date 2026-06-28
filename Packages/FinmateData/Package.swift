// swift-tools-version: 6.0
import PackageDescription

// FinmateData — the live, Supabase-backed DataLayer (docs/03 §3). It implements the
// Domain repository PROTOCOLS (declared in FinmateCore's `Domain`) on top of the
// official `supabase-swift` SDK, with Keychain-backed auth token storage (docs/07 §3).
//
// This package is intentionally SEPARATE from FinmateCore: FinmateCore stays
// dependency-free so `swift test` runs offline. supabase-swift lives only here.
// The app links `DataLayer` and chooses Supabase vs. in-memory repos at the
// composition root based on `FinmateConfig` (URL + anon key present ⇒ Supabase).
//
// Swift-tools 6.0 ⇒ Swift 6 language mode + strict concurrency.
let package = Package(
    name: "FinmateData",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "DataLayer", targets: ["DataLayer"]),
    ],
    dependencies: [
        .package(path: "../FinmateCore"),
        .package(url: "https://github.com/supabase/supabase-swift", from: "2.47.0"),
    ],
    targets: [
        .target(
            name: "DataLayer",
            dependencies: [
                .product(name: "Domain", package: "FinmateCore"),
                .product(name: "Shared", package: "FinmateCore"),
                .product(name: "Supabase", package: "supabase-swift"),
            ]
        ),
    ]
)
