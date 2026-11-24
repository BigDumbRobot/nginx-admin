// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NginxAdmin",
    platforms: [.macOS("14.2")],
    targets: [
        .executableTarget(
            name: "NginxAdmin",
            path: "Sources/NginxAdmin"
        )
    ]
)
