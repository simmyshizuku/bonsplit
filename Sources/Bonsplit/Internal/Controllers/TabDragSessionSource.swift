import AppKit

/// Retained AppKit source whose terminal callback owns tab-drag cancellation.
@MainActor
final class TabDragSessionSource: NSObject, NSDraggingSource {
    private let generation: Int
    private let transfer: TabDragTransfer
    private let transferRegistration: TabDragTransferRegistration
    private let transferRegistry: TabDragTransferRegistry
    private weak var controller: SplitViewController?
    private var didFinish = false
    // Keep the source view owned until `endedAt`; AppKit owns the session and
    // retains this source while its native drag is active.
    // AppKit's drag manager may outlive the SwiftUI tab view that initiated the
    // drag; releasing either object during an accepted drop can strand the
    // WindowManager drag connection.
    private var sourceView: NSView?
    /// The tab's own drag image and its origin relative to the pointer, used
    /// to restore the image after a detached preview.
    private var tabDragImage: (image: NSImage, size: NSSize, originFromPointer: CGVector)?
    private var isShowingDetachedPreview = false
    private let resizeAnimation = DraggingImageResizeAnimation()

    init(
        generation: Int,
        transfer: TabDragTransfer,
        transferRegistration: TabDragTransferRegistration,
        transferRegistry: TabDragTransferRegistry,
        controller: SplitViewController
    ) {
        self.generation = generation
        self.transfer = transfer
        self.transferRegistration = transferRegistration
        self.transferRegistry = transferRegistry
        self.controller = controller
        super.init()
    }

    /// Retains the source view until AppKit delivers this source's `endedAt` callback.
    func bind(sourceView: NSView) {
        guard !didFinish else { return }
        self.sourceView = sourceView
    }

    /// Records the tab's drag image so a detached preview can be undone when
    /// the pointer returns over a destination.
    func setTabDragImage(_ image: NSImage, screenFrame: NSRect, pointer: NSPoint) {
        tabDragImage = (
            image,
            screenFrame.size,
            CGVector(dx: screenFrame.minX - pointer.x, dy: screenFrame.minY - pointer.y)
        )
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        let preview = detachedPreview(atScreenPoint: screenPoint)
        if let preview {
            guard !isShowingDetachedPreview else { return }
            isShowingDetachedPreview = true
            // Grow (or shrink) from the tab's image into the thumbnail,
            // centered on the pointer.
            resizeAnimation.start(
                session: session,
                image: preview.image,
                from: tabDragImage?.size ?? preview.size,
                to: preview.size
            )
        } else if isShowingDetachedPreview, let tabDragImage {
            resizeAnimation.cancel()
            // Frames are in screen coordinates when no view is given.
            let frame = NSRect(
                x: screenPoint.x + tabDragImage.originFromPointer.dx,
                y: screenPoint.y + tabDragImage.originFromPointer.dy,
                width: tabDragImage.size.width,
                height: tabDragImage.size.height
            )
            session.enumerateDraggingItems(
                options: [],
                for: nil,
                classes: [NSPasteboardItem.self],
                searchOptions: [:]
            ) { item, _, _ in
                item.setDraggingFrame(frame, contents: tabDragImage.image)
            }
            isShowingDetachedPreview = false
        }
    }

    /// Asks the host for the image to show while the drag is over no destination.
    func detachedPreview(atScreenPoint screenPoint: NSPoint) -> TabDragDetachedPreview? {
        controller?.tabDragDetachedPreview(transfer, atScreenPoint: screenPoint)
    }

    /// Completes a superseded source after a later native pointer boundary
    /// proves that AppKit has left this source's drag loop.
    func finishAfterNativeBoundary() {
        finishDrag()
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        let isCancellation = Self.isCancellation(NSApp.currentEvent)
#if DEBUG
        dlog(
            "tab.dragEnded op=\(operation.rawValue) cancel=\(isCancellation ? 1 : 0) " +
            "event=\(NSApp.currentEvent.map { String($0.type.rawValue) } ?? "nil") " +
            "point=\(Int(screenPoint.x)),\(Int(screenPoint.y))"
        )
#endif
        finishDrag()
        // The system drag pasteboard advertises this session's transfer type
        // until another drag replaces it, which keeps host drop-capture
        // hit-testing armed forever and blocks the next tab drag from starting.
        transferRegistration.clearResidualCapability(from: session.draggingPasteboard)
        if operation.isEmpty, !isCancellation {
            reportUnplacedRelease(atScreenPoint: screenPoint)
        }
    }

    /// Reports a release that no destination accepted, after the source's
    /// terminal cleanup, so the host may relocate the tab (for example into a
    /// new window) without racing this drag's own state.
    func reportUnplacedRelease(atScreenPoint screenPoint: NSPoint) {
        controller?.tabDragDidEndWithoutDrop(transfer, atScreenPoint: screenPoint)
    }

    /// AppKit ends an Escape-cancelled drag with the same empty operation as
    /// a release over no destination; only the triggering event differs.
    static func isCancellation(_ event: NSEvent?) -> Bool {
        event?.type == .keyDown
    }

    func finishDrag() {
        guard !didFinish else { return }
        didFinish = true
        resizeAnimation.cancel()
        transferRegistry.endNativeDrag(transferRegistration)
        controller?.nativeTabDragSessionDidEnd(generation: generation)
        sourceView = nil
    }
}
