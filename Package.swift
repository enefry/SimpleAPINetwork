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
    .package(url: "https://github.com/enefry/LoggerProxy.git", from: "1.1.0")
  ],
  targets: [
    .target(
      name: "SimpleAPINetwork",
      dependencies: [
        .product(name: "LoggerProxy", package: "LoggerProxy")
      ],
      path: "SimpleAPINetwork",
      linkerSettings: [
        .linkedFramework("Foundation")
      ]
    )
  ]
)
