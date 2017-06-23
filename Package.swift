import PackageDescription

let package = Package(
    name: "FAST",
    dependencies: [
      .Package(url: "https://github.com/Zewo/Venice", majorVersion: 0, minor: 14),
      .Package(url: "https://github.com/IBM-Swift/HeliumLogger", majorVersion: 1, minor: 7),
      .Package(url: "https://github.com/Daniel1of1/CSwiftV", majorVersion: 0),
      .Package(url: "git@github.mit.edu:proteus/CEnergymon", majorVersion: 1),
      .Package(url: "git@github.mit.edu:proteus/FASTController", majorVersion: 1),
      .Package(url: "https://github.com/adamduracz/Nifty.git", majorVersion: 99),
      .Package(url: "https://github.com/barfer/Perfect-SQLite.git", majorVersion: 2),
      .Package(url: "https://github.com/IBM-Swift/BlueSocket", majorVersion: 0)
    ]
)
