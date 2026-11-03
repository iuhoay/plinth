// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Plinth",
    platforms: [.macOS(.v14)],
    targets: [
        // Resources live in App/Resources and are copied into the .app by
        // scripts/build_app.sh, so the code loads them from Bundle.main.
        .executableTarget(name: "Plinth", path: "Sources/Plinth")
    ]
)
