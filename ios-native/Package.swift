// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "FishCore", platforms: [.iOS(.v16), .macOS(.v13)], products: [.library(name: "FishCore", targets: ["FishCore"])], targets: [.target(name: "FishCore"), .testTarget(name: "FishCoreTests", dependencies: ["FishCore"], path: "Tests")])
