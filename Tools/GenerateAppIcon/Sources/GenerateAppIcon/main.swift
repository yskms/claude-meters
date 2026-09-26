import SwiftUI
import AppKit

// One-off icon generator, not part of the shipped app. Draws the same
// two-ring motif as the menu bar/Popover meters onto a macOS-style rounded
// square, and writes a single 1024x1024 PNG for the App Icon asset
// (Xcode 14+ "single size" app icon — no per-size exports needed).

let canvas: CGFloat = 1024

struct AppIconView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: canvas * 0.1811, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.13, green: 0.15, blue: 0.21),
                            Color(red: 0.05, green: 0.06, blue: 0.10),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            HStack(spacing: 64) {
                ring(percent: 0.62)
                ring(percent: 0.24)
            }
        }
        .frame(width: canvas, height: canvas)
    }

    private func ring(percent: Double) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: 46)
            Circle()
                .trim(from: 0, to: percent)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.42, green: 0.64, blue: 1.0),
                            Color(red: 0.58, green: 0.44, blue: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: 46, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 336, height: 336)
    }
}

// macOS app icon sets still expect the traditional per-size files (idiom
// "mac"), not the single-1024 "universal" shortcut newer iOS templates use —
// Xcode silently mis-renders it ("unassigned child") otherwise. Render once
// at high resolution and downsample for each required slot.
let requiredSizes: [(point: Int, scale: Int, filename: String)] = [
    (16, 1, "icon_16x16.png"),
    (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"),
    (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (512, 2, "icon_512x512@2x.png"),
]

@MainActor
func renderMaster() -> NSImage {
    let renderer = ImageRenderer(content: AppIconView())
    renderer.scale = 1
    renderer.proposedSize = ProposedViewSize(width: canvas, height: canvas)
    guard let nsImage = renderer.nsImage else {
        FileHandle.standardError.write("Failed to render icon\n".data(using: .utf8)!)
        exit(1)
    }
    return nsImage
}

func resized(_ image: NSImage, to pixelSize: Int) -> NSImage {
    // NSImage.lockFocus() draws through the current screen's backing scale
    // factor, so on a Retina display a "16x16 point" NSImage silently comes
    // out as a 32x32-pixel bitmap. Building an NSBitmapImageRep with an
    // explicit pixel count sidesteps that: there's no "points" to scale.
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        FileHandle.standardError.write("Failed to create bitmap rep\n".data(using: .utf8)!)
        exit(1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(
        in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
        from: NSRect(origin: .zero, size: image.size),
        operation: .copy,
        fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()

    let output = NSImage(size: NSSize(width: pixelSize, height: pixelSize))
    output.addRepresentation(rep)
    return output
}

func writePNG(_ image: NSImage, to url: URL) {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("Failed to encode \(url.lastPathComponent)\n".data(using: .utf8)!)
        exit(1)
    }
    do {
        try png.write(to: url)
    } catch {
        FileHandle.standardError.write("Failed to write \(url.path): \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

MainActor.assumeIsolated {
    let outputDir = CommandLine.arguments.count > 1
        ? CommandLine.arguments[1]
        : "."
    let dirURL = URL(fileURLWithPath: outputDir, isDirectory: true)
    try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

    let master = renderMaster()
    for entry in requiredSizes {
        let pixelSize = entry.point * entry.scale
        let image = resized(master, to: pixelSize)
        let url = dirURL.appendingPathComponent(entry.filename)
        writePNG(image, to: url)
        print("Wrote \(entry.filename) (\(pixelSize)x\(pixelSize))")
    }
}
