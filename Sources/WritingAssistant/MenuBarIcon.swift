import AppKit

enum MenuBarIcon {
    static func image(for status: AppStatus) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()

        drawBubble()

        switch status {
        case .working:
            drawWorkingDots()
        case .failed:
            drawFailureMark()
        default:
            drawTextLines()
            drawSpark()
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private static func drawBubble() {
        NSColor.black.setStroke()

        let bubble = NSBezierPath(
            roundedRect: NSRect(x: 2.5, y: 4.0, width: 13.0, height: 11.0),
            xRadius: 3.4,
            yRadius: 3.4
        )
        bubble.lineWidth = 1.6
        bubble.stroke()

        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 6.0, y: 4.2))
        tail.line(to: NSPoint(x: 4.7, y: 1.8))
        tail.line(to: NSPoint(x: 8.1, y: 4.2))
        tail.lineWidth = 1.6
        tail.lineJoinStyle = .round
        tail.lineCapStyle = .round
        tail.stroke()
    }

    private static func drawTextLines() {
        NSColor.black.setFill()

        NSBezierPath(
            roundedRect: NSRect(x: 5.4, y: 10.5, width: 5.5, height: 1.2),
            xRadius: 0.6,
            yRadius: 0.6
        ).fill()
        NSBezierPath(
            roundedRect: NSRect(x: 5.4, y: 7.5, width: 7.2, height: 1.2),
            xRadius: 0.6,
            yRadius: 0.6
        ).fill()
    }

    private static func drawSpark() {
        NSColor.black.setStroke()

        let spark = NSBezierPath()
        spark.move(to: NSPoint(x: 13.0, y: 11.1))
        spark.line(to: NSPoint(x: 13.0, y: 14.0))
        spark.move(to: NSPoint(x: 11.55, y: 12.55))
        spark.line(to: NSPoint(x: 14.45, y: 12.55))
        spark.lineWidth = 1.25
        spark.lineCapStyle = .round
        spark.stroke()
    }

    private static func drawWorkingDots() {
        NSColor.black.setFill()

        for x in [6.2, 9.0, 11.8] {
            NSBezierPath(ovalIn: NSRect(x: x, y: 8.5, width: 1.6, height: 1.6)).fill()
        }
    }

    private static func drawFailureMark() {
        NSColor.black.setStroke()

        let mark = NSBezierPath()
        mark.move(to: NSPoint(x: 9.0, y: 7.2))
        mark.line(to: NSPoint(x: 9.0, y: 11.3))
        mark.lineWidth = 1.6
        mark.lineCapStyle = .round
        mark.stroke()

        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 8.2, y: 5.4, width: 1.6, height: 1.6)).fill()
    }
}
