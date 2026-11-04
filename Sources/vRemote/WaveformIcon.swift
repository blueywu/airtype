import AppKit

/// Native template rendering of the approved 24 × 24 SVG, without an enclosing box.
enum WaveformIcon {
    static var image: NSImage {
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { _ in
            NSColor.black.setStroke()
            let path = NSBezierPath(); path.lineWidth = 1.8; path.lineCapStyle = .round
            for (x, y, h) in [(5.0, 10.5, 3.0), (8.5, 8.0, 8.0), (12.0, 5.5, 13.0), (15.5, 8.0, 8.0), (19.0, 10.5, 3.0)] {
                path.move(to: NSPoint(x: x, y: y)); path.line(to: NSPoint(x: x, y: y + h))
            }
            path.stroke(); return true
        }
        image.isTemplate = true
        return image
    }
}
