// swift-tools-version:4.0

import PackageDescription

let package = Package(
  name: "FAST",
  products: [
    .executable(name: "incrementer", targets: ["incrementer"]),
    .library(name: "FAST", targets: ["FAST"]),
  ],
  dependencies: [
    .package(url: "https://github.com/IBM-Swift/HeliumLogger", .exact("1.7.1")),
    .package(url: "https://github.com/Daniel1of1/CSwiftV", .exact("0.0.7")),
    .package(url: "git@github.mit.edu:proteus/CEnergymon", .exact("1.0.1")),
    .package(url: "git@github.mit.edu:proteus/FASTController", .exact("1.0.3")),
    .package(url: "https://github.com/PerfectlySoft/Perfect-HTTPServer", .exact("3.0.10")),
    .package(url: "https://github.com/ryuichis/swift-ast", .exact("0.2.0")),
  ],
  targets: [
    .target(name: "FAST", dependencies: [
      "HeliumLogger", "PerfectHTTPServer", "SwiftAST", "FASTController", "CSwiftV"]),
    .target(name: "incrementer", dependencies: ["FAST"]),
    .testTarget(name: "FASTTests", dependencies: ["FAST"]),
  ],
  swiftLanguageVersions: [4]
)
