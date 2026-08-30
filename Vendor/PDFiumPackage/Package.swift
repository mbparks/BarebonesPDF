// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PDFiumPackage",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CPDFium", targets: ["CPDFium"])
    ],
    targets: [
        .binaryTarget(
            name: "PDFium",
            url: "https://github.com/espresso3389/pdfium-xcframework/releases/download/v144.0.7811.0-20260502-190206/PDFium-chromium-7811-20260502-190206.xcframework.zip",
            checksum: "948d9257f53f01cbed74b81bb8adc8758e52ac9390751772de7889026d32d5a1"
        ),
        .target(
            name: "CPDFium",
            dependencies: ["PDFium"],
            publicHeadersPath: "include"
        )
    ]
)
