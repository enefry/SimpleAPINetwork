// swift-tools-version:5.9

import PackageDescription

let package = Package(
  name: "SimpleAPINetwork",
  platforms: [
    .iOS(.v13),
    .macOS(.v11),
  ],
  products: [
    .library(name: "SimpleAPINetwork", targets: ["SimpleAPINetwork"])
  ],
  dependencies: [
    .package(url: "https://github.com/enefry/LoggerProxy.git", from: "2.0.0"),
    .package(path: "../../Utils/ConcurrencyCollection"),
  ],
  targets: [
    .target(
      name: "SimpleAPINetwork",
      dependencies: [
        .product(name: "LoggerProxy", package: "LoggerProxy"),
        .product(name: "ConcurrencyCollection", package: "ConcurrencyCollection")
      ],
      path: "SimpleAPINetwork",
      linkerSettings: [
        .linkedFramework("Foundation")
      ]
    )
  ]
)
