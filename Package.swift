// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CoreDataJSONExport",
	 platforms: [
			  .macOS(.v10_15),
			  .iOS(.v13),
			  .watchOS(.v5)
		 ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "CoreDataJSONExport",
            targets: ["CoreDataJSONExport"]),
    ],
    dependencies: [
        .package(url: "https://github.com/bengottlieb/Suite.git", from: "0.9.12"),
		  .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.10")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "CoreDataJSONExport",
            dependencies: ["Suite", "ZIPFoundation"]),
    ]
)
