// swift-tools-version:4.0

import PackageDescription

let package = Package(
  name: "FAST",
  products: [
    .executable(name: "incrementer", targets: ["incrementer"]),
    .library(name: "FAST", targets: ["FAST"]),
    .library(name: "CAffinity", targets: ["CAffinity"]),
  ],
  dependencies: [
    .package(url: "https://github.com/IBM-Swift/HeliumLogger", .exact("1.7.1")),
    .package(url: "https://github.com/Daniel1of1/CSwiftV", .exact("0.0.7")),
    .package(url: "git@github.mit.edu:proteus/CEnergymon", .exact("1.0.1")),
    .package(url: "git@github.mit.edu:proteus/FASTController", .exact("1.0.4")),
    .package(url: "https://github.com/PerfectlySoft/Perfect-HTTPServer", .exact("3.0.10")),
    .package(url: "https://github.com/nicklockwood/Expression", .exact("0.12.11")),
    .package(url: "git@github.mit.edu:proteus/swift-ast", .exact("0.2.0")),
    .package(url: "git@github.mit.edu:proteus/UnconstrainedOptimizer", .exact("0.0.3")),
    .package(url: "git@github.mit.edu:proteus/MulticonstrainedOptimizer", .exact("0.0.13")),
  ],
  targets: [
    .target(name: "FAST", dependencies: [
      "HeliumLogger", "PerfectHTTPServer", "Expression", "SwiftAST", "FASTController", "CSwiftV", "CAffinity", "UnconstrainedOptimizer", "MulticonstrainedOptimizer"]),
    .target(name: "incrementer", dependencies: ["FAST"]),
    .target(name: "CAffinity", path: "Sources/CAffinity"),
	.testTarget(name: "FASTTests", dependencies: ["FAST"]),
  ],
  swiftLanguageVersions: [4]
)
