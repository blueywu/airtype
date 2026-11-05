import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Reproducible vector-derived icon: transparent outside the macOS tile.
let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: size * 4, space: colorSpace,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.setAllowsAntialiasing(true)
let tile = CGRect(x: 64, y: 64, width: 896, height: 896)
let shape = CGPath(roundedRect: tile, cornerWidth: 200, cornerHeight: 200, transform: nil)
context.addPath(shape)
context.saveGState()
context.clip()
let colors = [CGColor(red: 0.10, green: 0.12, blue: 0.14, alpha: 1),
              CGColor(red: 0.23, green: 0.26, blue: 0.29, alpha: 1)] as CFArray
let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 800, y: 64), end: CGPoint(x: 200, y: 960), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
context.restoreGState()
context.addPath(shape)
context.setStrokeColor(CGColor(red: 0.75, green: 0.81, blue: 0.84, alpha: 0.16))
context.setLineWidth(2)
context.strokePath()
context.setStrokeColor(CGColor(red: 0.52, green: 0.91, blue: 0.68, alpha: 1))
context.setLineCap(.round)
context.setLineWidth(64)
for (x, height) in [(264.0, 106.0), (388.0, 284.0), (512.0, 462.0), (636.0, 284.0), (760.0, 106.0)] {
    context.move(to: CGPoint(x: x, y: 512 - height / 2))
    context.addLine(to: CGPoint(x: x, y: 512 + height / 2))
    context.strokePath()
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(dest))
print(output.path)
