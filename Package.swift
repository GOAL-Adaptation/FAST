// swift-tools-version:4.0

import PackageDescription

let package = Package(
  name: "FAST",
  products: [
    .executable(name: "incrementer", targets: ["incrementer"]),
    .library(name: "FAST", targets: ["FAST"]),
  ],
  dependencies: [
    .package(url: "https://github.com/Zewo/Venice", .exact("0.20.0")),
    .package(url: "https://github.com/IBM-Swift/HeliumLogger", .exact("1.7.1")),
    .package(url: "https://github.com/Daniel1of1/CSwiftV", .exact("0.0.7")),
    .package(url: "git@github.mit.edu:proteus/CEnergymon", .exact("1.0.1")),
    .package(url: "git@github.mit.edu:proteus/FASTController", .exact("1.0.2")),
    .package(url: "https://github.com/PerfectlySoft/Perfect-SQLite.git", .exact("3.0.1")),
    .package(url: "https://github.com/IBM-Swift/CCurl", .exact("1.0.0")),
    .package(url: "https://github.com/jasonm128/Perfect-HTTPServer", .exact("99.0.2")),
    .package(url: "https://github.com/ryuichis/swift-ast", .revision("06c530a196ce8ef55fc03ecfa542ac7652cbc440")),
  ],
  targets: [
    .target(name: "FAST", dependencies: [
      "HeliumLogger", "PerfectHTTPServer", "PerfectSQLite", "SwiftAST", "FASTController", "CSwiftV", "Venice"]),
    .target(name: "incrementer", dependencies: ["FAST"])
  ],
  swiftLanguageVersions: [4]
)
