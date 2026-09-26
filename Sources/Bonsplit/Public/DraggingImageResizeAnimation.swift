import AppKit
import QuartzCore

/// Animates a live drag's leading image to a new image and size, keeping it
/// centered on the pointer, the way Safari turns a dragged tab into a
/// thumbnail. Other dragging items are left as they are.
///
/// AppKit has no animated drag-image change, so this re-sets the dragging
/// frame on a common-mode timer, which keeps firing inside the drag's
/// event-tracking run loop. Frames are screen coordinates.
@MainActor
public final class DraggingImageResizeAnimation {
    private var timer: Timer?

    public init() {}

    /// Starts resizing the drag image from `fromSize` to `toSize`, replacing
    /// any animation already running.
    ///
    /// - Parameters:
    ///   - session: The live dragging session.
    ///   - image: The image to show, drawn scaled into each frame.
    ///   - fromSize: The size at the start, usually the current drag image's.
    ///   - toSize: The final size.
    ///   - duration: The animation length in seconds.
    public func start(
        session: NSDraggingSession,
        image: NSImage,
        from fromSize: NSSize,
        to toSize: NSSize,
        duration: TimeInterval = 0.18
    ) {
        cancel()
        let startTime = CACurrentMediaTime()
        let step: @MainActor () -> Bool = { [weak session] in
            guard let session else { return false }
            let progress = duration > 0 ? min(1, (CACurrentMediaTime() - startTime) / duration) : 1
            let size = Self.size(from: fromSize, to: toSize, progress: progress)
            let frame = Self.frame(of: size, centeredOn: NSEvent.mouseLocation)
            session.enumerateDraggingItems(
                options: [],
                for: nil,
                classes: [NSPasteboardItem.self],
                searchOptions: [:]
            ) { item, index, stop in
                guard index == 0 else {
                    stop.pointee = true
                    return
                }
                item.setDraggingFrame(frame, contents: image)
            }
            return progress < 1
        }
        guard step() else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                if !step() { self?.cancel() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops the animation, leaving the drag image where it is.
    public func cancel() {
        timer?.invalidate()
        timer = nil
    }

    /// The eased size at `progress` (0...1), decelerating toward `toSize`.
    nonisolated static func size(from fromSize: NSSize, to toSize: NSSize, progress: Double) -> NSSize {
        let clamped = min(max(progress, 0), 1)
        let eased = CGFloat(1 - pow(1 - clamped, 3))
        return NSSize(
            width: fromSize.width + (toSize.width - fromSize.width) * eased,
            height: fromSize.height + (toSize.height - fromSize.height) * eased
        )
    }

    /// A frame of `size` whose center is `point`.
    nonisolated static func frame(of size: NSSize, centeredOn point: NSPoint) -> NSRect {
        NSRect(
            x: point.x - size.width / 2,
            y: point.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
