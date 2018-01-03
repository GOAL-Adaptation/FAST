import PackageDescription

let package = Package(
    name: "FAST",
    targets: [
      Target(name: "FAST", dependencies: []),
      Target(name: "incrementer", dependencies: ["FAST"])
    ],
    dependencies: [
      .Package(url: "https://github.com/Zewo/Venice", majorVersion: 0, minor: 14),
      .Package(url: "https://github.com/IBM-Swift/HeliumLogger", majorVersion: 1, minor: 7),
      .Package(url: "https://github.com/Daniel1of1/CSwiftV", majorVersion: 0),
      .Package(url: "git@github.mit.edu:proteus/CEnergymon", majorVersion: 1),
      .Package(url: "git@github.mit.edu:proteus/FASTController", majorVersion: 1),
      .Package(url: "https://github.com/PerfectlySoft/Perfect-SQLite.git", majorVersion: 2),
      .Package(url: "https://github.com/IBM-Swift/Kitura-Request.git", majorVersion: 0),
      .Package(url: "https://github.com/jasonm128/Perfect-HTTPServer", majorVersion: 99),
      .Package(url: "https://github.com/ryuichis/swift-ast", majorVersion: 0)
    ]
)
