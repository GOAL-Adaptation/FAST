import PackageDescription

let package = Package(
    name: "FAST",
    dependencies: [
      .Package(url: "https://github.com/Zewo/Venice.git", majorVersion: 0, minor: 14),
      .Package(url: "git@github.mit.edu:proteus/CEnergymon.git", majorVersion: 1)
    ]
)
